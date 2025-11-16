# ============================================================================
# VARIABLES.TF - Updated for Key Vault Integration
# ============================================================================

variable "location" {
  description = "The Azure region to deploy resources into."
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  default     = "rg-kolad-sch"
}

variable "subscription_id" {
  description = "The Azure subscription ID."
  type        = string
}

variable "client_id" {
  description = "The Client ID of the Managed Identity (for OIDC authentication)."
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "The Azure Tenant ID."
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Admin username for Windows VMs (stored in Key Vault)"
  type        = string
  default     = "AzureMinions"
  sensitive   = true
}

variable "allowed_rdp_ip" {
  description = "IP address allowed to RDP into management VM"
  type        = string
  default     = "109.41.113.107/32"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.allowed_rdp_ip))
    error_message = "The allowed_rdp_ip must be a valid CIDR notation (e.g., 109.41.113.107/32)."
  }
}


variable "autoscale_notification_emails" {
  description = "List of email addresses to notify on autoscale events"
  type        = list(string)
  default     = ["koosha.olad@gmail.com"]
}

# ===========================================================================
# VMSS CONFIGURATION VARIABLES (Optional - for easier tuning)
# ===========================================================================

variable "vmss_sku" {
  description = "VM SKU for scale sets"
  type        = string
  default     = "Standard_D2as_v5"
}

variable "vmss_zone1_min_instances" {
  description = "Minimum instances for Zone 1 VMSS"
  type        = number
  default     = 1
}

variable "vmss_zone1_max_instances" {
  description = "Maximum instances for Zone 1 VMSS"
  type        = number
  default     = 5
}

variable "vmss_zone2_min_instances" {
  description = "Minimum instances for Zone 2 VMSS"
  type        = number
  default     = 1
}

variable "vmss_zone2_max_instances" {
  description = "Maximum instances for Zone 2 VMSS"
  type        = number
  default     = 5
}

variable "autoscale_cpu_threshold_out" {
  description = "CPU percentage threshold to trigger scale out"
  type        = number
  default     = 75
}

variable "autoscale_cpu_threshold_in" {
  description = "CPU percentage threshold to trigger scale in"
  type        = number
  default     = 25
}

variable "business_hours_min_instances" {
  description = "Minimum instances during business hours"
  type        = number
  default     = 2
}

variable "business_hours_start" {
  description = "Business hours start time (24-hour format)"
  type        = number
  default     = 8
}

variable "business_hours_end" {
  description = "Business hours end time (24-hour format)"
  type        = number
  default     = 18
}