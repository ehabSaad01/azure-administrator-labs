Param(
  [string]$Location            = "germanywestcentral",
  [string]$RgName              = "RG-Networking-Lab-cli",
  [string]$VNetName            = "vnet-lab-cli",
  [string]$VNetCidr            = "10.30.0.0/16",
  [string]$SnWeb               = "snet-web-cli",
  [string]$SnWebCidr           = "10.30.1.0/24",
  [string]$SnApp               = "snet-app-cli",
  [string]$SnAppCidr           = "10.30.2.0/24",
  [string]$SnDb                = "snet-db-cli",
  [string]$SnDbCidr            = "10.30.3.0/24",
  [string]$SnBastion           = "AzureBastionSubnet",
  [string]$SnBastionCidr       = "10.30.10.0/26",
  [string]$NsgWeb              = "nsg-web-cli",
  [string]$NsgApp              = "nsg-app-cli",
  [string]$NsgDb               = "nsg-db-cli",
  [string]$PipWeb              = "pip-web-cli",
  [string]$NicWeb              = "nic-web-cli",
  [string]$VmWeb               = "vm-web-cli",
  [string]$VmSize              = "Standard_D2as_v5",
  [string]$VmZone              = "2",
  [string]$CloudInitPath       = "../cli/cloud-init-nginx.yaml",
  [string]$SshPublicKeyPath    = "$HOME/.ssh/id_rsa.pub"
)

# Make sure Az module is installed and authenticated:
# Install-Module Az -Scope CurrentUser
# Connect-AzAccount

New-AzResourceGroup -Name $RgName -Location $Location | Out-Null

$snWebCfg = New-AzVirtualNetworkSubnetConfig -Name $SnWeb -AddressPrefix $SnWebCidr
$vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RgName -Location $Location `
  -AddressPrefix $VNetCidr -Subnet $snWebCfg

Add-AzVirtualNetworkSubnetConfig -Name $SnApp -AddressPrefix $SnAppCidr -VirtualNetwork $vnet | Out-Null
Add-AzVirtualNetworkSubnetConfig -Name $SnDb  -AddressPrefix $SnDbCidr  -VirtualNetwork $vnet | Out-Null
Add-AzVirtualNetworkSubnetConfig -Name $SnBastion -AddressPrefix $SnBastionCidr -VirtualNetwork $vnet | Out-Null
$vnet | Set-AzVirtualNetwork | Out-Null

$nsgWeb = New-AzNetworkSecurityGroup -Name $NsgWeb -ResourceGroupName $RgName -Location $Location
$nsgApp = New-AzNetworkSecurityGroup -Name $NsgApp -ResourceGroupName $RgName -Location $Location
$nsgDb  = New-AzNetworkSecurityGroup -Name $NsgDb  -ResourceGroupName $RgName -Location $Location

# Add inbound rules for HTTP and HTTPS
$ruleHttp = New-AzNetworkSecurityRuleConfig -Name "allow-http" -Direction Inbound -Access Allow -Protocol Tcp -Priority 1000 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
$ruleHttps = New-AzNetworkSecurityRuleConfig -Name "allow-https" -Direction Inbound -Access Allow -Protocol Tcp -Priority 1010 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443
$nsgWeb.SecurityRules += $ruleHttp
$nsgWeb.SecurityRules += $ruleHttps
$nsgWeb | Set-AzNetworkSecurityGroup | Out-Null

# Attach NSGs to subnets
Set-AzVirtualNetworkSubnetConfig -Name $SnWeb -VirtualNetwork $vnet -AddressPrefix $SnWebCidr -NetworkSecurityGroup $nsgWeb | Out-Null
Set-AzVirtualNetworkSubnetConfig -Name $SnApp -VirtualNetwork $vnet -AddressPrefix $SnAppCidr -NetworkSecurityGroup $nsgApp | Out-Null
Set-AzVirtualNetworkSubnetConfig -Name $SnDb  -VirtualNetwork $vnet -AddressPrefix $SnDbCidr  -NetworkSecurityGroup $nsgDb  | Out-Null
$vnet | Set-AzVirtualNetwork | Out-Null

$pip = New-AzPublicIpAddress -Name $PipWeb -ResourceGroupName $RgName -Location $Location -AllocationMethod Static -Sku Standard

$snWeb = Get-AzVirtualNetworkSubnetConfig -Name $SnWeb -VirtualNetwork $vnet
$nic = New-AzNetworkInterface -Name $NicWeb -ResourceGroupName $RgName -Location $Location -Subnet $snWeb -PublicIpAddress $pip

# Configure Ubuntu 22.04 VM with cloud-init to install Nginx
$vmConfig = New-AzVMConfig -VMName $VmWeb -VMSize $VmSize -Zone $VmZone
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VmWeb -DisablePasswordAuthentication
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -Publis
