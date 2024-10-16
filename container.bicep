param ImageName string
param ImageTag string
param Environment string
param ContainerAppName string
param EnvironmentVariables array
param Secrets array
param Scaling object
param Location string = resourceGroup().location

var azureContainerRegistryRG = 'MHA-Dighub-Artifacts-${Environment}-RG'
var containerRegistryName = 'acrbsl${Environment}weu01'
var keyVaultName = 'kv-mngmnt-${Environment}-weu-01'
var systemAssignedUserRoles = [
  {
    name: 'storage-blob-contributor'
    id: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
  {
    name: 'storage-account-contributor'
    id: resourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  }
  {
    name: 'cdn-endpoint-contributor'
    id: resourceId('Microsoft.Authorization/roleDefinitions', '426e0c7f-0c7e-4658-b36f-ff54d6c29b45')
  }
]

resource rSharedContainerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: containerRegistryName
  scope: resourceGroup(azureContainerRegistryRG)
}

resource rContainerAppEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' existing = {
  name: 'ame-${ContainerAppName}-${Environment}'
}

resource rContainerUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'uid-${ContainerAppName}-${Environment}'
}

var secretsObject = [for secret in Secrets: {
  name: toLower(secret)
  keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/${secret}'
  identity: rContainerUserIdentity.id
}]

resource rContainerApp 'Microsoft.App/containerApps@2023-04-01-preview' = {
  name: '${Environment}-${ContainerAppName}'
  location: Location
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${rContainerUserIdentity.id}': {}
    }
  }
  properties: {
    environmentId: rContainerAppEnvironment.id
    configuration: {
      secrets: secretsObject
      registries: [
        {
          identity: rContainerUserIdentity.id
          server: rSharedContainerRegistry.properties.loginServer
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: ImageName
          image: '${rSharedContainerRegistry.properties.loginServer}/${ImageName}:${ImageTag}'
          command: []
          resources: {
            cpu: Scaling.Cpu
            memory: Scaling.Memory
          }
          env: EnvironmentVariables
        }
      ]
      scale: {
        minReplicas: Scaling.Minimum
        maxReplicas: Scaling.Maximum
        rules: Scaling.Rules
      }
    }
  }
}

module mStorageAccountBlobContributorRoleAssignemnt 'resources/container-app.subscription.role-assignmnet.bicep' = [for role in systemAssignedUserRoles: {
  name: '${rContainerApp.name}-role-${role.name}'
  scope: subscription()
  params: {
    ContainerAppIdentityId: rContainerApp.identity.principalId
    RoleId: role.id
  }
}]
