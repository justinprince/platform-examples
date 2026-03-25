targetScope = 'subscription'

@description('Resource group name for the image copy deployment.')
param resourceGroupName string

@description('Azure region for the deployment.')
param location string = 'eastus'

@description('Base name used to derive Azure resource names.')
param workloadName string = 'image-copy-acr'

// The image is built into the target ACR using `az acr build` and is not a
// direct deployment parameter. See README for build instructions.

@description('CPU requested by the Container App, for example 0.25, 0.5, or 1.0.')
param containerCpu string = '0.25'

@description('Memory requested by the Container App.')
param containerMemory string = '0.5Gi'

@description('Port exposed by the service.')
param containerPort int = 8080

@description('Name of the existing target Azure Container Registry.')
param acrName string

@description('Resource group that contains the target Azure Container Registry.')
param acrResourceGroupName string

@description('Destination repository prefix in ACR, including registry host, for example myregistry.azurecr.io/mirrors. If empty, defaults to "<acrName>.azurecr.io/cgr-image-copy"')
param dstRepoPrefix string = ''

// If the caller omitted `dstRepoPrefix`, synthesize a default using the
// provided `acrName`. This keeps the operator experience simple while still
// allowing explicit overrides.
var computedDstRepoPrefix = empty(dstRepoPrefix) ? '${acrName}.azurecr.io/cgr-image-copy' : dstRepoPrefix

@description('Path to the Dockerfile to use when building the runtime image. Can be a repo-local path.')
param dockerfilePath string = 'Dockerfile'

@description('UTC tag to force update of deployment script; default uses current time.')
param utcValue string = utcNow()

@description('Chainguard issuer URL.')
param issuerUrl string = 'https://issuer.enforce.dev'

@description('Chainguard API endpoint.')
param apiEndpoint string = 'https://console-api.enforce.dev'

@description('Chainguard source group name.')
param groupName string

@description('Chainguard source group ID.')
param groupId string

@description('Chainguard identity ID used by the service.')
param identityId string

@secure()
@description('Bootstrap OIDC token required by the current app code path for Chainguard token exchange.')
param chainguardOidcToken string = ''

@description('Skip referrer tags such as signatures and attestations.')
param ignoreReferrers bool = true

@description('Verify signatures before copying an image.')
param verifySignatures bool = false

@description('Apply external ingress to the Container App.')
param externalIngress bool = true

@description('Tags applied to created Azure resources.')
param tags object = {}

resource deploymentRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module workload './modules/workload.bicep' = {
  name: '${workloadName}-workload'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    workloadName: workloadName
    containerCpu: containerCpu
    containerMemory: containerMemory
    containerPort: containerPort
    acrName: acrName
    acrResourceGroupName: acrResourceGroupName
    dstRepoPrefix: computedDstRepoPrefix
    dockerfilePath: dockerfilePath
    utcValue: utcValue
    issuerUrl: issuerUrl
    apiEndpoint: apiEndpoint
    groupName: groupName
    groupId: groupId
    identityId: identityId
    chainguardOidcToken: chainguardOidcToken
    ignoreReferrers: ignoreReferrers
    verifySignatures: verifySignatures
    externalIngress: externalIngress
    tags: tags
  }
}

// Existing reference to the target ACR (in a possibly different resource group).
resource targetRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  scope: resourceGroup(subscription().subscriptionId, acrResourceGroupName)
  name: acrName
}

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')

// Assign AcrPull and AcrPush to the Container App managed identity on the
// target registry. These role assignments are created at subscription scope
// and scoped to the target registry resource.
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetRegistry.id, workload.outputs.containerAppName, 'AcrPull')
  scope: targetRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: workload.outputs.managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetRegistry.id, workload.outputs.containerAppName, 'AcrPush')
  scope: targetRegistry
  properties: {
    roleDefinitionId: acrPushRoleDefinitionId
    principalId: workload.outputs.managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Create a deployment script in the workload resource group to build the
// runtime image and grant it AcrPush on the target registry.
resource acrBuildScript 'Microsoft.Resources/deploymentScripts@2023-01-01' = {
  name: '${workloadName}-acrBuild'
  scope: resourceGroup(resourceGroupName)
  location: resourceGroup(resourceGroupName).location
  kind: 'AzureCLI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    forceUpdateTag: utcValue
    azCliVersion: '2.42.0'
    timeout: 'PT30M'
    scriptContent: 'az acr build --registry ${acrName} --image cgr-image-copy:v1 --file ${dockerfilePath} .'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

resource acrBuildScriptPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetRegistry.id, acrBuildScript.name, 'AcrPush')
  scope: targetRegistry
  dependsOn: [ acrBuildScript ]
  properties: {
    roleDefinitionId: acrPushRoleDefinitionId
    principalId: acrBuildScript.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output resourceGroup string = deploymentRg.name
output containerAppName string = workload.outputs.containerAppName
output serviceUrl string = workload.outputs.serviceUrl
output managedIdentityPrincipalId string = workload.outputs.managedIdentityPrincipalId
