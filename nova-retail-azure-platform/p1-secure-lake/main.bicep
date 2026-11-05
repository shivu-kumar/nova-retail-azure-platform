// Project 1: Secure data lake foundation
// Deploys: VNet, ADLS Gen2 (bronze/silver/gold), Key Vault, user-assigned managed identity,
// private endpoints (blob, dfs, vault) with private DNS zones, and RBAC role assignments.
targetScope = 'resourceGroup'

@description('Short workload name used in resource names (lowercase letters/digits, max 10 chars).')
@maxLength(10)
param workload string = 'novaretail'

@allowed([
  'dev'
  'test'
  'prod'
])
param env string = 'dev'

param location string = resourceGroup().location

@description('Optional: your public IP, to reach the lake from your machine while learning. Leave empty for fully private.')
param clientIp string = ''

@description('Deploy private DNS zones and private endpoints (Part 1C). Leave false for Part 1B.')
param deployPrivateNetworking bool = false

param tags object = {
  workload: workload
  environment: env
  project: 'p1-nova-retail'
}

var suffix = uniqueString(resourceGroup().id)
var storageName = toLower('st${workload}${env}${take(suffix, 6)}')
var kvName = 'kv-${workload}-${env}-${take(suffix, 5)}'
var publicAccess = empty(clientIp) ? 'Disabled' : 'Enabled'
var ipRules = empty(clientIp) ? [] : [
  {
    value: clientIp
    action: 'Allow'
  }
]

// Built-in role definition IDs
var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

var dnsZones = {
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  dfs: 'privatelink.dfs.${environment().suffixes.storage}'
  vault: 'privatelink.vaultcore.azure.net'
}

// ---------- Network ----------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${workload}-${env}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.10.0.0/16' ]
    }
    subnets: [
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.10.1.0/24'
        }
      }
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: '10.10.2.0/24'
        }
      }
    ]
  }
}

// ---------- Identity ----------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${workload}-${env}'
  location: location
  tags: tags
}

// ---------- Storage (ADLS Gen2) ----------
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS' // learn why: later compare ZRS/GRS for DR (Project 7)
  }
  properties: {
    isHnsEnabled: true // hierarchical namespace = ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // forces Entra ID auth; no account keys
    publicNetworkAccess: publicAccess
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ipRules
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for name in [ 'bronze', 'silver', 'gold' ]: {
  parent: blobService
  name: name
}]

// ---------- Key Vault ----------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true // RBAC, not legacy access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: env == 'prod' ? true : null // purge protection blocks lab teardown/recreate
    publicNetworkAccess: publicAccess
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: empty(clientIp) ? [] : [
        {
          value: clientIp
        }
      ]
    }
  }
}

// ---------- RBAC ----------
resource raStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, uami.id, storageBlobDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributor)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, uami.id, keyVaultSecretsUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- Private DNS ----------
resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in items(dnsZones): if (deployPrivateNetworking) {
  name: z.value
  location: 'global'
  tags: tags
}]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in items(dnsZones): if (deployPrivateNetworking) {
  parent: zones[i]
  name: 'link-${vnet.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

// ---------- Private endpoints ----------
var endpoints = [
  { name: 'blob', targetId: storage.id, groupId: 'blob', zoneKey: 'blob' }
  { name: 'dfs', targetId: storage.id, groupId: 'dfs', zoneKey: 'dfs' }
  { name: 'vault', targetId: kv.id, groupId: 'vault', zoneKey: 'vault' }
]

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = [for e in endpoints: if (deployPrivateNetworking) {
  name: 'pe-${e.name}-${workload}-${env}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${e.name}'
        properties: {
          privateLinkServiceId: e.targetId
          groupIds: [ e.groupId ]
        }
      }
    ]
  }
}]

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = [for (e, i) in endpoints: if (deployPrivateNetworking) {
  parent: pe[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', dnsZones[e.zoneKey])
        }
      }
    ]
  }
  dependsOn: [
    zones
    zoneLinks
  ]
}]

// ---------- Outputs ----------
output storageAccountName string = storage.name
output keyVaultName string = kv.name
output managedIdentityName string = uami.name
output managedIdentityPrincipalId string = uami.properties.principalId
