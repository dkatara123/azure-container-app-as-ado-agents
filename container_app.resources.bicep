param Environment string
param ContainerAppSubnetPrefix object
param IpRulesKv array
param ContainerAppNames array
param Location string = resourceGroup().location

// variables
var logAnalyticsRG = 'MHA-Dighub-Utilities-${Environment}-RG'
var keyVaultName = 'kv-mngmnt-${Environment}-weu-01'
var logAnalyticsWorkspaceName = 'laws-dighub-${Environment}-weu-01'
var tenantId = subscription().tenantId

resource rSharedLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logAnalyticsRG)
}

var VnetName = {
  exp: 'vnet-dighub-exp-weu-01'
  dev: 'vnet-dighub-dev-weu-01'
  qa: 'vnet-dighub-qa-weu-01'
  uat: 'vnet-dighub-uat-weu-01'
  stg: 'vnet-dighub-staging-weu-01'
  prd: 'vnet-dighub-prod-weu-01'
}
var ResourceGroupVnet = {
  exp: 'MHA-Dighub-ExpVnet-RG'
  dev: 'MHA-Dighub-DevVnet-RG'
  qa: 'MHA-Dighub-QaVnet-RG'
  uat: 'MHA-Dighub-UatVnet-RG'
  stg: 'MHA-Dighub-StagingVnet-RG'
  prd: 'MHA-Dighub-ProdVnet-RG'
}

module mContainerAppSubnetDeployment './resources/container-app.subnet.bicep' = [for name in ContainerAppNames: {
  name: 'ContainerAppSubnetDeployment-${name}'
  scope: resourceGroup(ResourceGroupVnet[Environment])
  params: {
    Location: Location
    VnetName: VnetName[Environment]
    ContainerAppSubnetAddressPrefix: ContainerAppSubnetPrefix[name][Environment]
    SubnetName: 'snet-ame-${name}-${Environment}-weu-01'
  }
}]

resource rKeyVault 'Microsoft.KeyVault/vaults@2021-10-01' = {
  name: keyVaultName
  location: Location
  tags: {
    Environment: Environment
    'DigHub-Component': 'Management'
    'Downtime Cost': 'Medium'
    sensitive: 'true'
    Purpose: 'used for store secrets for management-console and self-hosted agent'
  }
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableSoftDelete: true
    tenantId: tenantId
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: IpRulesKv
      virtualNetworkRules: [for i in range(0, length(ContainerAppNames)): {
        id: mContainerAppSubnetDeployment[i].outputs.SubnetId
      }
      ]
    }
  }
}

resource rDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: keyVaultName
  scope: rKeyVault
  properties: {
    workspaceId: rSharedLogAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}
