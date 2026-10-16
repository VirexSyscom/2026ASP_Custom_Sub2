############################################
# outputs.tf
#   統一格式：共用驗證 → 資源群組 → Hub 網路
############################################

############################################
# 共用：命名與標籤驗證
############################################
output "name_prefix_applied" {
  description = "實際套用的前綴字串"
  value       = local.prefix
}

output "resource_names" {
  description = "所有資源的最終名稱，可用於驗證前綴是否正確套用"
  value       = local.name
}

output "common_tags" {
  description = "套用到所有資源的共用標籤基準"
  value       = local.common_tags
}

output "hub_tags_applied" {
  description = "Hub 網路資源群組套用的標籤"
  value       = local.hub_tags
}

############################################
# 資源群組
############################################
output "resource_groups" {
  description = "本組態管理的資源群組"
  value = {
    hub = local.hub_rg_name
  }
}

############################################
# Hub 網路層
############################################
output "hub_vnet" {
  description = "Hub VNet 資訊"
  value = {
    id   = azurerm_virtual_network.hub.id
    name = azurerm_virtual_network.hub.name
  }
}

output "hub_subnet_ids" {
  description = "Hub 子網路資源 ID"
  value = {
    hub_bastion = var.create_hub_bastion ? azurerm_subnet.hub_bastion[0].id : null
    gateway     = var.create_vpn_gateway ? azurerm_subnet.gateway[0].id : null
  }
}

output "hub_bastion" {
  description = "Hub Bastion 資訊"
  value = {
    id        = try(azurerm_bastion_host.hub[0].id, null)
    sku       = try(azurerm_bastion_host.hub[0].sku, null)
    public_ip = try(azurerm_public_ip.hub_bastion[0].ip_address, null)
  }
}

output "vpn_gateway" {
  description = "VPN Gateway 與 Local Network Gateway 資訊"
  value = {
    id                       = try(azurerm_virtual_network_gateway.vpn[0].id, null)
    public_ip                = try(azurerm_public_ip.vpn_gateway[0].ip_address, null)
    sku                      = try(azurerm_virtual_network_gateway.vpn[0].sku, null)
    bgp_enabled              = try(azurerm_virtual_network_gateway.vpn[0].bgp_enabled, null)
    local_network_gateway_id = try(azurerm_local_network_gateway.fortigate[0].id, null)
  }
}

output "vpn_connection" {
  description = "Site-to-Site VPN Connection 資訊"
  value = {
    created = var.create_vpn_gateway && var.create_vpn_connection
    id      = try(azurerm_virtual_network_gateway_connection.fortigate[0].id, null)
    name    = try(azurerm_virtual_network_gateway_connection.fortigate[0].name, null)
  }
}

output "hub_spoke_peering" {
  description = "Hub 與 Spoke 之間的 VNet Peering 狀態"
  value = {
    enabled         = var.enable_hub_spoke_peering
    gateway_transit = local.peering_gateway_transit
    hub_to_spoke_id = try(azurerm_virtual_network_peering.hub_to_spoke[0].id, null)
    spoke_to_hub_id = try(azurerm_virtual_network_peering.spoke_to_hub[0].id, null)
    hub_to_uat_id   = try(azurerm_virtual_network_peering.hub_to_uat[0].id, null)
    uat_to_hub_id   = try(azurerm_virtual_network_peering.uat_to_hub[0].id, null)
  }
}

output "hub_private_dns_zone_links" {
  description = "Hub VNet 的 Private DNS Zone 連結 ID"
  value = {
    blob      = try(azurerm_private_dns_zone_virtual_network_link.blob_hub[0].id, null)
    sql       = try(azurerm_private_dns_zone_virtual_network_link.sql_hub[0].id, null)
    key_vault = try(azurerm_private_dns_zone_virtual_network_link.keyvault_hub[0].id, null)
  }
}
