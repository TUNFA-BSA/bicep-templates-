param tags object
param virtualMachine_parameters object
param landingZone_parameters object
param diskEncryptionSet_parameters object
param dataDisk_list object
param keyVault object
param keyVaultEncryption object

param VnetID string
param networkSecurityGroupVM string

@description('Domain NetBiosName plus User name of a domain user with sufficient rights to perfom domain join operation. E.g. domain\\username')
param domainJoinUserName string

@description('Domain user password')
@secure()
param domainJoinUserPassword string

resource kv 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVault.keyvaultname
  scope: resourceGroup(subscription().subscriptionId, resourceGroup().name)
}

resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2022-07-02'={

  name:diskEncryptionSet_parameters.name
  location:landingZone_parameters.location
  tags:tags
  identity:{
    type:diskEncryptionSet_parameters.type
  }
  properties:{
    activeKey:{
      sourceVault:{
        id:keyVaultEncryption.resourceID
      }
      keyUrl:keyVaultEncryption.keyVaultKeyUriWithVersion
      }
    encryptionType:diskEncryptionSet_parameters.encryptionType
    rotationToLatestKeyVersionEnabled: diskEncryptionSet_parameters.rotationToLatestKeyVersionEnabled
  }
}

@description('Access Policy for the Disk Encryption Set')
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01'={
  name: '${keyVaultEncryption.keyVaultEncryptionName}/add'
  properties: {
    accessPolicies:[
      {
        objectId: diskEncryptionSet.identity.principalId
        
        permissions: {
          secrets:[
            'get'
          ]
          keys:[
            'Get'
            'WrapKey'
            'UnwrapKey'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]  
  }
}

module virtualMachine 'vm-windows-app.bicep' = [ for i in range(1,length(virtualMachine_parameters)):{
  name: '${virtualMachine_parameters['vm${i}'].name}-VM${i}'
  params: {
    networkInterfaceName:'${virtualMachine_parameters['vm${i}'].name}-NIC0${i}'
    domainJoinUserName:domainJoinUserName
    domainJoinUserPassword:domainJoinUserPassword
    dataDisk_list:dataDisk_list
    virtualMachine_parameters:virtualMachine_parameters['vm${i}']
    landingZone_parameters:landingZone_parameters
    networkSecurityGroupVM : networkSecurityGroupVM
    tags:tags
    diskEncryptionDiskID:diskEncryptionSet.id
    adminpassword:kv.getSecret('vm${i}AdminPassword')
    VnetID:VnetID
  }
}]

output virtualMachine array =  [for i in range(0, length(virtualMachine_parameters)): {
  virtualMachineName: virtualMachine[i].name
}]
