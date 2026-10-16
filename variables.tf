############################################
# variables.tf
#   Hub 網路資源群組沿用同一套變數命名規則：
#     <層>_resource_group_name / create_<層>_resource_group / <層>_tags
#       hub     ：Hub 網路（VPN Gateway / Bastion）
#       network ：既有 Spoke 網路 RG（僅供 Peering / DNS 連結參照）
############################################

############################################
# 訂閱
#   由 Azure DevOps Service Connection 自動注入
#   ARM_SUBSCRIPTION_ID，一般無需輸入。
############################################
variable "subscription_id" {
  description = "Azure 訂閱 ID。留 null 由 ARM_SUBSCRIPTION_ID 環境變數提供。"
  type        = string
  default     = null
  nullable    = true
}

############################################
# 命名前綴
############################################
variable "name_prefix" {
  description = "所有資源名稱的前綴詞，例如 demo、hr、corp。留空則不加前綴。資源群組名稱不套用前綴。"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.name_prefix))
    error_message = "name_prefix 僅能包含英數字與連字號。"
  }
  validation {
    condition     = length(var.name_prefix) <= 10
    error_message = "name_prefix 建議不超過 10 字元，避免資源名稱超出 Azure 長度限制。"
  }
}

variable "name_separator" {
  description = "前綴與資源名稱之間的分隔符號"
  type        = string
  default     = "-"
}

############################################
# 基本設定
############################################
variable "location" {
  description = "資源部署區域"
  type        = string
  default     = "japaneast"
}

variable "location_short" {
  description = "區域縮寫，用於資源命名（japaneast = jpe）"
  type        = string
  default     = "jpe"
}

############################################
# 資源群組（名稱不套用前綴）
############################################
variable "hub_resource_group_name" {
  description = "Hub 網路資源群組名稱（VPN Gateway / Hub Bastion 置於此）"
  type        = string
  default     = "Hub-Network-RG"
}

variable "create_hub_resource_group" {
  description = "true = 由本組態建立 Hub RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "network_resource_group_name" {
  description = "既有 Spoke 網路資源群組名稱（Spoke VNet 與 Private DNS Zone 所在，僅供參照）"
  type        = string
  default     = "Spoke-Network-RG"
}

############################################
# 標籤（統一由 locals 合併；資源群組名稱不加前綴，但標籤一律套用）
############################################
variable "environment" {
  description = "環境代號，會自動寫入 Environment 標籤（UAT 層會自動改寫為 uat）"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "uat", "dev", "test"], var.environment)
    error_message = "environment 必須為 prod、uat、dev 或 test。"
  }
}

variable "owner" {
  description = "資源擁有者，會自動寫入 Owner 標籤"
  type        = string
  default     = "network-team"
}

variable "cost_center" {
  description = "成本中心代碼，會自動寫入 CostCenter 標籤；留空則不輸出該標籤"
  type        = string
  default     = ""
}

variable "tags" {
  description = "額外的全域自訂標籤，會與系統自動產生的共用標籤合併（同名時以此處為準）"
  type        = map(string)
  default     = {}
}

variable "hub_tags" {
  description = "僅套用於 Hub 網路資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

############################################
# 網路位址 - Hub
############################################
variable "hub_vnet_address_space" {
  description = "Hub VNet 位址空間"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "hub_bastion_subnet_prefixes" {
  description = "Hub AzureBastionSubnet CIDR，至少需 /26"
  type        = list(string)
  default     = ["10.0.0.0/26"]
}

variable "gateway_subnet_prefixes" {
  description = "Hub GatewaySubnet CIDR，建議 /27 以上"
  type        = list(string)
  default     = ["10.0.1.0/27"]
}

############################################
# Bastion
############################################
variable "hub_bastion_sku" {
  description = "Hub Bastion SKU（Hub 為傳統模式，需公用 IP 與 AzureBastionSubnet）"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.hub_bastion_sku)
    error_message = "hub_bastion_sku 必須為 Basic、Standard 或 Premium。"
  }
}

variable "create_hub_bastion" {
  description = "是否建立 Hub Bastion（含其 AzureBastionSubnet 與公用 IP）"
  type        = bool
  default     = true
}

############################################
# VPN Gateway / Site-to-Site（Hub）
############################################
variable "create_vpn_gateway" {
  description = "是否建立 VPN Gateway（含 GatewaySubnet 與公用 IP）。建立時間約 30-45 分鐘。"
  type        = bool
  default     = true
}

variable "vpn_gateway_sku" {
  description = "Azure VPN Gateway SKU"
  type        = string
  default     = "VpnGw2AZ"

  validation {
    condition = contains([
      "Basic",
      "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5",
      "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"
    ], var.vpn_gateway_sku)
    error_message = "請指定有效的 VPN Gateway SKU。"
  }
}

variable "vpn_gateway_public_ip_zones" {
  description = "VPN Gateway Standard Public IP 的 Availability Zones"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "enable_bgp" {
  description = "是否於 Azure VPN Gateway 啟用 BGP（對應資源參數已改用 bgp_enabled）"
  type        = bool
  default     = false
}

variable "onprem_vpn_public_ip" {
  description = "地端 FortiGate 的公用 IP 位址"
  type        = string
  default     = "203.0.113.10"

  validation {
    condition     = can(cidrhost("${var.onprem_vpn_public_ip}/32", 0))
    error_message = "onprem_vpn_public_ip 必須是有效的 IPv4 位址。"
  }
}

variable "onprem_address_spaces" {
  description = "FortiGate 後方的地端網段"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "create_vpn_connection" {
  description = "是否建立 Site-to-Site VPN Connection"
  type        = bool
  default     = false
}

variable "vpn_shared_key" {
  description = "IPsec Pre-Shared Key。只有建立 VPN Connection 時才需要。"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition = (
      var.create_vpn_connection == false ||
      (var.vpn_shared_key != null && length(trimspace(var.vpn_shared_key)) > 0)
    )
    error_message = "create_vpn_connection 為 true 時，必須提供非空白的 vpn_shared_key。"
  }
}

############################################
# Hub 與 Spoke 對等互連
############################################
variable "enable_hub_spoke_peering" {
  description = "是否建立 Hub 與 PROD/UAT Spoke 之間的雙向 VNet Peering 及 Hub VNet 的 Private DNS 連結（需先部署 Spoke 網路組態）"
  type        = bool
  default     = true
}
