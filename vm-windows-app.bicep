param tags object
param virtualMachine_parameters object
param landingZone_parameters object
param dataDisk_list object

param diskEncryptionDiskID string
param networkInterfaceName string
param networkSecurityGroupVM string
param VnetID string

param domainJoinUserName string
@secure()
param domainJoinUserPassword string
@secure()
param adminpassword string

var aadLoginExtensionName = 'AADLoginForWindows'
var domainJoinOptions = 3
var aadExtension = true


resource networkInterface 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: networkInterfaceName
  location: landingZone_parameters.location
  tags:tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: VnetID
          }
          privateIPAddress: virtualMachine_parameters.privateIP
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup:{
      id:networkSecurityGroupVM
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: virtualMachine_parameters.name
  location: landingZone_parameters.location
  tags: tags
  identity:{
    type:'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: virtualMachine_parameters.size
    }

    storageProfile: {
      osDisk: {
        osType: virtualMachine_parameters.osType
        createOption: 'fromImage'
        name: '${virtualMachine_parameters.name}_DSK01'
        caching: 'ReadWrite'
        diskSizeGB:virtualMachine_parameters.osDiskSize
        managedDisk: {
          storageAccountType: virtualMachine_parameters.osDiskType
          diskEncryptionSet:{
            id:diskEncryptionDiskID
          }
        } 
        deleteOption:'Delete'
      }
      imageReference: {
        publisher: virtualMachine_parameters.publisher //'MicrosoftWindowsServer'
        offer: virtualMachine_parameters.imageOffer
        sku: virtualMachine_parameters.OSVersion
        version: 'latest'
      }
      dataDisks:[for i in range(1,length(dataDisk_list)): {
        
          name: '${virtualMachine_parameters.name}_DSK0${i+1}'
          createOption: 'Empty'
          caching: 'ReadOnly'
          writeAcceleratorEnabled: false
          diskSizeGB: dataDisk_list['dataDisk${i}'].size
          lun: i
          managedDisk:{
            diskEncryptionSet:{
              id: diskEncryptionDiskID
            }
            storageAccountType: 'Premium_LRS'
          }
      }]
    }
      
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    osProfile: {
      computerName: virtualMachine_parameters.name
      adminUsername: virtualMachine_parameters.adminUsername
      adminPassword: adminpassword
      
      windowsConfiguration:{
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: false
          patchMode: 'AutomaticByOS'
        }
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource availabilitySet 'Microsoft.Compute/availabilitySets@2019-07-01' = if(virtualMachine_parameters.needAvailabilitySet==true) {
  name: virtualMachine_parameters.availabilitySet.availabilitySetName
  location: landingZone_parameters.location
  properties: {
    platformFaultDomainCount: virtualMachine_parameters.availabilitySet.availabilitySetPlatformFaultDomainCount
    platformUpdateDomainCount: virtualMachine_parameters.availabilitySet.availabilitySetPlatformUpdateDomainCount
  }
  sku: {
    name: 'Aligned'
  }
}

////////////////////////////////////
/////////// EXTENSIONS ////////////
//////////////////////////////////

// Azure Active Directory Login

@description('adding Azure Active Directory Login Extension')
resource virtualMachineName_aadLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2018-10-01' = if (aadExtension){
  parent: virtualMachine
  name: aadLoginExtensionName
  location: landingZone_parameters.location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: aadLoginExtensionName
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      mdmId: ''
    }
  }
  tags: tags
}

// add to the domain extension

@description('Script for remove VM from Workgroup')
resource removeWorkgroup 'Microsoft.Compute/virtualMachines/runCommands@2022-03-01' = {
  parent: virtualMachine
  name: 'removeWorkgroup-${virtualMachine_parameters.name}'
  location: landingZone_parameters.location
  properties: {
    source: {
      script: 'DSRegCmd /Leave'
    }
    timeoutInSeconds: 3600
  }
  dependsOn: [
    virtualMachineName_aadLoginExtension
  ]
}



@description('Extension for Join VM to Domain')
resource joindomain 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
  parent: virtualMachine
  name: 'joindomain'
  location: landingZone_parameters.location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      Name: virtualMachine_parameters.domainFQDN
      User: domainJoinUserName
      Restart: 'true'
      Options: domainJoinOptions
      OUPath: virtualMachine_parameters.ouPath
    }
    protectedSettings: {
      Password: domainJoinUserPassword
    }
  }
  dependsOn: [
    removeWorkgroup
  ]
}

////////////////////////////////////////
//////////// Scripts //////////////////
//////////////////////////////////////

@description('Script for Default Format Data Disks on Windows Machine')
resource formatDisks 'Microsoft.Compute/virtualMachines/runCommands@2022-03-01' = {
  parent: virtualMachine
  name: 'formatDisks-${virtualMachine.name}'
  location: landingZone_parameters.location
  properties: {
    source: {
//      script: loadTextContent('../scripts/format-disks.ps1')
    }
  }
}

/////////// outputs

output vmappName string =  virtualMachine.name
output adminUsername string = virtualMachine_parameters.adminUsername
output identity string = virtualMachine.identity.principalId
output vmID string = virtualMachine.id
