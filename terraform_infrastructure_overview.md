# Terraform Code Overview

This document provides a comprehensive overview of the Terraform code used to provision the Azure infrastructure. It details the variables, resources, dependencies, and outputs used in this project.

## Table of Contents

- [Terraform Code Overview](#terraform-code-overview)
  - [Table of Contents](#table-of-contents)
  - [1. Provider Configuration](#1-provider-configuration)
  - [2. Input Variables](#2-input-variables)
  - [3. Core Resources](#3-core-resources)
    - [3.1. Networking](#31-networking)
    - [3.2. Security](#32-security)
    - [3.3. Compute](#33-compute)
    - [3.4. Monitoring and Logging](#34-monitoring-and-logging)
    - [3.5. Backup and Recovery](#35-backup-and-recovery)
    - [3.6. DNS](#36-dns)
  - [4. Resource Dependencies](#4-resource-dependencies)
  - [5. Outputs](#5-outputs)

---

## 1. Provider Configuration

The configuration relies on the `azurerm` provider to interact with Microsoft Azure. It is configured to use OpenID Connect (OIDC) for authentication, which is a security best practice that avoids storing secrets.

-   **Provider:** `hashicorp/azurerm`
-   **Version:** `~> 4.51.0`
-   **Authentication:** OIDC (`use_oidc = true`)

## 2. Input Variables

The following table outlines the input variables used to customize the deployment.

| Variable Name                     | Description                                                              | Type           | Default Value          | Sensitive |
| --------------------------------- | ------------------------------------------------------------------------ | -------------- | ---------------------- | --------- |
| `location`                        | The Azure region where resources will be deployed.                       | `string`       | `swedencentral`        | No        |
| `resource_group_name`             | The name of the resource group to contain the resources.                 | `string`       | `rg-kolad-sch`         | No        |
| `subscription_id`                 | The Azure subscription ID.                                               | `string`       | (Required)             | No        |
| `client_id`                       | The Client ID of the Managed Identity for OIDC authentication.           | `string`       | (Required)             | Yes       |
| `tenant_id`                       | The Azure Tenant ID.                                                     | `string`       | (Required)             | Yes       |
| `admin_username`                  | The admin username for the Windows virtual machines.                     | `string`       | `AzureMinions`         | Yes       |
| `allowed_rdp_ip`                  | The source IP address (CIDR) allowed for RDP access to the management VM. | `string`       | `109.41.113.107/32`    | No        |
| `autoscale_notification_emails`   | A list of email addresses to receive autoscale event notifications.      | `list(string)` | `["koosha.olad@g,aol.com"]` | No        |
| `vmss_sku`                        | The virtual machine SKU for the scale sets.                              | `string`       | `Standard_D2as_v5`     | No        |
| `vmss_zone1_min_instances`        | Minimum number of instances for the Zone 1 VMSS.                         | `number`       | `1`                    | No        |
| `vmss_zone1_max_instances`        | Maximum number of instances for the Zone 1 VMSS.                         | `number`       | `5`                    | No        |
| `vmss_zone2_min_instances`        | Minimum number of instances for the Zone 2 VMSS.                         | `number`       | `1`                    | No        |
| `vmss_zone2_max_instances`        | Maximum number of instances for the Zone 2 VMSS.                         | `number`       | `5`                    | No        |
| `autoscale_cpu_threshold_out`     | The CPU percentage threshold to trigger a scale-out action.              | `number`       | `75`                   | No        |
| `autoscale_cpu_threshold_in`      | The CPU percentage threshold to trigger a scale-in action.               | `number`       | `25`                   | No        |
| `business_hours_min_instances`    | The minimum number of instances during business hours.                   | `number`       | `2`                    | No        |
| `business_hours_start`            | The start hour for business hours scaling (24-hour format).              | `number`       | `8`                    | No        |
| `business_hours_end`              | The end hour for business hours scaling (24-hour format).                | `number`       | `18`                   | No        |

## 3. Core Resources

This section describes the purpose of each major resource created by the Terraform code.

### 3.1. Networking

| Resource Type                       | Name                      | Purpose                                                                                             |
| ----------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------- |
| `azurerm_virtual_network`           | `vnet_shared`             | Provides the primary isolated network for all resources, with address space `10.100.0.0/16`.        |
| `azurerm_subnet`                    | `sub_apps`, `sub_mgmt`    | Creates two subnets: one for the application workloads and one for the management virtual machine.    |
| `azurerm_public_ip`                 | `pip_lb`                  | A static, standard SKU public IP address for the load balancer to receive internet traffic.         |
| `azurerm_lb`                        | `lb`                      | A standard load balancer to distribute incoming traffic across the web server VMSS instances.       |
| `azurerm_lb_backend_address_pool`   | `pool_webs`               | The backend pool containing the application VMSS instances.                                         |
| `azurerm_lb_probe`                  | `hp_lb`                   | A health probe to monitor the health of backend instances on TCP port 443.                          |
| `azurerm_lb_rule`                   | `lb_rule`                 | Forwards incoming traffic on port 443 to the backend pool.                                          |
| `azurerm_lb_outbound_rule`          | `out_lb`                  | Manages outbound connectivity for the VMSS instances.                                               |

### 3.2. Security

| Resource Type                                | Name                                | Purpose                                                                                                                            |
| -------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `azurerm_key_vault`                          | `vm_credentials`                    | Securely stores and manages secrets, such as the VM admin username and password. RBAC is enabled for granular access control.      |
| `azurerm_key_vault_secret`                   | `vm_admin_username`, `vm_admin_password` | Stores the administrator credentials for the virtual machines. The password is randomly generated.                                 |
| `azurerm_network_security_group`             | `nsg_sub_apps`, `nsg_sub_mgmt`      | Network Security Groups to enforce firewall rules for the application and management subnets.                                      |
| `azurerm_network_security_rule`              | Various                             | Defines specific ingress and egress rules, such as allowing HTTPS, RDP from trusted sources, and denying traffic from quarantine. |
| `azurerm_application_security_group`         | `asg_web_tier`, `asg_mgmt_tier`, etc. | Application Security Groups to logically group VMs and apply network security rules based on application roles.                  |

### 3.3. Compute

| Resource Type                               | Name                                | Purpose                                                                                                                            |
| ------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `azurerm_windows_virtual_machine`           | `vm_mgmt`                           | A standalone virtual machine for management and administrative tasks, placed in the management subnet.                             |
| `azurerm_windows_virtual_machine_scale_set` | `vmss_web_zone1`, `vmss_web_zone2`  | Two separate Virtual Machine Scale Sets for the web application, deployed across two availability zones for high availability.     |
| `azurerm_monitor_autoscale_setting`         | `vmss_zone1_autoscale`, `vmss_zone2_autoscale` | Configures autoscaling for the VMSS based on CPU and memory metrics, as well as a schedule for business hours.                 |

### 3.4. Monitoring and Logging

| Resource Type                                  | Name                         | Purpose                                                                                                                            |
| ---------------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `azurerm_log_analytics_workspace`              | `law`                        | A central workspace for collecting, analyzing, and storing logs and metrics from all resources.                                    |
| `azurerm_storage_account`                      | `stblc`                      | A storage account used for long-term archival of logs exported from the Log Analytics Workspace.                                   |
| `azurerm_storage_container`                    | `insights-logs-*`            | Multiple containers within the storage account to organize different types of logs (activity, security, etc.).                     |
| `azurerm_storage_management_policy`            | `lifecycle`                  | An automated policy to transition log data to cooler storage tiers and eventually archive it to reduce costs.                      |
| `azurerm_log_analytics_data_export_rule`       | `export_all`                 | A rule to continuously export all tables from the Log Analytics Workspace to the designated storage account.                     |

### 3.5. Backup and Recovery

| Resource Type                     | Name | Purpose                                                                                             |
| --------------------------------- | ---- | --------------------------------------------------------------------------------------------------- |
| `azurerm_recovery_services_vault` | `rsv`| Provides backup and disaster recovery capabilities for the environment. Soft delete is enabled.         |

### 3.6. DNS

| Resource Type                                   | Name              | Purpose                                                                                             |
| ----------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------------------- |
| `azurerm_private_dns_zone`                      | `dns_zone`        | A private DNS zone (`test.local`) for name resolution within the virtual network.                   |
| `azurerm_private_dns_zone_virtual_network_link` | `dns_vnet_link`   | Links the private DNS zone to the virtual network, enabling automatic registration of VM hostnames. |
| `azurerm_private_dns_a_record`                  | `dns_vm_mgmt`     | Creates a static 'A' record for the management VM.                                                  |

## 4. Resource Dependencies

The infrastructure is designed with explicit dependencies to ensure resources are created and configured in the correct order.

-   **Virtual Network and Subnets:** The `azurerm_virtual_network` is created first, followed by the `azurerm_subnet` resources within it.
-   **Key Vault and Secrets:** The `azurerm_key_vault` is created, and then RBAC roles are assigned (`azurerm_role_assignment`) before secrets (`azurerm_key_vault_secret`) are written.
-   **Network Security:** `azurerm_application_security_group` and `azurerm_network_security_group` resources are created before the `azurerm_network_security_rule` resources that reference them. NSG rules are then associated with subnets.
-   **Compute and Networking:** Network interfaces (`azurerm_network_interface`) and the load balancer (`azurerm_lb`) are created before the virtual machines and scale sets that depend on them.
-   **VM Credentials:** Virtual machines and scale sets depend on the `azurerm_key_vault_secret` for their admin credentials, ensuring the secret is available before the VM is provisioned.

## 5. Outputs

There are no explicit outputs defined in the `main.tf` file. All important resource identifiers (like the Key Vault URI or Load Balancer IP address) can be queried from the Azure portal or via the Azure CLI once the deployment is complete.
