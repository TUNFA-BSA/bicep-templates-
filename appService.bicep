param landingZone_parameters object
param appService_parameters object
param tags object

param appServicePlanId string
param acrName string
param managedIdentityId string
param managedIdentityIdClient string 
@description('Enable system identity for App Service (sys: SystemAssigned   usr:UserAssigned  non:None)')
param enableSystemIdentity string = 'usr'

param logAnalyticsWorkspaceID string
param subnetRef string

param appInsightsInstrumentationKey string
param appInsightsConnectionString string
param acrLoginServer string

resource appServiceApp 'Microsoft.Web/sites@2022-03-01' = {
  name: appService_parameters.name
  location: landingZone_parameters.location
  kind: appService_parameters.kind
  identity: {
    type: enableSystemIdentity == 'sys' ? 'SystemAssigned' : enableSystemIdentity == 'usr' ? 'UserAssigned' : 'None'
    userAssignedIdentities: (enableSystemIdentity == 'usr') ? {
      '${managedIdentityId}': {}
    } : null
  }
  tags: tags
  properties: {
    vnetRouteAllEnabled: true
    enabled: true
    serverFarmId: appServicePlanId
    httpsOnly: false
    virtualNetworkSubnetId: subnetRef
    siteConfig: {
      numberOfWorkers: 1
      defaultDocuments: [
        'Default.htm'
        'Default.html'
        'Default.asp'
        'index.htm'
        'index.html'
        'iisstart.htm'
        'default.aspx'
        'index.php'
        'hostingstart.html'
      ]
      linuxFxVersion: 'DOCKER|${acrName}.azurecr.io/${appService_parameters.docker.container}:${appService_parameters.docker.version}'
      acrUseManagedIdentityCreds: true
      netFrameworkVersion: appService_parameters.netFrameworkVersion
      acrUserManagedIdentityID: managedIdentityIdClient
      alwaysOn: true
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      publicNetworkAccess: 'Disabled'
      ftpsState:'FtpsOnly'
      scmIpSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      appSettings:[
        {
          name:'DOCKER_REGISTRY_SERVER_URL'
          value: acrLoginServer
        }
        {
          name:'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name:'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name:'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name:'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3 (Linux)'
        }
        {
          name:'XDT_MicrosoftApplicationInsights_Mode'
          value: 'default'
        }
      ]
    }
  }

}

resource appServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appServiceDiagnosticSettings'
  scope: appServiceApp
  properties:{
    workspaceId: logAnalyticsWorkspaceID
    logs: [
      {
        category: 'AppServiceAntivirusScanAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceFileAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: false
        retentionPolicy:{
          days: 0
          enabled: false 
        }
      }
    ]
  }
}

output id string = appServiceApp.id
output name string = appServiceApp.name
output defaultHostName string = appServiceApp.properties.defaultHostName
