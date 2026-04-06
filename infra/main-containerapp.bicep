@description('Location for all resources')
param location string

@description('Name for the Azure Container App')
param acaName string

@description('Display name for the Entra App')
param entraAppDisplayName string

@description('Microsoft Foundry project resource ID for assigning Entra App role to Foundry project managed identity')
param foundryProjectResourceId string

@description('Service Management Reference for the Entra Application. Optional GUID used to link the app to a service in Azure.')
param serviceManagementReference string = ''

@description('Application Insights connection string. Use "DISABLED" to disable telemetry, or provide existing connection string. If omitted, new App Insights will be created.')
param appInsightsConnectionString string = ''

@description('Kusto known services JSON configuration')
param kustoKnownServices string = ''

// Deploy Application Insights if appInsightsConnectionString is empty and not DISABLED
var appInsightsName = '${acaName}-insights'

module appInsights 'modules/application-insights.bicep' = {
  name: 'application-insights-deployment'
  params: {
    appInsightsConnectionString: appInsightsConnectionString
    name: appInsightsName
    location: location
  }
}

// Deploy Entra App
var entraAppUniqueName = '${replace(toLower(entraAppDisplayName), ' ', '-')}-${uniqueString(resourceGroup().id)}'

module entraApp 'modules/entra-app.bicep' = {
  name: 'entra-app-deployment'
  params: {
    entraAppDisplayName: entraAppDisplayName
    entraAppUniqueName: entraAppUniqueName
    serviceManagementReference: serviceManagementReference
  }
}

// ACR for hosting the Fabric RTI MCP container image
var acrName = replace('cr${acaName}${uniqueString(resourceGroup().id)}', '-', '')

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: length(acrName) > 50 ? substring(acrName, 0, 50) : acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// User-assigned managed identity for ACR pull
var identityName = '${acaName}-identity'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// AcrPull role assignment for managed identity
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, userAssignedIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Additional env vars for Fabric RTI MCP
var additionalEnvVars = concat([
  {
    name: 'KUSTO_EAGER_CONNECT'
    value: 'false'
  }
], !empty(kustoKnownServices) ? [
  {
    name: 'KUSTO_KNOWN_SERVICES'
    value: kustoKnownServices
  }
] : [])

// Deploy ACA Infrastructure to host Fabric RTI MCP Server
module acaInfrastructure 'modules/aca-infrastructure.bicep' = {
  name: 'aca-infrastructure-deployment'
  params: {
    name: acaName
    location: location
    acrLoginServer: acr.properties.loginServer
    imageName: 'fabric-rti-mcp:latest'
    identityId: userAssignedIdentity.id
    identityClientId: userAssignedIdentity.properties.clientId
    appInsightsConnectionString: appInsights.outputs.connectionString
    azureMcpCollectTelemetry: string(!empty(appInsights.outputs.connectionString))
    azureAdTenantId: tenant().tenantId
    azureAdClientId: entraApp.outputs.entraAppClientId
    additionalEnvVars: additionalEnvVars
  }
  dependsOn: [
    acrPullRole
  ]
}

// Deploy Entra App role assignment for Microsoft Foundry project MI to access ACA
module foundryRoleAssignment 'modules/foundry-role-assignment-entraapp.bicep' = if (!empty(foundryProjectResourceId)) {
  name: 'foundry-role-assignment'
  params: {
    foundryProjectResourceId: foundryProjectResourceId
    entraAppServicePrincipalObjectId: entraApp.outputs.entraAppServicePrincipalObjectId
    entraAppRoleId: entraApp.outputs.entraAppRoleId
  }
}

// Outputs for azd and other consumers
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_LOCATION string = location

// Entra App outputs
output ENTRA_APP_CLIENT_ID string = entraApp.outputs.entraAppClientId
output ENTRA_APP_OBJECT_ID string = entraApp.outputs.entraAppObjectId
output ENTRA_APP_SERVICE_PRINCIPAL_ID string = entraApp.outputs.entraAppServicePrincipalObjectId
output ENTRA_APP_ROLE_ID string = entraApp.outputs.entraAppRoleId
output ENTRA_APP_IDENTIFIER_URI string = entraApp.outputs.entraAppIdentifierUri

// ACA Infrastructure outputs
output CONTAINER_APP_URL string = acaInfrastructure.outputs.containerAppUrl
output CONTAINER_APP_NAME string = acaInfrastructure.outputs.containerAppName
output CONTAINER_APP_PRINCIPAL_ID string = acaInfrastructure.outputs.containerAppPrincipalId
output AZURE_CONTAINER_APP_ENVIRONMENT_ID string = acaInfrastructure.outputs.containerAppEnvironmentId

// ACR outputs
output AZURE_CONTAINER_REGISTRY_NAME string = acr.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer

// Application Insights outputs
output APPLICATION_INSIGHTS_NAME string = appInsightsName
output APPLICATION_INSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output AZURE_MCP_COLLECT_TELEMETRY string = string(!empty(appInsights.outputs.connectionString))
