# Day15 — Azure Bastion secure admin path (no Public IP on VMs)
# PowerShell Az module. English comments only.

param(
  [string]$Subscription = "<your_subscription_id>",
  [string]$Location = "westeurope"
)

$RG   = "rg-day15-bastion"
$VNet = "vnet15weu";        $VNetCidr = "10.15.0.0/16"
$SApp = "snet-app15";       $SAppCidr = "10.15.1.0/24"
$SBas = "AzureBastionSubnet";$SBasCidr = "10.15.0.0/26"
$NSG  = "nsg-app15"
$Pip  = "pip-bast15weu"
$Bast = "bast15weu"
$VM   = "vm15a"
$Tags = @{ env="lab"; day="15"; owner="ehab" }

Set-AzContext -Subscription $Subscription | Out-Null

New-AzResourceGroup -Name $RG -Location $Location -Tag $Tags -Force | Out-Null

$vnet = New-AzVirtualNetwork -Name $VNet -ResourceGroupName $RG -Location $Location -AddressPrefix $VNetCidr
$vnet = Add-AzVirtualNetworkSubnetConfig -Name $SApp -AddressPrefix $SAppCidr -VirtualNetwork $vnet
$vnet = Add-AzVirtualNetworkSubnetConfig -Name $SBas -AddressPrefix $SBasCidr -VirtualNetwork $vnet
$vnet | Set-AzVirtualNetwork | Out-Null

$allow = New-AzNetworkSecurityRuleConfig -Name "allow-ssh-from-bastion" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
  -SourceAddressPrefix $SBasCidr -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
$deny  = New-AzNetworkSecurityRuleConfig -Name "deny-vnet-inbound" -Access Deny -Protocol * -Direction Inbound -Priority 200 `
  -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *
$nsg = New-AzNetworkSecurityGroup -Name $NSG -ResourceGroupName $RG -Location $Location -SecurityRules $allow,$deny -Tag $Tags

$subApp = Get-AzVirtualNetworkSubnetConfig -Name $SApp -VirtualNetwork $vnet
$null = Set-AzVirtualNetworkSubnetConfig -Name $SApp -VirtualNetwork $vnet -AddressPrefix $SAppCidr -NetworkSecurityGroup $nsg
$vnet | Set-AzVirtualNetwork | Out-Null

$pip = New-AzPublicIpAddress -Name $Pip -ResourceGroupName $RG -Location $Location -AllocationMethod Static -Sku Standard -Tag $Tags

New-AzBastion -Name $Bast -ResourceGroupName $RG -PublicIpAddress $pip -VirtualNetwork $vnet -Location $Location -Sku Basic -AsJob | Out-Null

$sshPub = Get-Content -Raw -Path "$HOME/.ssh/id_rsa.pub"
$nic = New-AzNetworkInterface -Name "nic-$VM" -ResourceGroupName $RG -Location $Location -SubnetId (Get-AzVirtualNetworkSubnetConfig -Name $SApp -VirtualNetwork $vnet).Id

$vm = New-AzVMConfig -VMName $VM -VMSize "Standard_B1s" |
  Set-AzVMOperatingSystem -Linux -ComputerName $VM -DisablePasswordAuthentication |
  Add-AzVMSshPublicKey -KeyData $sshPub -Path "/home/azureuser/.ssh/authorized_keys" |
  Add-AzVMNetworkInterface -Id $nic.Id |
  Set-AzVMSourceImage -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest" |
  Set-AzVMOSDisk -CreateOption FromImage

$vm = Set-AzVMIdentity -VM $vm -Type SystemAssigned
New-AzVM -ResourceGroupName $RG -Location $Location -VM $vm | Out-Null

Write-Host "Done Day15. VM without Public IP. Bastion ready."
