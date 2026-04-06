@description('Microsoft Foundry project resource ID')
@metadata({
  example: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/myResourceGroup/providers/Microsoft.CognitiveServices/accounts/myAccount/projects/firstProject'
})
param foundryProjectResourceId string

@description('Entra App Service Principal Object ID (resourceId in Graph API)')
param entraAppServicePrincipalObjectId string

@description('Entra App Role ID to assign')
param entraAppRoleId string

extension microsoftGraphV1

// Supported formats:
// Account (hub): /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{accountName}
// Project:       /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{accountName}/projects/{projectName}
var resourceIdParts = split(foundryProjectResourceId, '/')
var isProjectResource = length(resourceIdParts) > 10
var projectResourceGroup = resourceIdParts[4]
var accountName = resourceIdParts[8]

// For project-level resources, reference the project
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = if (isProjectResource) {
  scope: resourceGroup(projectResourceGroup)
  name: '${accountName}/${resourceIdParts[10]}'
}

// For account-level resources, reference the account directly
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!isProjectResource) {
  scope: resourceGroup(projectResourceGroup)
  name: accountName
}

var foundryProjectMIPrincipalId = isProjectResource ? foundryProject!.identity.principalId : foundryAccount!.identity.principalId

resource appRoleAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: foundryProjectMIPrincipalId
  resourceId: entraAppServicePrincipalObjectId
  appRoleId: entraAppRoleId
}

output roleAssignmentId string = appRoleAssignment.id
output foundryProjectMIPrincipalId string = foundryProjectMIPrincipalId
