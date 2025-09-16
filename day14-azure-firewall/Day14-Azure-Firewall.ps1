# =========================================================
# Day14 — Azure Firewall (SNAT + DNAT) — Minimal Az PowerShell
# English comments. Fixed names. Simple flow.
# =========================================================

# Connect if needed:
# Connect-AzAccount

# ---------- Parameters ----------
$rg="rg-day14-firewall"; $loc="westeurope"
$vnet="vnet14weu"
$fw="afw14weu"; $pol="afwpol14"; $pip="pip-afw14"
$law="law14weu"; $rt="rt-backend14"; $nsg="nsg-backend14"; $vm="vm14a"

# ---------- RG ----------
New-AzResourceGroup -Name $rg -Location $loc -ErrorAction Stop | Out-Null

# ---------- VNet + Subnets ----------
$subFirewall = New-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -AddressPrefix "10.14.0.0/26"
$subBackend  = New-AzVirtualNetworkSubnetConfig -Name "snet-backend14"     -AddressPrefix "10.14.1.0/24"
$vnetObj = New-AzVirtualNetwork -Name $vnet -ResourceGroupName $rg -Location $loc -AddressPrefix "10.14.0.0/16" -Subnet $subFirewall,$subBackend

# ---------- Log Analytics ----------
$lawObj = New-AzOperationalInsightsWorkspace -ResourceGroupName $rg -Name $law -Location $loc -Sku "PerGB2018"

# ---------- Public IP ----------
$pipObj = New-AzPublicIpAddress -Name $pip -ResourceGroupName $rg -Location $loc -Sku "Standard" -AllocationMethod "Static" -IpAddressVersion "IPv4"

# ---------- Firewall Policy ----------
$polObj = New-AzFirewallPolicy -Name $pol -ResourceGroupName $rg -Location $loc -ThreatIntelMode "Alert"

# ---------- Azure Firewall in VNet ----------
$fwObj = New-AzFirewall -Name $fw -ResourceGroupName $rg -Location $loc -SkuName "AZFW_VNet" -Tier "Standard" -FirewallPolicy $polObj
$subAFW = Get-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -VirtualNetwork $vnetObj
Add-AzFirewallIpConfiguration -Name "afw-ipconfig" -Firewall $fwObj -PublicIpAddress $pipObj -Subnet $subAFW | Out-Null
Set-AzFirewall -Firewall $fwObj | Out-Null
$fwObj = Get-AzFirewall -Name $fw -ResourceGroupName $rg
$afwPrivIp = $fwObj.IpConfigurations[0].PrivateIPAddress
Write-Output "[Info] FW private IP: $afwPrivIp"

# ---------- Route table + default route ----------
$rtObj = New-AzRouteTable -Name $rt -ResourceGroupName $rg -Location $loc
Add-AzRouteConfig -Name "default-to-afw" -AddressPrefix "0.0.0.0/0" -NextHopType "VirtualAppliance" -NextHopIpAddress $afwPrivIp -RouteTable $rtObj | Out-Null
Set-AzRouteTable -RouteTable $rtObj | Out-Null

# ---------- NSG (temp SSH allow) ----------
$nsgObj = New-AzNetworkSecurityGroup -Name $nsg -ResourceGroupName $rg -Location $loc
Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsgObj -Name "allow-ssh-from-internet-test" -Description "Temporary SSH allow" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix "10.14.1.0/24" -DestinationPortRange 22 | Out-Null
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgObj | Out-Null

# Associate NSG + RT to backend subnet
Set-AzVirtualNetworkSubnetConfig -Name "snet-backend14" -VirtualNetwork $vnetObj -AddressPrefix "10.14.1.0/24" -NetworkSecurityGroup $nsgObj -RouteTable $rtObj | Out-Null
Set-AzVirtualNetwork -VirtualNetwork $vnetObj | Out-Null

# ---------- VM (no Public IP) ----------
$subBackendRef = Get-AzVirtualNetworkSubnetConfig -Name "snet-backend14" -VirtualNetwork $vnetObj
$nicObj = New-AzNetworkInterface -Name ("nic-"+$vm) -ResourceGroupName $rg -Location $loc -SubnetId $subBackendRef.Id
New-AzVM -Name $vm -ResourceGroupName $rg -Location $loc -Size "Standard_B2s" -NetworkInterface $nicObj -Image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" -AuthenticationType "sshPublicKey" -GenerateSshKey | Out-Null
$vmPrivIp = (Get-AzNetworkInterface -Name ("nic-"+$vm) -ResourceGroupName $rg).IpConfigurations[0].PrivateIpAddress
$pipIp   = (Get-AzPublicIpAddress -Name $pip -ResourceGroupName $rg).IpAddress
Write-Output "[Info] VM private IP: $vmPrivIp"
Write-Output "[Info] FW Public IP:  $pipIp"

# ---------- Rule Collection Group + rules ----------
# Network rule: DNS 53 to Internet
$netRule = New-AzFirewallPolicyNetworkRule -Name "dns-any" -SourceAddress "10.14.1.0/24" -DestinationAddress "*" -Protocol "TCP","UDP" -DestinationPort "53"
$netRc   = New-AzFirewallPolicyFilterRuleCollection -Name "rc-allow-dns" -Priority 200 -ActionType Allow -Rule $netRule

# Application rule: HTTP/HTTPS to selected FQDNs
$appRule = New-AzFirewallPolicyApplicationRule -Name "web-allowed" -SourceAddress "10.14.1.0/24" -Protocol "Http","Https" -TargetFqdn "ifconfig.io","aka.ms","microsoft.com","ubuntu.com","github.com"
$appRc   = New-AzFirewallPolicyFilterRuleCollection -Name "rc-allow-web" -Priority 300 -ActionType Allow -Rule $appRule

# DNAT: PIP:22 -> VM:22
$natRule = New-AzFirewallPolicyNatRule -Name "ssh-to-vm14a" -SourceAddress "*" -DestinationAddress $pipIp -DestinationPort "22" -Protocol "TCP" -TranslatedAddress $vmPrivIp -TranslatedPort "22"
$natRc   = New-AzFirewallPolicyNatRuleCollection -Name "rc-dnat-admin" -Priority 100 -ActionType Dnat -Rule $natRule

# Create/Update Rule Collection Group
$rcgName="rcg-main"
if (-not (Get-AzFirewallPolicyRuleCollectionGroup -FirewallPolicy $polObj -Name $rcgName -ErrorAction SilentlyContinue)) {
  New-AzFirewallPolicyRuleCollectionGroup -Name $rcgName -Priority 100 -FirewallPolicy $polObj -RuleCollection $netRc,$appRc,$natRc | Out-Null
} else {
  Set-AzFirewallPolicyRuleCollectionGroup -Name $rcgName -FirewallPolicy $polObj -RuleCollection $netRc,$appRc,$natRc | Out-Null
}

Write-Output "DONE — Day14 Az PowerShell baseline"
