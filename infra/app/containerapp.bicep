@description('Name of the Container App')
param name string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Tags for resources')
param tags object = {}

@description('Name of the Container App Environment')
param containerAppEnvName string

@description('Name of the ACR')
param containerRegistryName string

@description('Container image name (without registry prefix)')
param imageName string

@description('Resource ID of the user-assigned managed identity')
param identityId string

@description('Client ID of the user-assigned managed identity')
param identityClientId string

@description('Application Insights connection string')
param applicationInsightsConnectionString string = ''

@description('Environment variables for the container')
param envVars array = []

@description('Target port the container listens on')
param targetPort int = 3000

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 10

@description('CPU cores allocated to the container')
param cpuCores string = '0.5'

@description('Memory allocated to the container')
param memory string = '1Gi'

// Container App Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// Base env vars that are always set
var baseEnvVars = [
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }
  { name: 'AZURE_CLIENT_ID', value: identityClientId }
]

var allEnvVars = union(baseEnvVars, envVars)

// Container App
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': 'mcp' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp-server'
          image: '${acr.properties.loginServer}/${imageName}'
          resources: {
            cpu: json(cpuCores)
            memory: memory
          }
          env: allEnvVars
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: targetPort
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
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// Role assignment: AcrPull for the managed identity on the ACR
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identityId, acrPullRoleId)
  scope: acr
  properties: {
    principalId: reference(identityId, '2023-01-31').principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output uri string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppEnvName string = containerAppEnv.name
output registryLoginServer string = acr.properties.loginServer
output registryName string = acr.name
