// This Bicep template helps you deploy AKS on Azure Stack HCI
// It will deploy 3 resources:  Logical Network, Connected Cluster, Provisioned Cluster Instance
// Read more on my blog: https://

//----------------
// PARAMETERS
//----------------

// Parameters - Global

@description('The geo-location where the resources will live')
param location string = 'eastus'

@description('Full Resource ID of the existing Custom Location')
param customLocation string = '/subscriptions/xxx/resourceGroups/yyy/providers/Microsoft.ExtendedLocation/customLocations/zzz'

// Parameters - Logical Network

@description('Resource name to use for the Logical Network')
param logicalNetworkName string

@description('Name of local virtual switch on the HCI Cluster')
param vmSwitchName string = 'ConvergedSwitch(compute_management)'

@description('IP Range to use for the Logical Network in CIDR format')
param addressPrefix string = '10.1.2.0/24'

@description('One or more IP Pools to use, must be taken from the CIDR range')
param ipPools array = [
  {
    start: '10.1.2.50'
    end: '10.1.2.250'
  }
]

@description('Default Gateway to use with your Logical Network')
param defaultGateway string = '10.1.2.1'

@description('One or more DNS Servers to use with your Logical Network')
param dnsServers array = [
  '10.1.2.2'
]

@description('The VLAN ID used by the CIDR range')
param vlan int = 4

@description('Azure Tags to apply to the Logical Network')
param resourceTagsLogicalNetwork object = {}

// Parameters - Connected Cluster

@description('The resource name to use for the AKS cluster')
param provisionedClusterName string = 'MyAksCluster'

@description('The identity of the connected cluster. Options: None, SystemAssigned')
param identityType string = 'SystemAssigned'

@description('Object ID for an Entra ID group that will be granted admin access to the AKS cluster')
param adminGroupObjectIDs array = [
  'xxx'
]

@description('Azure Tags to apply to the AKS cluster')
param resourceTagsAks object = {}

// Parameters - Provisioned Cluster Instances

@description('Version of AKS to deploy')
param kubernetesVersion string = 'v1.27.3'

@description('The configuration of the Agent Node Pool(s)')
param agentPoolProfiles array = [
  {
    count: 3
    name: 'nodepool1'
    osType: 'Linux'
    vmSize: 'Standard_A4_v2'
  }
]

@description('IP to use for the Control Plane. Must be in the Logical Network CIDR, but NOT inside an IP Pool')
param controlPlaneIp string = '10.1.2.11'

@description('How many Control Plane nodes to create. Options: 1, 3, 5')
param controlPlaneNodeCount int = 3

@description('Size of the Control Plane nodes')
param controlPlaneNodesize string = 'Standard_A4_v2'

@description('SSH public key used to authenticate with VMs')
param keyData string = 'ssh-rsa xxxxxx'

@description('Network policy used for building Kubernetes network. Options: calico')
param networkPolicy string = 'calico'

@description('A CIDR notation IP Address range from which to assign pod IPs.')
param podCidr string = '10.244.0.0/16'

//----------------
// RESOURCES
//----------------

resource logicalNetwork 'microsoft.azurestackhci/logicalnetworks@2023-09-01-preview' = {
  name: logicalNetworkName
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocation
  }
  tags: resourceTagsLogicalNetwork
  properties: {
    subnets: [
      {
        name: logicalNetworkName
        properties: {
          ipAllocationMethod: 'Static'
          addressPrefix: addressPrefix
          vlan: vlan
          ipPools: ipPools
          routeTable: {
            properties: {
              routes: [
                {
                  name: logicalNetworkName
                  properties: {
                    addressPrefix: '0.0.0.0/0'
                    nextHopIpAddress: defaultGateway
                  }
                }
              ]
            }
          }
        }
      }
    ]
    vmSwitchName: vmSwitchName
    dhcpOptions: {
      dnsServers: dnsServers
    }
  }
}

resource provisionedCluster 'Microsoft.Kubernetes/ConnectedClusters@2024-01-01' = {
  kind: 'ProvisionedCluster'
  name: provisionedClusterName
  location: location
  tags: resourceTagsAks
  identity: {
    type: identityType
  }
  properties: {
    agentPublicKeyCertificate: ''
    aadProfile: {
      enableAzureRBAC: false
      adminGroupObjectIDs: adminGroupObjectIDs
    }
  }
}

resource clusterInstance 'Microsoft.HybridContainerService/ProvisionedClusterInstances@2024-01-01' = {
  scope: provisionedCluster
  name: 'default'
  extendedLocation: {
    type: 'customLocation'
    name: customLocation
  }
  properties: {
    agentPoolProfiles: agentPoolProfiles
    cloudProviderProfile: {
      infraNetworkProfile: {
        vnetSubnetIds: [
          logicalNetwork.id
        ]
      }
    }
    controlPlane: {
      controlPlaneEndpoint: {
        hostIP: controlPlaneIp
      }
      count: controlPlaneNodeCount
      vmSize: controlPlaneNodesize
    }
    kubernetesVersion: kubernetesVersion
    linuxProfile: {
      ssh: {
        publicKeys: [
          {
            keyData: keyData
          }
        ]
      }
    }
    networkProfile: {
      loadBalancerProfile: {
        count: 0
      }
      networkPolicy: networkPolicy
      podCidr: podCidr
    }
  }
}
