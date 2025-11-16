# Environment Setup Guide

This guide provides step-by-step instructions for setting up and running the Azure environment using Bicep for bootstrapping and Terraform for the main infrastructure deployment.

## Table of Contents

- [Environment Setup Guide](#environment-setup-guide)
  - [Table of Contents](#table-of-contents)
  - [1. Prerequisites](#1-prerequisites)
  - [2. Phase 1: Bicep Bootstrap](#2-phase-1-bicep-bootstrap)
    - [2.1. What it Creates](#21-what-it-creates)
    - [2.2. How to Run It](#22-how-to-run-it)
  - [3. Phase 2: Terraform Deployment](#3-phase-2-terraform-deployment)
    - [3.1. How it Works](#31-how-it-works)
    - [3.2. Local Setup and Execution](#32-local-setup-and-execution)
  - [4. GitHub Actions CI/CD](#4-github-actions-cicd)
    - [4.1. Required Secrets and Variables](#41-required-secrets-and-variables)
    - [4.2. Workflow Explanation](#42-workflow-explanation)

---

## 1. Prerequisites

Before you begin, ensure you have the following installed and configured:

-   **Azure CLI:** Authenticated to your Azure account.
    -   Run `az login` and `az account set --subscription "<Your-Subscription-ID>"`.
-   **Terraform:** Version `1.0.0` or newer.
-   **GitHub Account:** With permissions to manage repository secrets and variables.
-   **Permissions:** You need sufficient permissions in the target Azure subscription to create resource groups, managed identities, and assign roles (e.g., `Owner` or `Contributor`).

## 2. Phase 1: Bicep Bootstrap

The first phase involves running a Bicep template to create the core resources required for a secure Terraform deployment. This step is performed once per environment.

### 2.1. What it Creates

The Bicep bootstrap (`TF-Bootstrap/Bootstrap/bootstrap.bicep`) provisions the following:

1.  **User-Assigned Managed Identity:**
    -   **Resource:** `Microsoft.ManagedIdentity/userAssignedIdentities`
    -   **Purpose:** Creates a managed identity (`id-wss-lab-sec-2`) that GitHub Actions will use to authenticate to Azure. This avoids using long-lived service principal secrets.
    -   **Federated Credential:** A federated identity credential is created and linked to the managed identity. This credential establishes a trust relationship with your GitHub repository, allowing workflows from the `main` branch to request Azure AD tokens.

2.  **Storage Account for Terraform State:**
    -   **Resource:** `Microsoft.Storage/storageAccounts`
    -   **Purpose:** Creates a storage account (`sttfwsslabsec001`) and a blob container (`tfstate`) to store the Terraform state file (`.tfstate`). Storing state remotely is crucial for team collaboration and security.

### 2.2. How to Run It

1.  **Navigate to the bootstrap directory:**
    ```bash
    cd TF-Bootstrap/Bootstrap
    ```

2.  **Modify the `bootstrap.bicep` file (if necessary):**
    -   Update the `githubRepo` parameter to match your GitHub repository (`<Your-Username>/<Your-Repo-Name>`).
    -   The `storageAccountName` is hardcoded; ensure it is globally unique. If the deployment fails due to a name conflict, change it.

3.  **Deploy the Bicep template:**
    Execute the following Azure CLI command. Make sure the resource group (`rg-kolad-sch`) already exists or create it first (`az group create --name rg-kolad-sch --location swedencentral`).

    ```bash
    az deployment group create --resource-group rg-kolad-sch --template-file bootstrap.bicep
    ```

4.  **Grant Permissions:**
    After the Bicep deployment succeeds, you must manually grant the newly created Managed Identity the `Storage Blob Data Contributor` role on the storage account. This allows it to read and write the Terraform state file.

    -   Get the Principal ID of the Managed Identity from the Bicep output.
    -   Run the following command:
        ```bash
        az role assignment create --assignee <Managed-Identity-Principal-ID> --role "Storage Blob Data Contributor" --scope "/subscriptions/<Your-Subscription-ID>/resourceGroups/rg-kolad-sch/providers/Microsoft.Storage/storageAccounts/sttfwsslabsec001"
        ```

## 3. Phase 2: Terraform Deployment

With the bootstrap resources in place, Terraform can now securely deploy the main application infrastructure.

### 3.1. How it Works

The `backend.tf` file is configured to use the `azurerm` backend, pointing to the storage account and container created by Bicep. When Terraform runs (either locally or in GitHub Actions), it authenticates to Azure using the Managed Identity (OIDC) and then loads its state from the remote backend.

### 3.2. Local Setup and Execution

To run Terraform from your local machine, you must configure your environment to authenticate as the Managed Identity.

1.  **Set Environment Variables:**
    Set these variables in your shell to allow Terraform to use OIDC.

    ```powershell
    $env:ARM_CLIENT_ID="<Managed-Identity-Client-ID>"
    $env:ARM_TENANT_ID="<Your-Azure-Tenant-ID>"
    $env:ARM_SUBSCRIPTION_ID="<Your-Subscription-ID>"
    $env:ARM_USE_OIDC="true"
    ```

2.  **Initialize Terraform:**
    Navigate to the root of the repository and run `terraform init`. Terraform will read the `backend.tf` configuration and connect to the remote state file.

3.  **Run Plan and Apply:**
    ```bash
    # See what changes will be made
    terraform plan

    # Apply the changes
    terraform apply
    ```

## 4. GitHub Actions CI/CD

The repository includes two workflows for automated CI/CD: `terraform.yml` and `terraform-destroy.yml`.

### 4.1. Required Secrets and Variables

You must configure the following in your GitHub repository settings under **Settings > Secrets and variables > Actions**:

#### Secrets

These are sensitive values that are encrypted.

| Secret Name               | Description                                         | Example Value                        |
| ------------------------- | --------------------------------------------------- | ------------------------------------ |
| `AZURE_CLIENT_ID`         | The Client ID of the bootstrapped Managed Identity. | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_TENANT_ID`         | Your Azure Active Directory Tenant ID.              | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_SUBSCRIPTION_ID`   | The ID of your Azure subscription.                  | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

#### Variables

These are non-sensitive values.

| Variable Name                    | Description                                                     | Example Value          |
| -------------------------------- | --------------------------------------------------------------- | ---------------------- |
| `BACKEND_RESOURCE_GROUP_NAME`    | The name of the resource group containing the state file.       | `rg-kolad-sch`         |
| `BACKEND_STORAGE_ACCOUNT_NAME`   | The name of the storage account for the state file.             | `sttfwsslabsec001`     |
| `BACKEND_CONTAINER_NAME`         | The name of the blob container for the state file.              | `tfstate`              |

### 4.2. Workflow Explanation

-   **`terraform.yml` (CI/CD Workflow):**
    -   **Trigger:** Runs on a `push` to the `main` branch or on any `pull_request`.
    -   **Authentication:** Uses the `azure/login` action with the configured secrets to get an access token for the Managed Identity.
    -   **Pull Request (CI):** On a pull request, the workflow runs `terraform init`, `fmt`, `validate`, and `plan`. This validates the code and shows a preview of the changes without applying them.
    -   **Push to Main (CD):** On a push to `main`, the workflow runs the same initial steps and then proceeds to `terraform apply -auto-approve`, automatically deploying the changes to Azure.

-   **`terraform-destroy.yml` (Manual Destroy Workflow):**
    -   **Trigger:** This workflow is triggered manually from the GitHub Actions UI (`workflow_dispatch`).
    -   **Purpose:** Provides a safe and controlled way to destroy all infrastructure managed by Terraform.
    -   **Action:** It runs `terraform init` and then `terraform destroy -auto-approve`. Use with caution.
