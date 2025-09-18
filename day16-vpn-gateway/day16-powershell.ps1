# English comments: Day16 end-to-end, no preassigned variables.

New-AzResourceGroup -Name "rg-day16-vpn" -Location "westeurope"

New-AzVirtualNetwork -Name "vnet16weu" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" -AddressPrefix "10.16.0.0/16" | Set-AzVirtualNetwork
Add-AzVirtualNetworkSubnetConfig -Name "snet-app16" -AddressPrefix "10.16.1.0/24" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet16weu" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork
Add-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix "10.16.255.0/27" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet16weu" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork

New-AzVirtualNetwork -Name "vnet-branch16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" -AddressPrefix "10.26.0.0/16" | Set-AzVirtualNetwork
Add-AzVirtualNetworkSubnetConfig -Name "snet-branch16" -AddressPrefix "10.26.1.0/24" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet-branch16" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork
Add-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix "10.26.255.0/27" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet-branch16" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork

New-AzPublicIpAddress -Name "gwpip16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" -Sku "Standard" -AllocationMethod "Static" | Out-Null
New-AzPublicIpAddress -Name "gwpip-branch16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" -Sku "Standard" -AllocationMethod "Static" | Out-Null

New-AzVirtualNetworkGateway -Name "vpngw16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" `
  -IpConfigurations (New-AzVirtualNetworkGatewayIpConfig -Name "gwipconf16" `
    -SubnetId (Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet16weu" -ResourceGroupName "rg-day16-vpn")).Id `
    -PublicIpAddressId (Get-AzPublicIpAddress -Name "gwpip16" -ResourceGroupName "rg-day16-vpn").Id) `
  -GatewayType "Vpn" -VpnType "RouteBased" -GatewaySku "VpnGw1" -EnableBgp -Asn 65515 `
  -VpnClientProtocol "IkeV2","OpenVPN" -VpnClientAddressPool "172.16.16.0/24" | Out-Null

New-AzVirtualNetworkGateway -Name "vpngw-branch16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" `
  -IpConfigurations (New-AzVirtualNetworkGatewayIpConfig -Name "gwipconf-branch16" `
    -SubnetId (Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet-branch16" -ResourceGroupName "rg-day16-vpn")).Id `
    -PublicIpAddressId (Get-AzPublicIpAddress -Name "gwpip-branch16" -ResourceGroupName "rg-day16-vpn").Id) `
  -GatewayType "Vpn" -VpnType "RouteBased" -GatewaySku "VpnGw1" -EnableBgp -Asn 65020 | Out-Null

# Replace <BASE64_ROOT_CERT> with Base64-encoded root .cer
Add-AzVpnClientRootCertificate `
  -VirtualNetworkGateway (Get-AzVirtualNetworkGateway -Name "vpngw16" -ResourceGroupName "rg-day16-vpn") `
  -VpnClientRootCertificateName "day16Root" `
  -PublicCertData "<BASE64_ROOT_CERT>"

Set-AzVirtualNetworkGateway `
  -VirtualNetworkGateway (Get-AzVirtualNetworkGateway -Name "vpngw16" -ResourceGroupName "rg-day16-vpn") `
  -CustomRoute "10.26.0.0/16" `
  -VpnClientProtocol "IkeV2","OpenVPN" `
  -VpnClientAddressPool "172.16.16.0/24" | Out-Null

New-AzVirtualNetworkGatewayConnection `
  -Name "conn-vnet16-to-branch16" `
  -ResourceGroupName "rg-day16-vpn" `
  -Location "westeurope" `
  -VirtualNetworkGateway1 (Get-AzVirtualNetworkGateway -Name "vpngw16" -ResourceGroupName "rg-day16-vpn") `
  -VirtualNetworkGateway2 (Get-AzVirtualNetworkGateway -Name "vpngw-branch16" -ResourceGroupName "rg-day16-vpn") `
  -ConnectionType "Vnet2Vnet" `
  -SharedKey "Az@Day16_S2S#2025" `
  -EnableBGP:$true | Out-Null

New-AzNetworkSecurityGroup -Name "nsg-app16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" | Out-Null
Add-AzNetworkSecurityRuleConfig -Name "allow-ssh-p2s" -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 `
  -SourceAddressPrefix "172.16.16.0/24" -SourcePortRange "*" -DestinationAddressPrefix "VirtualNetwork" -DestinationPortRange 22 `
  -NetworkSecurityGroup (Get-AzNetworkSecurityGroup -Name "nsg-app16" -ResourceGroupName "rg-day16-vpn") | Set-AzNetworkSecurityGroup
Set-AzVirtualNetworkSubnetConfig -Name "snet-app16" -AddressPrefix "10.16.1.0/24" `
  -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet16weu" -ResourceGroupName "rg-day16-vpn") `
  -NetworkSecurityGroup (Get-AzNetworkSecurityGroup -Name "nsg-app16" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork

New-AzNetworkSecurityGroup -Name "nsg-branch16" -ResourceGroupName "rg-day16-vpn" -Location "westeurope" | Out-Null
Add-AzNetworkSecurityRuleConfig -Name "allow-ssh-p2s" -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority 1000 `
  -SourceAddressPrefix "172.16.16.0/24" -SourcePortRange "*" -DestinationAddressPrefix "VirtualNetwork" -DestinationPortRange 22 `
  -NetworkSecurityGroup (Get-AzNetworkSecurityGroup -Name "nsg-branch16" -ResourceGroupName "rg-day16-vpn") | Set-AzNetworkSecurityGroup
Set-AzVirtualNetworkSubnetConfig -Name "snet-branch16" -AddressPrefix "10.26.1.0/24" `
  -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet-branch16" -ResourceGroupName "rg-day16-vpn") `
  -NetworkSecurityGroup (Get-AzNetworkSecurityGroup -Name "nsg-branch16" -ResourceGroupName "rg-day16-vpn") | Set-AzVirtualNetwork

# Quick BGP checks
Get-AzVirtualNetworkGateway -Name "vpngw16" -ResourceGroupName "rg-day16-vpn" | Get-AzVirtualNetworkGatewayBgpPeerStatus
Get-AzVirtualNetworkGateway -Name "vpngw-branch16" -ResourceGroupName "rg-day16-vpn" | Get-AzVirtualNetworkGatewayBgpPeerStatus
