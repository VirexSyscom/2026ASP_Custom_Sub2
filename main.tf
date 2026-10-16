############################################
# main.tf
#   Hub 網路（Hub-Network-RG）
#
#   統一格式：
#     1. 命名一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.<層>_tags, { ResourceType = ... }) 產生
#     3. 本組態僅管理一個資源群組：Hub 網路（Hub-Network-RG）
#        RG 名稱一律不套用前綴，但標籤一律套用
#     4. 支援 create_hub_resource_group 切換「新建 / 沿用既有」
#     5. Spoke VNet 與 Private DNS Zone 由 Spoke 網路組態管理，
#        本組態僅以 data 來源參照，用於 VNet Peering 與 DNS 連結
############################################

data "azurerm_client_config" "current" {}

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # ---------- 統一命名表 ----------
  name = {
    # ===== Hub 網路層 =====
    hub_vnet           = "${local.prefix}Hub-VNET"
    hub_bastion_subnet = "AzureBastionSubnet" # Azure 保留名稱，不可加前綴
    gateway_subnet     = "GatewaySubnet"      # Azure 保留名稱，不可加前綴
    hub_bastion_pip    = "${local.prefix}hub-vnet-bastion-pip"
    hub_bastion        = "${local.prefix}hub-vnet-bastion"
    hub_bastion_ipcfg  = "${local.prefix}bastion-ipconfig"
    vpn_gateway_pip    = "${local.prefix}vpn-gateway-pip"
    vpn_gateway        = "${local.prefix}vpn-gateway"
    vpn_gateway_ipcfg  = "${local.prefix}vpn-gateway-ipconfig"
    local_gateway      = "${local.prefix}fortigate-local-gateway"
    vpn_connection     = "${local.prefix}to-fortigate-vpn"
    peer_hub_to_spoke  = "${local.prefix}peer-hub-to-spoke"
    peer_spoke_to_hub  = "${local.prefix}peer-spoke-to-hub"
    peer_hub_to_uat    = "${local.prefix}peer-hub-to-uat-spoke"
    peer_uat_to_hub    = "${local.prefix}peer-uat-spoke-to-hub"

    # ===== 既有 Spoke 網路層（僅供 data 參照，命名規則與 Spoke 組態一致）=====
    spoke_vnet     = "${local.prefix}Spoke-VNET"
    uat_spoke_vnet = "${local.prefix}UAT-Spoke-VNET"
  }

  # ---------- 統一標籤 ----------
  common_tags = merge(
    {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      Location    = var.location
      Prefix      = var.name_prefix
    },
    var.cost_center == "" ? {} : { CostCenter = var.cost_center },
    var.tags
  )

  # 各層專屬標籤（在共用標籤之上疊加）
  hub_tags = merge(local.common_tags, { Layer = "Network", Tier = "Hub" }, var.hub_tags)

  # ---------- 資源群組解析 ----------
  hub_rg_name     = var.create_hub_resource_group ? azurerm_resource_group.hub[0].name : data.azurerm_resource_group.hub_existing[0].name
  hub_rg_location = var.create_hub_resource_group ? azurerm_resource_group.hub[0].location : data.azurerm_resource_group.hub_existing[0].location

  # Spoke VNet / Private DNS Zone 所在的既有 Spoke 網路 RG
  network_rg_name = var.network_resource_group_name

  subscription_id = data.azurerm_client_config.current.subscription_id

  # Peering 時是否可使用 Hub 的 VPN Gateway 進行 Gateway Transit
  peering_gateway_transit = var.enable_hub_spoke_peering && var.create_vpn_gateway
}

############################################
# 資源群組（Hub 網路 RG，名稱不套用前綴，但一律套用統一標籤）
############################################
data "azurerm_resource_group" "hub_existing" {
  count = var.create_hub_resource_group ? 0 : 1
  name  = var.hub_resource_group_name
}

resource "azurerm_resource_group" "hub" {
  count    = var.create_hub_resource_group ? 1 : 0
  name     = var.hub_resource_group_name
  location = var.location

  tags = merge(local.hub_tags, {
    ResourceType = "ResourceGroup"
  })
}

############################################
# 既有 Spoke 網路資源（由 Spoke 網路組態建立，此處僅參照）
#   部署順序：先部署 Spoke 網路組態，再部署本組態
############################################
data "azurerm_virtual_network" "spoke" {
  count               = var.enable_hub_spoke_peering ? 1 : 0
  name                = local.name.spoke_vnet
  resource_group_name = local.network_rg_name
}

data "azurerm_virtual_network" "uat_spoke" {
  count               = var.enable_hub_spoke_peering ? 1 : 0
  name                = local.name.uat_spoke_vnet
  resource_group_name = local.network_rg_name
}

data "azurerm_private_dns_zone" "blob" {
  count               = var.enable_hub_spoke_peering ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.network_rg_name
}

data "azurerm_private_dns_zone" "sql" {
  count               = var.enable_hub_spoke_peering ? 1 : 0
  name                = "privatelink.database.windows.net"
  resource_group_name = local.network_rg_name
}

data "azurerm_private_dns_zone" "keyvault" {
  count               = var.enable_hub_spoke_peering ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.network_rg_name
}

############################################
# 【Hub】Virtual Network
############################################
resource "azurerm_virtual_network" "hub" {
  name                = local.name.hub_vnet
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  address_space       = var.hub_vnet_address_space

  tags = merge(local.hub_tags, {
    ResourceType = "VirtualNetwork"
    Workload     = "Hub-Network"
  })
}

# Azure Bastion 專用子網路，名稱為 Azure 保留字，不可加前綴
resource "azurerm_subnet" "hub_bastion" {
  count                = var.create_hub_bastion ? 1 : 0
  name                 = local.name.hub_bastion_subnet
  resource_group_name  = local.hub_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.hub_bastion_subnet_prefixes
}

# VPN Gateway 專用子網路，名稱為 Azure 保留字，不可加前綴
resource "azurerm_subnet" "gateway" {
  count                = var.create_vpn_gateway ? 1 : 0
  name                 = local.name.gateway_subnet
  resource_group_name  = local.hub_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.gateway_subnet_prefixes
}

############################################
# 【Hub】Bastion（傳統模式：Standard 靜態公用 IP）
############################################
resource "azurerm_public_ip" "hub_bastion" {
  count               = var.create_hub_bastion ? 1 : 0
  name                = local.name.hub_bastion_pip
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"

  tags = merge(local.hub_tags, {
    ResourceType = "PublicIP"
    Purpose      = "Bastion-Frontend"
  })
}

resource "azurerm_bastion_host" "hub" {
  count               = var.create_hub_bastion ? 1 : 0
  name                = local.name.hub_bastion
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  sku                 = var.hub_bastion_sku

  tags = merge(local.hub_tags, {
    ResourceType = "Bastion"
    Purpose      = "SecureRemoteAccess"
    AccessModel  = "PublicIP"
    Scope        = "HubVNet"
  })

  ip_configuration {
    name                 = local.name.hub_bastion_ipcfg
    subnet_id            = azurerm_subnet.hub_bastion[0].id
    public_ip_address_id = azurerm_public_ip.hub_bastion[0].id
  }
}

############################################
# 【Hub】VPN Gateway
############################################
resource "azurerm_public_ip" "vpn_gateway" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.vpn_gateway_pip
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  zones               = var.vpn_gateway_public_ip_zones

  tags = merge(local.hub_tags, {
    ResourceType = "PublicIP"
    Purpose      = "VPNGateway-Frontend"
  })
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.vpn_gateway
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  type          = "Vpn"
  vpn_type      = "RouteBased"
  active_active = false

  # azurerm 4.x：enable_bgp 已棄用並更名為 bgp_enabled，v5.0 將移除
  bgp_enabled = var.enable_bgp

  sku        = var.vpn_gateway_sku
  generation = "Generation2"

  tags = merge(local.hub_tags, {
    ResourceType = "VirtualNetworkGateway"
    Purpose      = "Site-to-Site"
  })

  ip_configuration {
    name                          = local.name.vpn_gateway_ipcfg
    public_ip_address_id          = azurerm_public_ip.vpn_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }
}

############################################
# 【Hub】Local Network Gateway（地端 FortiGate）
############################################
resource "azurerm_local_network_gateway" "fortigate" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.local_gateway
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  gateway_address = var.onprem_vpn_public_ip
  address_space   = var.onprem_address_spaces

  tags = merge(local.hub_tags, {
    ResourceType = "LocalNetworkGateway"
    Purpose      = "OnPremises-FortiGate"
  })
}

############################################
# 【Hub】Site-to-Site IPsec Connection
############################################
resource "azurerm_virtual_network_gateway_connection" "fortigate" {
  count               = var.create_vpn_gateway && var.create_vpn_connection ? 1 : 0
  name                = local.name.vpn_connection
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.fortigate[0].id
  shared_key                 = var.vpn_shared_key

  # azurerm 4.x：enable_bgp 已棄用並更名為 bgp_enabled
  bgp_enabled = var.enable_bgp

  tags = merge(local.hub_tags, {
    ResourceType = "VpnConnection"
    Purpose      = "Site-to-Site"
  })
}

############################################
# 【Hub <-> Spoke】VNet Peering
#   Spoke 端 Peering 建立於 Spoke 網路 RG 的既有 VNet 上
############################################
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                     = var.enable_hub_spoke_peering ? 1 : 0
  name                      = local.name.peer_hub_to_spoke
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = data.azurerm_virtual_network.spoke[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = local.peering_gateway_transit
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                     = var.enable_hub_spoke_peering ? 1 : 0
  name                      = local.name.peer_spoke_to_hub
  resource_group_name       = local.network_rg_name
  virtual_network_name      = data.azurerm_virtual_network.spoke[0].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = local.peering_gateway_transit

  depends_on = [azurerm_virtual_network_peering.hub_to_spoke]
}

resource "azurerm_virtual_network_peering" "hub_to_uat" {
  count                     = var.enable_hub_spoke_peering ? 1 : 0
  name                      = local.name.peer_hub_to_uat
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = data.azurerm_virtual_network.uat_spoke[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = local.peering_gateway_transit
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

resource "azurerm_virtual_network_peering" "uat_to_hub" {
  count                     = var.enable_hub_spoke_peering ? 1 : 0
  name                      = local.name.peer_uat_to_hub
  resource_group_name       = local.network_rg_name
  virtual_network_name      = data.azurerm_virtual_network.uat_spoke[0].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = local.peering_gateway_transit

  depends_on = [azurerm_virtual_network_peering.hub_to_uat]
}

############################################
# 【Hub】Private DNS Zone 連結
#   Zone 本身位於 Spoke 網路 RG，此處僅建立 Hub VNet 的連結
############################################
resource "azurerm_private_dns_zone_virtual_network_link" "blob_hub" {
  count                 = var.enable_hub_spoke_peering ? 1 : 0
  name                  = "${local.prefix}link-hub-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = data.azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false

  tags = merge(local.hub_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_hub" {
  count                 = var.enable_hub_spoke_peering ? 1 : 0
  name                  = "${local.prefix}link-hub-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = data.azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false

  tags = merge(local.hub_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_hub" {
  count                 = var.enable_hub_spoke_peering ? 1 : 0
  name                  = "${local.prefix}link-hub-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = data.azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false

  tags = merge(local.hub_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}
