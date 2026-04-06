@description('Location for all resources')
param location string = resourceGroup().location

@description('Application Insights connection string. Use "DISABLED" to disable telemetry, or provide existing connection string. If omitted, new App Insights will be created.')
param appInsightsConnectionString string = ''

@description('Name for new Application Insights (only used if connection string is empty)')
param name string

var shouldCreate = empty(appInsightsConnectionString)
var isDisabled = appInsightsConnectionString == 'DISABLED'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (shouldCreate) {
  name: '${name}-workspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (shouldCreate) {
  name: name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

output connectionString string = shouldCreate
  ? (applicationInsights.?properties.ConnectionString ?? '')
  : (isDisabled ? '' : appInsightsConnectionString)
