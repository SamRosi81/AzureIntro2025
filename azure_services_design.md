# Azure Services Design

This document outlines the design and implementation of the Azure services used in this project, aligning with the customer requirements specified in `requirements.md`.

## Table of Contents

- [Azure Services Design](#azure-services-design)
  - [Table of Contents](#table-of-contents)
  - [1. Naming Convention](#1-naming-convention)
  - [2. Core Requirements and Implementation](#2-core-requirements-and-implementation)
    - [2.1. High Availability and Load Balancing](#21-high-availability-and-load-balancing)
    - [2.2. Backup and Data Protection](#22-backup-and-data-protection)
    - [2.3. Centralized Logging and Monitoring](#23-centralized-logging-and-monitoring)
  - [3. Key Service Deep-Dive](#3-key-service-deep-dive)
    - [3.1. Azure Load Balancer](#31-azure-load-balancer)
    - [3.2. Azure Virtual Machine Scale Sets (VMSS)](#32-azure-virtual-machine-scale-sets-vmss)
    - [3.3. Azure Key Vault](#33-azure-key-vault)
    - [3.4. Azure Recovery Services Vault](#34-azure-recovery-services-vault)
    - [3.5. Azure Log Analytics Workspace](#35-azure-log-analytics-workspace)

---

## 1. Naming Convention

We have adopted the Microsoft Cloud Adoption Framework (CAF) naming convention to ensure consistency and clarity across all resources. The Azure Naming Tool was used to generate standardized names.

The convention follows this pattern:
`{resource-type}-{workload}-{environment}-{instance}`

-   **Example (Virtual Network):** `vnet-wss-lab-sec-001`
-   **Example (Key Vault):** `kv-wss-lab-sec-001`

This approach makes resources easily identifiable and manageable.

## 2. Core Requirements and Implementation

### 2.1. High Availability and Load Balancing

> **Requirement:** "Implement Azure Load Balancer: Demonstrate the configuration and usage of Azure Load Balancer to evenly distribute traƯic between the two applications hosted on separate virtual machines."

#### Implementation

To meet this requirement, we implemented a highly available architecture using the following services:

-   **Azure Load Balancer (Standard SKU):** A public-facing load balancer (`lbi-wss-lab-sec-001`) was chosen to distribute incoming HTTPS traffic from the internet to our web servers. The Standard SKU was selected for its zone-redundant capabilities and advanced features.
-   **Virtual Machine Scale Sets (VMSS):** Instead of individual VMs, we deployed two separate `azurerm_windows_virtual_machine_scale_set` resources (`vmss-app1-sec` and `vmss-app2-sec`). Each VMSS is pinned to a different Availability Zone ("1" and "2") to protect against datacenter-level failures. This provides higher availability than using two standalone VMs.
-   **Health Probes:** A TCP health probe (`hp_lb`) is configured on port 443. The load balancer uses this probe to monitor the health of each VM instance and will only send traffic to healthy, responsive instances.

This design ensures that traffic is automatically distributed across healthy instances in different physical locations, providing a robust and resilient solution.

### 2.2. Backup and Data Protection

> **Requirement:** "Backup Solution for Applications: Design and implement a backup strategy for both applications to ensure data protection and easy recovery in case of failure."

#### Implementation

We addressed this requirement by provisioning an **Azure Recovery Services Vault**.

-   **Service:** `azurerm_recovery_services_vault` (`rsv-wss-lab-sec-001`)
-   **Use Case:** This vault serves as the central management point for all backup and disaster recovery operations. While the Terraform code provisions the vault itself, the next step is to configure backup policies within Azure to target the VMSS instances.
-   **Setup:** The vault was created with the `Standard` SKU and `soft_delete_enabled = true`. Soft delete is a critical security feature that protects backups from accidental or malicious deletion for a configurable retention period.
-   **Next Steps:** A backup policy must be configured in the Azure portal or via Azure CLI to define the backup frequency (e.g., daily) and retention period for the VMSS instances. This policy will then be associated with the web server scale sets.

### 2.3. Centralized Logging and Monitoring

> **Requirement:** "Store Application Logs: Set up a logging solution to capture and store application logs, ensuring that logs are accessible for monitoring, troubleshooting, and auditing purposes."

#### Implementation

A comprehensive logging and monitoring solution was implemented using the following services:

-   **Azure Log Analytics Workspace:** An `azurerm_log_analytics_workspace` (`log-wss-lab-sec-001`) was created to serve as the primary sink for all logs and performance metrics from the environment. It is configured with a 30-day retention period.
-   **Azure Storage Account for Archival:** An `azurerm_storage_account` (`stblcwsslabsec001`) is used for long-term, cost-effective log archival.
-   **Data Export and Lifecycle Management:**
    -   An `azurerm_log_analytics_data_export_rule` automatically exports all tables from the Log Analytics Workspace to the storage account.
    -   An `azurerm_storage_management_policy` is in place to manage the lifecycle of these exported logs. It automatically moves data to the "Cool" tier after 30 days and to the "Archive" tier after 180 days, significantly optimizing storage costs.

This setup ensures that logs are available for immediate analysis in Log Analytics while also being securely and cheaply stored for long-term compliance and auditing.

## 3. Key Service Deep-Dive

### 3.1. Azure Load Balancer

-   **Use Case:** To provide a single, public-facing endpoint for the web application and distribute traffic across the zone-redundant VMSS instances.
-   **Setup:**
    -   A `Standard` SKU public IP address (`pip-lb`) was created.
    -   The load balancer (`lbi-wss-lab-sec-001`) is configured with a frontend IP configuration pointing to this public IP.
    -   A backend pool (`pool_webs`) is defined to contain the network interfaces of the VMSS instances.
    -   A load balancing rule (`lb_rule`) maps incoming TCP traffic on port 443 to the backend pool on the same port.
-   **Security:** The load balancer works in conjunction with the `nsg_sub_apps` Network Security Group, which only permits inbound traffic on port 443 from the "Internet" source tag to the load balancer's backend.

### 3.2. Azure Virtual Machine Scale Sets (VMSS)

-   **Use Case:** To provide a scalable and highly available pool of web servers. Using VMSS simplifies management and enables automatic scaling.
-   **Setup:**
    -   Two separate `azurerm_windows_virtual_machine_scale_set` resources are deployed, one in Zone 1 and one in Zone 2.
    -   Each VMSS is attached to the load balancer's backend pool and health probe.
    -   `Automatic Instance Repair` is enabled, allowing the service to automatically replace unhealthy instances.
-   **Autoscaling:**
    -   Metric-based rules are configured to scale out (add instances) when CPU usage exceeds 75% and scale in (remove instances) when it drops below 25%.
    -   Schedule-based rules are also in place to proactively increase the minimum instance count during predefined business hours.

### 3.3. Azure Key Vault

-   **Use Case:** To securely store and manage sensitive information, primarily the administrator credentials for the virtual machines.
-   **Setup:**
    -   An `azurerm_key_vault` (`kv-wss-lab-sec-001`) is provisioned with RBAC enabled for access control, which is more secure and manageable than access policies.
    -   A random password is generated by Terraform using the `random_password` resource and stored directly in the Key Vault as a secret (`vm-admin-password`).
    -   The VMSS resources are configured to fetch the admin username and password directly from Key Vault during provisioning.
-   **Security:** This approach completely removes hardcoded credentials from the Terraform code and state file, significantly improving the security posture of the deployment.

### 3.4. Azure Recovery Services Vault

-   **Use Case:** Centralized management of backups for the VMSS instances.
-   **Setup:** A standard vault (`rsv-wss-lab-sec-001`) is created with soft delete enabled.
-   **Security:** Soft delete protects against accidental or malicious deletion of backups, providing a crucial layer of data protection.

### 3.5. Azure Log Analytics Workspace

-   **Use Case:** A unified sink for all operational data, including VM performance metrics, event logs, and activity logs.
-   **Setup:** A `PerGB2018` SKU workspace (`log-wss-lab-sec-001`) is created. Diagnostic settings (not shown in Terraform, but a necessary next step) must be configured on the Azure resources to send their logs to this workspace.
-   **Cost Optimization:** The data export and storage lifecycle policies ensure that hot data is kept in the workspace for immediate querying, while cold data is moved to cheaper storage tiers automatically.
