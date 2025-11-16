// modules/mi.bicep
// Creates a User-Assigned Managed Identity and a Federated Credential for GitHub Actions OIDC.

param location string
param managedIdentityName string
param githubRepo string

// Create the User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Create the Federated Identity Credential to link the MI with your GitHub repository
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  // The parent is the Managed Identity created above
  parent: managedIdentity
  // A descriptive name for the credential
  name: 'github-federated-credential'
  properties: {
    // The issuer URL for GitHub Actions is always the same
    issuer: 'https://token.actions.githubusercontent.com'
    // The audiences value for Azure is always the same
    audiences: [
      'api://AzureADTokenExchange'
    ]
    // The subject line MUST match your repository and branch/tag/environment
    // Format: repo:<OWNER>/<REPO>:environment:<ENVIRONMENT_NAME>
    // Note: We are targeting the 'production' environment from GitHub Actions
    subject: 'repo:${githubRepo}:environment:production'
  }
}

// --- Outputs ---
output name string = managedIdentity.name
output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
output resourceId string = managedIdentity.id
