param Name string
param Environment string
param Location string = resourceGroup().location

// ======= Variables =======
// Virtual network related variables
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

var EnvironmentTag = {
  exp: 'Experiment'
  dev: 'Dev'
  qa: 'Qa'
  uat: 'Uat'
  stg: 'Staging'
  prd: 'Prod'
}

// Resources groups variables
var azureContainerRegistryRG = 'MHA-Dighub-Artifacts-${Environment}-RG'
var logAnalyticsRG = 'MHA-Dighub-Utilities-${Environment}-RG'

// Resources names variables
var containerRegistryName = 'acrbsl${Environment}weu01'
var logAnalyticsWorkspaceName = 'laws-dighub-${Environment}-weu-01'
var keyVaultName = 'kv-mngmnt-${Environment}-weu-01'

// Deployable resources variables
var userIdentityName = 'uid-${Name}-${Environment}'
var containerAppEnvironmentName = 'ame-${Name}-${Environment}'
var subnetName = 'snet-ame-${Name}-${Environment}-weu-01'

// Defining roles variables
var acrPullRole = resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var kvSecretsUserRole = resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
// ======= Variables end =======

resource rSharedLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logAnalyticsRG)
}

resource rContainersUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userIdentityName
  location: Location
}

resource rVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: VnetName[Environment]
  scope: resourceGroup(ResourceGroupVnet[Environment])
}

resource rContainerAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-11-01' existing = {
  parent: rVirtualNetwork
  name: subnetName
}

resource rKeyVault 'Microsoft.KeyVault/vaults@2022-11-01' existing = {
  name: keyVaultName
}

resource rKeyVaultRole 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(kvSecretsUserRole, rKeyVault.id, userIdentityName)
  scope: rKeyVault
  properties: {
    roleDefinitionId: kvSecretsUserRole
    principalId: rContainersUserIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

module mAssignAcrPullRole './resources/container-app.container-registry.role-assignment.bicep' = {
  name: guid(acrPullRole, containerRegistryName, userIdentityName)
  scope: resourceGroup(azureContainerRegistryRG)
  params: {
    containerAppUserIdentityId: rContainersUserIdentity.id
    containerAppUserIdentityPrincipalId: rContainersUserIdentity.properties.principalId
    acrPullRoleId: acrPullRole
    containerRegistryName: containerRegistryName
  }
}

resource rContainerAppEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' = {
  name: containerAppEnvironmentName
  location: Location
  tags: {
    ApplicationName: 'DevOps'
    BusinessCriticality: 'Medium'
    BusinessUnit: 'DigitalHub'
    Environment: EnvironmentTag[Environment]
    OwnerName: 'EPAM'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: rSharedLogAnalyticsWorkspace.properties.customerId
        sharedKey: rSharedLogAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    vnetConfiguration: {
      infrastructureSubnetId: rContainerAppSubnet.id
      internal: true
    }
    infrastructureResourceGroup: '${resourceGroup().name}-internal'
    zoneRedundant: false
  }
}
