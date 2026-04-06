@description('Location for all resources')
param location string = resourceGroup().location

@description('Default name for Azure Container App, and name prefix for all other resources')
param name string

@description('Azure Container App name')
param containerAppName string = name

@description('Environment name for the Container Apps Environment')
param environmentName string = '${name}-env'

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string

@description('Container image name including tag (e.g., fabric-rti-mcp:latest)')
param imageName string

@description('Resource ID of the user-assigned managed identity for ACR pull')
param identityId string

@description('Client ID of the user-assigned managed identity')
param identityClientId string

@description('Number of CPU cores allocated to the container')
param cpuCores string = '0.5'

@description('Amount of memory allocated to the container')
param memorySize string = '1Gi'

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 10

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Whether to collect telemetry')
param azureMcpCollectTelemetry string

@description('Azure AD Tenant ID')
param azureAdTenantId string

@description('Azure AD Client ID')
param azureAdClientId string

@description('Additional environment variables for the container')
param additionalEnvVars array = []

@description('Use the placeholder image for initial provisioning when the real image has not been pushed to ACR yet')
param fetchLatestRevision bool = true

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: {
    'azd-service-name': 'mcp'
    product: 'fabric-rti-mcp'
  }
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        allowInsecure: false
        transport: 'http'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: acrLoginServer
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          image: fetchLatestRevision ? 'mcr.microsoft.com/k8se/quickstart:latest' : '${acrLoginServer}/${imageName}'
          name: containerAppName
          resources: {
            cpu: json(cpuCores)
            memory: memorySize
          }
          env: concat([
            {
              name: 'FABRIC_RTI_TRANSPORT'
              value: 'http'
            }
            {
              name: 'FABRIC_RTI_HTTP_HOST'
              value: '0.0.0.0'
            }
            {
              name: 'FABRIC_RTI_HTTP_PORT'
              value: '3000'
            }
            {
              name: 'FABRIC_RTI_HTTP_PATH'
              value: '/mcp'
            }
            {
              name: 'FABRIC_RTI_STATELESS_HTTP'
              value: 'true'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: identityClientId
            }
            {
              name: 'AzureAd__Instance'
              value: environment().authentication.loginEndpoint
            }
            {
              name: 'AzureAd__TenantId'
              value: azureAdTenantId
            }
            {
              name: 'AzureAd__ClientId'
              value: azureAdClientId
            }
            {
              name: 'AZURE_MCP_COLLECT_TELEMETRY'
              value: azureMcpCollectTelemetry
            }
            {
              name: 'AZURE_MCP_DANGEROUSLY_DISABLE_HTTPS_REDIRECTION'
              value: 'true'
            }
            {
              name: 'AZURE_MCP_DANGEROUSLY_ENABLE_FORWARDED_HEADERS'
              value: 'true'
            }
          ], !empty(appInsightsConnectionString) ? [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
          ] : [], additionalEnvVars)
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppResourceId string = containerApp.id
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name
output containerAppPrincipalId string = containerApp.identity.principalId
output containerAppEnvironmentId string = containerAppsEnvironment.id
