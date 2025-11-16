# ===========================================================================
# MAIN.TF - Two VMSS (One per Availability Zone) with Autoscaling
# ===========================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.51.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
  }
  use_oidc        = true
  subscription_id = var.subscription_id
  client_id       = var.client_id
  tenant_id       = var.tenant_id
}

# ===========================================================================
# DATA SOURCES
# ===========================================================================

data "azurerm_client_config" "current" {}

# ============================================================================
# RANDOM PASSWORD GENERATION
# ============================================================================

resource "random_password" "vm_admin_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# ============================================================================
# KEY VAULT
# ============================================================================

resource "azurerm_key_vault" "vm_credentials" {
  name                       = "kv-wss-lab-sec-010"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
    Purpose     = "VM-Credentials"
  }
}

# ============================================================================
# KEY VAULT RBAC
# ============================================================================

resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.vm_credentials.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_certificates_officer" {
  scope                = azurerm_key_vault.vm_credentials.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================================
# KEY VAULT SECRETS
# ============================================================================

resource "azurerm_key_vault_secret" "vm_admin_username" {
  name         = "vm-admin-username"
  value        = var.admin_username
  key_vault_id = azurerm_key_vault.vm_credentials.id

  depends_on = [azurerm_role_assignment.kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  value        = random_password.vm_admin_password.result
  key_vault_id = azurerm_key_vault.vm_credentials.id
  content_type = "password"

  tags = {
    CreatedBy = "Terraform"
    Purpose   = "VM-Admin-Credentials"
  }

  depends_on = [azurerm_role_assignment.kv_secrets_officer]

  lifecycle {
    ignore_changes = [tags]
  }
}

# ============================================================================
# APPLICATION SECURITY GROUPS
# ============================================================================

resource "azurerm_application_security_group" "asg_web_tier" {
  name                = "ASG-WEB-TIER-WSS-LAB-SEC-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    tier = "web"
    role = "application"
  }
}

resource "azurerm_application_security_group" "asg_mgmt_tier" {
  name                = "ASG-MGMT-TIER-WSS-LAB-SEC-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    tier = "management"
    role = "administration"
  }
}

resource "azurerm_application_security_group" "asg_lb_backend" {
  name                = "ASG-LB-BACKEND-WSS-LAB-SEC-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    tier = "web"
    role = "load-balanced"
  }
}

resource "azurerm_application_security_group" "asg_quarantine" {
  name                = "ASG-QUARANTINE-WSS-LAB-SEC-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    tier = "security"
    role = "incident-response"
  }
}

# ===========================================================================
# NETWORK SECURITY GROUPS (NO INLINE RULES)
# ===========================================================================

resource "azurerm_network_security_group" "nsg_sub_apps" {
  name                = "nsg-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    Purpose = "Application-Subnet-Security"
  }
}

resource "azurerm_network_security_group" "nsg_sub_mgmt" {
  name                = "nsg-mgmt-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    Purpose = "Management-Subnet-Security"
  }
}

# ============================================================================
# NSG RULES - APPLICATION SUBNET
# ============================================================================

resource "azurerm_network_security_rule" "apps_allow_rdp_from_mgmt" {
  name                                       = "AllowRDPFromMgmt"
  priority                                   = 300
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "3389"
  source_application_security_group_ids      = [azurerm_application_security_group.asg_mgmt_tier.id]
  destination_application_security_group_ids = [azurerm_application_security_group.asg_web_tier.id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.nsg_sub_apps.name

  depends_on = [
    azurerm_application_security_group.asg_mgmt_tier,
    azurerm_application_security_group.asg_web_tier,
    azurerm_network_security_group.nsg_sub_apps
  ]
}

resource "azurerm_network_security_rule" "apps_allow_https_from_internet" {
  name                                       = "AllowHTTPSFromInternet"
  priority                                   = 250
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "443"
  source_address_prefix                      = "Internet"
  destination_application_security_group_ids = [azurerm_application_security_group.asg_lb_backend.id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.nsg_sub_apps.name

  depends_on = [
    azurerm_application_security_group.asg_lb_backend,
    azurerm_network_security_group.nsg_sub_apps
  ]
}

resource "azurerm_network_security_rule" "apps_deny_all_from_quarantine" {
  name                                  = "DenyAllFromQuarantine"
  priority                              = 100
  direction                             = "Outbound"
  access                                = "Deny"
  protocol                              = "*"
  source_port_range                     = "*"
  destination_port_range                = "*"
  source_application_security_group_ids = [azurerm_application_security_group.asg_quarantine.id]
  destination_address_prefix            = "*"
  resource_group_name                   = var.resource_group_name
  network_security_group_name           = azurerm_network_security_group.nsg_sub_apps.name

  depends_on = [
    azurerm_application_security_group.asg_quarantine,
    azurerm_network_security_group.nsg_sub_apps
  ]
}

resource "azurerm_network_security_rule" "apps_deny_all_to_quarantine" {
  name                                       = "DenyAllToQuarantine"
  priority                                   = 100
  direction                                  = "Inbound"
  access                                     = "Deny"
  protocol                                   = "*"
  source_port_range                          = "*"
  destination_port_range                     = "*"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.asg_quarantine.id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.nsg_sub_apps.name

  depends_on = [
    azurerm_application_security_group.asg_quarantine,
    azurerm_network_security_group.nsg_sub_apps
  ]
}

# ============================================================================
# NSG RULES - MANAGEMENT SUBNET
# ============================================================================

resource "azurerm_network_security_rule" "mgmt_allow_rdp_from_specific_ip" {
  name                                       = "AllowRDPFromSpecificIP"
  priority                                   = 300
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "3389"
  source_address_prefix                      = var.allowed_rdp_ip
  destination_application_security_group_ids = [azurerm_application_security_group.asg_mgmt_tier.id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.nsg_sub_mgmt.name

  depends_on = [
    azurerm_application_security_group.asg_mgmt_tier,
    azurerm_network_security_group.nsg_sub_mgmt
  ]
}

resource "azurerm_network_security_rule" "mgmt_deny_all_from_quarantine" {
  name                                  = "DenyAllFromQuarantine"
  priority                              = 100
  direction                             = "Outbound"
  access                                = "Deny"
  protocol                              = "*"
  source_port_range                     = "*"
  destination_port_range                = "*"
  source_application_security_group_ids = [azurerm_application_security_group.asg_quarantine.id]
  destination_address_prefix            = "*"
  resource_group_name                   = var.resource_group_name
  network_security_group_name           = azurerm_network_security_group.nsg_sub_mgmt.name

  depends_on = [
    azurerm_application_security_group.asg_quarantine,
    azurerm_network_security_group.nsg_sub_mgmt
  ]
}

resource "azurerm_network_security_rule" "mgmt_deny_all_to_quarantine" {
  name                                       = "DenyAllToQuarantine"
  priority                                   = 100
  direction                                  = "Inbound"
  access                                     = "Deny"
  protocol                                   = "*"
  source_port_range                          = "*"
  destination_port_range                     = "*"
  source_address_prefix                      = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.asg_quarantine.id]
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.nsg_sub_mgmt.name

  depends_on = [
    azurerm_application_security_group.asg_quarantine,
    azurerm_network_security_group.nsg_sub_mgmt
  ]
}

# ============================================================================
# VIRTUAL NETWORK AND SUBNETS
# ============================================================================

resource "azurerm_virtual_network" "vnet_shared" {
  name                = "vnet-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.100.0.0/16"]

  tags = {
    owner = "amir"
  }
}

resource "azurerm_subnet" "sub_apps" {
  name                 = "snet-app-wss-lab-sec-001"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes     = ["10.100.1.0/24"]

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true

  depends_on = [azurerm_virtual_network.vnet_shared]
}

resource "azurerm_subnet" "sub_mgmt" {
  name                 = "snet-mngmnt-wss-lab-sec-002"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared.name
  address_prefixes     = ["10.100.0.0/24"]

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true

  depends_on = [azurerm_virtual_network.vnet_shared]
}

# ============================================================================
# SUBNET NSG ASSOCIATIONS
# ============================================================================

resource "azurerm_subnet_network_security_group_association" "sub_apps_nsg" {
  subnet_id                 = azurerm_subnet.sub_apps.id
  network_security_group_id = azurerm_network_security_group.nsg_sub_apps.id

  depends_on = [
    azurerm_subnet.sub_apps,
    azurerm_network_security_group.nsg_sub_apps,
    azurerm_network_security_rule.apps_allow_rdp_from_mgmt,
    azurerm_network_security_rule.apps_allow_https_from_internet,
    azurerm_network_security_rule.apps_deny_all_from_quarantine,
    azurerm_network_security_rule.apps_deny_all_to_quarantine
  ]
}

resource "azurerm_subnet_network_security_group_association" "sub_mgmt_nsg" {
  subnet_id                 = azurerm_subnet.sub_mgmt.id
  network_security_group_id = azurerm_network_security_group.nsg_sub_mgmt.id

  depends_on = [
    azurerm_subnet.sub_mgmt,
    azurerm_network_security_group.nsg_sub_mgmt,
    azurerm_network_security_rule.mgmt_allow_rdp_from_specific_ip,
    azurerm_network_security_rule.mgmt_deny_all_from_quarantine,
    azurerm_network_security_rule.mgmt_deny_all_to_quarantine
  ]
}

# ============================================================================
# PUBLIC IP ADDRESSES
# ============================================================================

resource "azurerm_public_ip" "pip_lb" {
  name                    = "pip-lb-wss-lab-sec-001"
  location                = var.location
  resource_group_name     = var.resource_group_name
  allocation_method       = "Static"
  sku                     = "Standard"
  zones                   = ["1", "2", "3"]
  ip_version              = "IPv4"
  idle_timeout_in_minutes = 4
}

# ============================================================================
# LOAD BALANCER
# ============================================================================
resource "azurerm_lb" "lb" {
  name                = "lbi-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PIP-LB"
    public_ip_address_id = azurerm_public_ip.pip_lb.id
  }

  depends_on = [azurerm_public_ip.pip_lb]
}

resource "azurerm_lb_backend_address_pool" "pool_webs" {
  name            = "Pool-webs"
  loadbalancer_id = azurerm_lb.lb.id

  depends_on = [azurerm_lb.lb]
}

resource "azurerm_lb_probe" "hp_lb" {
  name                = "HP-LB"
  loadbalancer_id     = azurerm_lb.lb.id
  protocol            = "Tcp"
  port                = 443
  interval_in_seconds = 5
  number_of_probes    = 1

  depends_on = [azurerm_lb.lb]
}

resource "azurerm_lb_rule" "lb_rule" {
  name                           = "LB-rule"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PIP-LB"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pool_webs.id]
  probe_id                       = azurerm_lb_probe.hp_lb.id
  floating_ip_enabled            = false
  disable_outbound_snat          = true

  depends_on = [
    azurerm_lb_backend_address_pool.pool_webs,
    azurerm_lb_probe.hp_lb
  ]
}

resource "azurerm_lb_outbound_rule" "out_lb" {
  name                     = "out-LB"
  loadbalancer_id          = azurerm_lb.lb.id
  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.pool_webs.id
  allocated_outbound_ports = 15992
  idle_timeout_in_minutes  = 4

  frontend_ip_configuration {
    name = "PIP-LB"
  }

  depends_on = [
    azurerm_lb_backend_address_pool.pool_webs,
    azurerm_lb_rule.lb_rule
  ]
}


# ============================================================================
# MANAGEMENT VM (Single VM)
# ============================================================================

resource "azurerm_network_interface" "nic_mgmt" {
  name                = "nic-vm-mgmt-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.sub_mgmt.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv4"
    primary                       = true
  }

  depends_on = [azurerm_subnet.sub_mgmt]
}

resource "azurerm_network_interface_application_security_group_association" "nic_mgmt_asg" {
  network_interface_id          = azurerm_network_interface.nic_mgmt.id
  application_security_group_id = azurerm_application_security_group.asg_mgmt_tier.id

  depends_on = [
    azurerm_network_interface.nic_mgmt,
    azurerm_application_security_group.asg_mgmt_tier
  ]
}

resource "azurerm_windows_virtual_machine" "vm_mgmt" {
  name                  = "vm-mgmt-wss-sec"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = "Standard_D2as_v5"
  admin_username        = azurerm_key_vault_secret.vm_admin_username.value
  admin_password        = azurerm_key_vault_secret.vm_admin_password.value
  network_interface_ids = [azurerm_network_interface.nic_mgmt.id]

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-vm-mgmt-wss-lab-sec-001"
  }

  secure_boot_enabled = true
  vtpm_enabled        = true

  depends_on = [
    azurerm_network_interface.nic_mgmt,
    azurerm_key_vault_secret.vm_admin_password
  ]
}

# ============================================================================
# VMSS - ZONE 1
# ============================================================================

resource "azurerm_windows_virtual_machine_scale_set" "vmss_web_zone1" {
  name                = "vmss-app1"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard_D2as_v5"
  instances           = 1
  admin_username      = azurerm_key_vault_secret.vm_admin_username.value
  admin_password      = azurerm_key_vault_secret.vm_admin_password.value

  zones        = ["1"]
  zone_balance = false

  upgrade_mode    = "Automatic"
  health_probe_id = azurerm_lb_probe.hp_lb.id

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-vmss-zone1"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.sub_apps.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.pool_webs.id]

      application_security_group_ids = [
        azurerm_application_security_group.asg_web_tier.id,
        azurerm_application_security_group.asg_lb_backend.id
      ]
    }
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  tags = {
    Environment = "Lab"
    Zone        = "1"
    Tier        = "Web"
  }

  depends_on = [
    azurerm_subnet.sub_apps,
    azurerm_lb_backend_address_pool.pool_webs,
    azurerm_lb_probe.hp_lb,
    azurerm_application_security_group.asg_web_tier,
    azurerm_application_security_group.asg_lb_backend,
    azurerm_key_vault_secret.vm_admin_password
  ]
}

# ============================================================================
# VMSS - ZONE 2
# ============================================================================

resource "azurerm_windows_virtual_machine_scale_set" "vmss_web_zone2" {
  name                = "vmss-app2"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard_D2as_v5"
  instances           = 1
  admin_username      = azurerm_key_vault_secret.vm_admin_username.value
  admin_password      = azurerm_key_vault_secret.vm_admin_password.value

  zones        = ["2"]
  zone_balance = false

  upgrade_mode    = "Automatic"
  health_probe_id = azurerm_lb_probe.hp_lb.id

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-vmss-zone2"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.sub_apps.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.pool_webs.id]

      application_security_group_ids = [
        azurerm_application_security_group.asg_web_tier.id,
        azurerm_application_security_group.asg_lb_backend.id
      ]
    }
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  tags = {
    Environment = "Lab"
    Zone        = "2"
    Tier        = "Web"
  }

  depends_on = [
    azurerm_subnet.sub_apps,
    azurerm_lb_backend_address_pool.pool_webs,
    azurerm_lb_probe.hp_lb,
    azurerm_application_security_group.asg_web_tier,
    azurerm_application_security_group.asg_lb_backend,
    azurerm_key_vault_secret.vm_admin_password
  ]
}

# ============================================================================
# AUTOSCALE SETTINGS - ZONE 1
# ============================================================================

resource "azurerm_monitor_autoscale_setting" "vmss_zone1_autoscale" {
  name                = "autoscale-vmss-zone1"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.vmss_web_zone1.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    # Scale OUT when CPU > 75%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone1.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale IN when CPU < 25%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone1.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    # Scale OUT when Memory > 80%
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone1.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 1073741824 # 1GB in bytes
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  # Schedule-based scaling for business hours
  profile {
    name = "businessHoursProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    recurrence {
      timezone = "Central European Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [8]
      minutes  = [0]
    }
  }

  # Scale back after business hours
  profile {
    name = "afterHoursProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 3
    }

    recurrence {
      timezone = "Central European Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [18]
      minutes  = [0]
    }
  }


  depends_on = [azurerm_windows_virtual_machine_scale_set.vmss_web_zone1]
}

# ===========================================================================
# AUTOSCALE SETTINGS - ZONE 2v
# ===========================================================================

resource "azurerm_monitor_autoscale_setting" "vmss_zone2_autoscale" {
  name                = "autoscale-vmss-zone2"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.vmss_web_zone2.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    # Scale OUT when CPU > 75%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone2.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale IN when CPU < 25%
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone2.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    # Scale OUT when Memory > 80%
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss_web_zone2.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 1073741824 # 1GB in bytes
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  # Schedule-based scaling for business hours
  profile {
    name = "businessHoursProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    recurrence {
      timezone = "Central European Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [8]
      minutes  = [0]
    }
  }

  # Scale back after business hours
  profile {
    name = "afterHoursProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 3
    }

    recurrence {
      timezone = "Central European Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [18]
      minutes  = [0]
    }
  }


  depends_on = [azurerm_windows_virtual_machine_scale_set.vmss_web_zone2]
}

# ============================================================================
# RECOVERY SERVICES VAULT
# ============================================================================

resource "azurerm_recovery_services_vault" "rsv" {
  name                = "rsv-wss-lab-sec-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  soft_delete_enabled = true
}

# ============================================================================
# LOG ANALYTICS WORKSPACE
# ============================================================================

resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-wss-lab-sec-010"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ============================================================================
# STORAGE ACCOUNT FOR LOG EXPORT
# ============================================================================

resource "azurerm_storage_account" "stblc" {
  name                     = "stblcwsslabsec001"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

# ============================================================================
# STORAGE CONTAINERS
# ============================================================================

resource "azurerm_storage_container" "insights_logs_activity" {
  name                  = "insights-logs-activity"
  storage_account_id    = azurerm_storage_account.stblc.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "insights_logs_security" {
  name                  = "insights-logs-security"
  storage_account_id    = azurerm_storage_account.stblc.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "insights_logs_resource" {
  name                  = "insights-logs-resource"
  storage_account_id    = azurerm_storage_account.stblc.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "insights_logs_networking" {
  name                  = "insights-logs-networking"
  storage_account_id    = azurerm_storage_account.stblc.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "insights_logs_app" {
  name                  = "insights-logs-app"
  storage_account_id    = azurerm_storage_account.stblc.id
  container_access_type = "private"
}

# ============================================================================
# LIFECYCLE MANAGEMENT POLICY
# ============================================================================

resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.stblc.id

  rule {
    name    = "log-lifecycle"
    enabled = true

    filters {
      prefix_match = ["insights-logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
      }
    }
  }
}

# ============================================================================
# LINKED STORAGE ACCOUNT
# ============================================================================

resource "azurerm_log_analytics_linked_storage_account" "law_storage" {
  data_source_type      = "CustomLogs"
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  storage_account_ids   = [azurerm_storage_account.stblc.id]
}

# ============================================================================
# DATA EXPORT RULES
# ============================================================================

resource "azurerm_log_analytics_data_export_rule" "export_all" {
  name                    = "export-all-tables"
  resource_group_name     = var.resource_group_name
  workspace_resource_id   = azurerm_log_analytics_workspace.law.id
  destination_resource_id = azurerm_storage_account.stblc.id
  table_names             = ["*"]
  enabled                 = true
}

# ============================================================================
# PRIVATE DNS ZONE
# ============================================================================

resource "azurerm_private_dns_zone" "dns_zone" {
  name                = "test.local"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_link" {
  name                  = "localdns"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet_shared.id
  registration_enabled  = true

  depends_on = [
    azurerm_private_dns_zone.dns_zone,
    azurerm_virtual_network.vnet_shared
  ]
}

# ============================================================================
# PRIVATE DNS A RECORDS
# ============================================================================

resource "azurerm_private_dns_a_record" "dns_vm_mgmt" {
  name                = "vm-mgmt-demo-sw"
  zone_name           = azurerm_private_dns_zone.dns_zone.name
  resource_group_name = var.resource_group_name
  ttl                 = 10
  records             = ["10.100.0.4"]

  depends_on = [azurerm_private_dns_zone.dns_zone]
}