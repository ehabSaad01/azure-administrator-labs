# Requires Az modules
# Day10 — Identity & Governance (PowerShell)
# Comments are in English

param(
  [Parameter(Mandatory = $true)] [string] $SubscriptionId,
  [string] $Location = "westeurope",
  [string] $Suffix = (Get-Date -Format "yyyyMMddHHmm")
)

# ---------- Variables ----------
$Rg   = "rg-day10-iam-gov"
$Vnet = "vnetday10weu"
$SnetPe = "snet-pe"
$SnetVm = "snet-vm"
$Kv   = "kvday10weu$Suffix"
$Sa   = "saday10weu$Suffix"
$Vm   = "vmday10weu"
$La   = "laday10weu$Suffix"
$Tags = @{ env = "lab"; owner = "day10" }

# ---------- Context ----------
# Select subscription
Select-AzSubscription -SubscriptionId $SubscriptionId  # select context

# ---------- Resource Group ----------
# Create RG with tags
$rgObj = New-AzResourceGroup -Name $Rg -Location $Location -Tag $Tags -Force

# ---------- Policy Assignments ----------
# Allowed locations
$allowed = Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Allowed locations"} | Select-Object -First 1
New-AzPolicyAssignment -Name "pa-day10-allowed-locs" -Scope $rgObj.ResourceId -PolicyDefinition $allowed -PolicyParameterObject @{ listOfAllowedLocations = @($Location) }

# Require tags
$require = Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq "Require a tag and its value on resources"} | Select-Object -First 1
New-AzPolicyAssignment -Name "pa-day10-require-tag-env"   -Scope $rgObj.ResourceId -PolicyDefinition $require -PolicyParameterObject @{ tagName = "env";   tagValue = "lab" }
New-AzPolicyAssignment -Name "pa-day10-require-tag-owner" -Scope $rgObj.ResourceId -PolicyDefinition $require -PolicyParameterObject @{ tagName = "owner"; tagValue = "day10" }

# ---------- Networking ----------
# VNet and subnets
$vnet = New-AzVirtualNetwork -Name $Vnet -ResourceGroupName $Rg -Location $Location -AddressPrefix "10.20.0.0/16" -Tag $Tags
$vnet | Add-AzVirtualNetworkSubnetConfig -Name $SnetPe -AddressPrefix "10.20.0.0/24" | Set-AzVirtualNetwork | Out-Null
$v = Get-AzVirtualNetwork -Name $Vnet -ResourceGroupName $Rg
$v | Add-AzVirtualNetworkSubnetConfig -Name $SnetVm -AddressPrefix "10.20.1.0/24" | Set-AzVirtualNetwork | Out-Null

# Private DNS zones
$kvZone   = "privatelink.vaultcore.azure.net"
$blobZone = "privatelink.blob.core.windows.net"
$z1 = New-AzPrivateDnsZone -ResourceGroupName $Rg -Name $kvZone
$z2 = New-AzPrivateDnsZone -ResourceGroupName $Rg -Name $blobZone
New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $Rg -ZoneName $kvZone  -Name "link-kv-zone"   -VirtualNetworkId $v.Id -EnableRegistration:$false | Out-Null
New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $Rg -ZoneName $blobZone -Name "link-blob-zone" -VirtualNetworkId $v.Id -EnableRegistration:$false | Out-Null

# ---------- Key Vault ----------
# RBAC only + purge protection + public access disabled
$kv = New-AzKeyVault -Name $Kv -ResourceGroupName $Rg -Location $Location -Sku Standard -EnablePurgeProtection -EnableRbacAuthorization -PublicNetworkAccess "Disabled" -Tag $Tags

# ---------- Storage ----------
# Keyless + TLS1.2 + public access disabled
$sa = New-AzStorageAccount -Name $Sa -ResourceGroupName $Rg -Location $Location -SkuName Standard_LRS -Kind StorageV2 `
       -AllowBlobPublicAccess:$false -AllowSharedKeyAccess:$false -MinimumTlsVersion TLS1_2 -PublicNetworkAccess "Disabled" -EnableHttpsTrafficOnly -Tag $Tags

# ---------- Private Endpoints ----------
# KV PE
$peKv = New-AzPrivateEndpoint -Name "pe-kv-day10" -ResourceGroupName $Rg -Location $Location `
          -Subnet (Get-AzVirtualNetworkSubnetConfig -Name $SnetPe -VirtualNetwork $v) `
          -PrivateLinkServiceConnection @( New-AzPrivateLinkServiceConnection -Name "pec-kv-day10" -PrivateLinkServiceId $kv.ResourceId -GroupId "vault" )
Add-AzPrivateDnsZoneGroup -Name "zg-kv" -ResourceGroupName $Rg -PrivateEndpointName "pe-kv-day10" `
          -PrivateDnsZoneConfig @( New-AzPrivateDnsZoneConfig -Name "cfg1" -PrivateDnsZoneId $z1.Id ) | Out-Null

# SA PE for blob
$peSa = New-AzPrivateEndpoint -Name "pe-sa-day10" -ResourceGroupName $Rg -Location $Location `
          -Subnet (Get-AzVirtualNetworkSubnetConfig -Name $SnetPe -VirtualNetwork $v) `
          -PrivateLinkServiceConnection @( New-AzPrivateLinkServiceConnection -Name "pec-sa-day10" -PrivateLinkServiceId $sa.Id -GroupId "blob" )
Add-AzPrivateDnsZoneGroup -Name "zg-sa" -ResourceGroupName $Rg -PrivateEndpointName "pe-sa-day10" `
          -PrivateDnsZoneConfig @( New-AzPrivateDnsZoneConfig -Name "cfg1" -PrivateDnsZoneId $z2.Id ) | Out-Null

# ---------- VM ----------
# Linux VM without Public IP and with System-assigned MI
$nic = New-AzNetworkInterface -Name "$Vm-nic" -ResourceGroupName $Rg -Location $Location -SubnetId (Get-AzVirtualNetworkSubnetConfig -Name $SnetVm -VirtualNetwork $v).Id
$vmCfg = New-AzVMConfig -VMName $Vm -VMSize "Standard_B2s" | Set-AzVMOperatingSystem -Linux -ComputerName $Vm -DisablePasswordAuthentication -ProvisionVMAgent
$vmCfg = Set-AzVMSourceImage -VM $vmCfg -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts" -Version "latest"
$vmCfg | Add-AzVMNetworkInterface -Id $nic.Id | Out-Null
$vm = New-AzVM -ResourceGroupName $Rg -Location $Location -VM $vmCfg -GenerateSshKeys
$vm2 = Set-AzVM -ResourceGroupName $Rg -Name $Vm -AssignIdentity

# ---------- RBAC ----------
$spId = (Get-AzVM -Name $Vm -ResourceGroupName $Rg).Identity.PrincipalId
New-AzRoleAssignment -ObjectId $spId -RoleDefinitionName "Key Vault Secrets User" -Scope $kv.ResourceId | Out-Null
New-AzRoleAssignment -ObjectId $spId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $sa.Id | Out-Null

# ---------- Log Analytics ----------
$la = New-AzOperationalInsightsWorkspace -ResourceGroupName $Rg -Name $La -Location $Location -Sku "PerGB2018" -Tag $Tags

# ---------- Diagnostics ----------
$kvCats = (Get-AzDiagnosticSettingCategory -ResourceId $kv.ResourceId | Where-Object {$_.CategoryType -eq "Logs"}).Name
Set-AzDiagnosticSetting -Name "diag-kv-day10" -ResourceId $kv.ResourceId -WorkspaceId $la.ResourceId -Enabled $true -Category $kvCats | Out-Null
$saCats = (Get-AzDiagnosticSettingCategory -ResourceId $sa.Id | Where-Object {$_.CategoryType -eq "Logs"}).Name
Set-AzDiagnosticSetting -Name "diag-sa-day10" -ResourceId $sa.Id -WorkspaceId $la.ResourceId -Enabled $true -Category $saCats | Out-Null

Write-Host "Done. KV=$Kv SA=$Sa LA=$La" -ForegroundColor Green
