############################################
# terraform.tfvars
############################################

############################################
# 訂閱：由 Azure DevOps Service Connection 注入
# ARM_SUBSCRIPTION_ID，一般不需填寫
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名前綴（需與 Spoke 網路組態一致）
############################################
name_prefix    = "demo"
name_separator = "-"

############################################
# 基本設定
############################################
location       = "japaneast"
location_short = "jpe"

############################################
# 資源群組（名稱不套用前綴）
############################################
hub_resource_group_name   = "Hub-Network-RG"
create_hub_resource_group = true

# 既有 Spoke 網路 RG（Spoke VNet / Private DNS Zone 所在，僅供參照）
network_resource_group_name = "Spoke-Network-RG"

############################################
# 標籤
############################################
environment = "prod"
owner       = "network-team"
cost_center = "CC-1001"

# 全域共用自訂標籤（同名時覆寫系統標籤）
tags = {
  Project      = "Hub-Spoke-Network"
  BusinessUnit = "HR"
  DataClass    = "Confidential"
  Criticality  = "High"
  ReviewDate   = "2027-01-01"
}

# 分層專屬標籤
hub_tags = {
  Workload = "Hub-Network"
}

############################################
# 網路位址 - Hub
############################################
hub_vnet_address_space      = ["10.0.0.0/16"]
hub_bastion_subnet_prefixes = ["10.0.0.0/26"]
gateway_subnet_prefixes     = ["10.0.1.0/27"]

############################################
# Bastion
############################################
hub_bastion_sku    = "Basic"
create_hub_bastion = true

############################################
# VPN Gateway / Site-to-Site
############################################
create_vpn_gateway          = true
vpn_gateway_sku             = "VpnGw2AZ"
vpn_gateway_public_ip_zones = ["1", "2", "3"]
enable_bgp                  = false

onprem_vpn_public_ip = "203.0.113.10"
onprem_address_spaces = [
  "192.168.10.0/24",
  "192.168.20.0/24"
]

# create_vpn_connection = true 時，vpn_shared_key 必填
# 建議以環境變數注入：TF_VAR_vpn_shared_key
create_vpn_connection = false
# vpn_shared_key      = "***"

############################################
# Hub 與 Spoke 對等互連
############################################
enable_hub_spoke_peering = true
