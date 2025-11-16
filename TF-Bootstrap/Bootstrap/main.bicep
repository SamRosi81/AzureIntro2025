// main.bicep
// This is the main entry point for the deployment.
// Deploy using: az deployment group create --resource-group rg-kolad-sch --template-file main.bicep --parameters githubRepo='owner/repo' storageAccountName='yourstorageaccount'

targetScope = 'resourceGroup'

// --- Parameters ---
// These are the values you might want to change for different deployments.

// The Azure region for all resources.
param location string = 'swedencentral'

// Your GitHub repository in the format 'owner/repository'.
@description('GitHub repository in the format owner/repository')
param githubRepo string

// The storage account name (must be globally unique, 3-24 chars, lowercase alphanumeric)
@description('Storage account name for Terraform state (globally unique)')
@minLength(3)
@maxLength(24)
param storageAccountName string

// The branch that will trigger deployments. Use '*' for any branch.
param githubBranch string = 'main'

// --- Variables ---

var storageContainerName = 'tfstate'
var managedIdentityName = 'id-wss-lab-sec-2'

// Contributor role definition ID (built-in role)
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// User Access Administrator role definition ID (built-in role)
var userAccessAdminRoleId = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'

// --- Modules ---
// Calling the modular Bicep files to create the resources.

// Module to deploy the Managed Identity and Federated Credential for GitHub Actions
module managedIdentity 'modules/mi.bicep' = {
  name: 'managedIdentityDeployment'
  params: {
    location: location
    managedIdentityName: managedIdentityName
    githubRepo: githubRepo
  }
}

// Module to deploy the Storage Account for Terraform state
module storageAccount 'modules/st.bicep' = {
  name: 'storageAccountDeployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    storageContainerName: storageContainerName
  }
}

// --- Role Assignments Module ---

// Module to assign roles to the Managed Identity
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignmentsDeployment'
  params: {
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    contributorRoleId: contributorRoleId
    userAccessAdminRoleId: userAccessAdminRoleId
  }
}

// --- Outputs ---
// These are the important values you'll need after deployment.

output managedIdentityName string = managedIdentity.outputs.name
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId
output managedIdentityClientId string = managedIdentity.outputs.clientId
output managedIdentityResourceId string = managedIdentity.outputs.resourceId

output storageAccountName string = storageAccount.outputs.name
output storageContainerName string = storageAccount.outputs.containerName

output contributorRoleAssignmentId string = roleAssignments.outputs.contributorRoleAssignmentId
output userAccessAdminRoleAssignmentId string = roleAssignments.outputs.userAccessAdminRoleAssignmentId
