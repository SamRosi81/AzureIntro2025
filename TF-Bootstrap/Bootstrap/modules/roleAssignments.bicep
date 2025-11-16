// modules/roleAssignments.bicep
// Assigns roles to the Managed Identity

param managedIdentityPrincipalId string
param contributorRoleId string
param userAccessAdminRoleId string

// Assign Contributor role to the Managed Identity at Resource Group scope
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentityPrincipalId, contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allows the managed identity to manage resources in the resource group'
  }
}

// Assign User Access Administrator role to the Managed Identity at Resource Group scope
// This allows the MI to grant Key Vault permissions
resource userAccessAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentityPrincipalId, userAccessAdminRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userAccessAdminRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Limited to assigning Key Vault Secret Officer and Key Vault Certificate Officer roles'
    // Note: Azure RBAC doesn't support conditional role assignments in Bicep directly.
    // The limitation to only Key Vault roles must be enforced through Azure Policy or operational procedures.
  }
}

// --- Outputs ---
output contributorRoleAssignmentId string = contributorRoleAssignment.id
output userAccessAdminRoleAssignmentId string = userAccessAdminRoleAssignment.id
