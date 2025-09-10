Param()

$SubscriptionId = "<your_subscription_id>"
$ResourceGroupName = "rg-day9-storage-security"
$LocationName = "westeurope"
$KeyVaultName = "kvday9weu31733"
$KeyName = "cmk-day9"
$StorageAccountName = "stday9secweu31733"
$ContainerName = "enc-test"

# 0) Context
Select-AzSubscription -SubscriptionId $SubscriptionId

# 1) RG
New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName | Out-Null

# 2) Key Vault (RBAC + network)
$kv = New-AzKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroupName -Location $LocationName -EnableRbacAuthorization -PublicNetworkAccess "Enabled"
Update-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -DefaultAction Deny -Bypass AzureServices -EnablePurgeProtection
$myIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip")
Add-AzKeyVaultNetworkRule -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -IpAddressRange "$myIp/32"

# grant current user temp admin on KV
$user = (Get-AzADUser -SignedIn).Id
$kvId = (Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName).ResourceId
New-AzRoleAssignment -ObjectId $user -RoleDefinitionName "Key Vault Administrator" -Scope $kvId | Out-Null

# 3) Key + rotation
Add-AzKeyVaultKey -VaultName $KeyVaultName -Name $KeyName -KeyType "RSA" -KeySize 3072 | Out-Null
$policy = @{
  lifetimeActions = @(
    @{ trigger = @{ timeAfterCreate = "P12M"; timeBeforeExpiry = $null }; action = @{ type = "Rotate" } },
    @{ trigger = @{ timeBeforeExpiry = "P30D" }; action = @{ type = "Notify" } }
  )
  attributes = @{ expiryTime = "P24M" }
} | ConvertTo-Json -Depth 4
Update-AzKeyVaultKeyRotationPolicy -VaultName $KeyVaultName -KeyName $KeyName -Policy $policy | Out-Null

# 4) Storage + identity + firewall
New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -Location $LocationName -SkuName "Standard_LRS" -Kind "StorageV2" -MinimumTlsVersion "TLS1_2" -EnableHttpsTrafficOnly
Update-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -AssignIdentity
Update-AzStorageAccountNetworkRuleSet -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -DefaultAction Deny -Bypass AzureServices
Add-AzStorageAccountNetworkRule -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -IpAddressOrRange $myIp

# 5) Grant storage MI on KV
$saPid = (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Identity.PrincipalId
New-AzRoleAssignment -ObjectId $saPid -RoleDefinitionName "Key Vault Crypto Service Encryption User" -Scope $kvId | Out-Null

# 6) Bind CMK (auto-version)
Update-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -KeyVaultEncryption -KeyName $KeyName -KeyVaultUri "https://$KeyVaultName.vault.azure.net" -KeyVersion ""

# 7) Scopes
New-AzStorageEncryptionScope -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Name "scope-mm" -KeySource MicrosoftStorage
New-AzStorageEncryptionScope -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Name "scope-cmk" -KeySource MicrosoftKeyVault -KeyUri "https://$KeyVaultName.vault.azure.net/keys/$KeyName"

# 8) Container (enforce CMK scope)
$ctx = (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Context
New-AzStorageContainer -Context $ctx -Name $ContainerName -Permission Off -DefaultEncryptionScope "scope-cmk" -DenyEncryptionScopeOverride:$true | Out-Null
