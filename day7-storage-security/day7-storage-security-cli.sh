#!/usr/bin/env bash 
set -euo pipefail 
# 
# Day7 — Storage Security (Bash + Azure CLI) 
# End-to-end: RG, Storage Account (HTTPS only + TLS 1.2), Network rules, 
# Container via ARM (control plane), RBAC, VNet/Subnet, Private Endpoint, Private DNS, 
# Optional data-plane smoke test (temporary allow), then lock down. 
# 
# Notes: 
# - Replace <YOUR_SUBSCRIPTION_ID> once, below. 
# - This script avoids environment variables on purpose (as requested). 
# - Use globally-unique names for storage accounts if you change defaults. 
# 
# Prereqs: 
# - Azure CLI logged in: az login 
# - Sufficient permissions to create RBAC assignments and networking 
# - 'storage-preview' extension for container-rm 
# 
echo "[1/16] Set subscription context" 
az account set --subscription "4e837a18-8964-4cd7-bcdf-4553a4ce3814" 
echo "[2/16] Create Resource Group (idempotent)" 
az group create --name rg-day7-storage-security-cli --location westeurope 
echo "[3/16] Create secure Storage Account (HTTPS only, TLS1.2, no public blob)" 
az storage account create \ 
--name stday7ehab01cli \ 
--resource-group rg-day7-storage-security-cli \ 
--location westeurope \ 
--sku Standard_LRS \ 
--kind StorageV2 \ 
--https-only true \ 
--min-tls-version TLS1_2 \ 
--allow-blob-public-access false 
echo "[4/16] Lock down public access to Selected networks (deny by default, no bypass)" 
az storage account update \ 
--resource-group rg-day7-storage-security-cli \ 
--name stday7ehab01cli \ 
--default-action Deny \ 
--bypass None 
echo "[5/16] Allow only your current public IPv4 (detected via api.ipify.org)" 
az storage account network-rule add \ 
--resource-group rg-day7-storage-security-cli \ 
--account-name stday7ehab01cli \ 
--ip-address "$(curl -4 -s https://api.ipify.org)" 
echo "[6/16] Ensure storage-preview extension exists for container-rm" 
az extension add --name storage-preview --upgrade 
echo "[7/16] Create a private container via ARM (control plane, unaffected by storage firewall)" 
az storage container-rm create \ 
--name day7-container-cli \ 
--storage-account stday7ehab01cli \ 
--resource-group rg-day7-storage-security-cli \ 
--public-access off 
echo "[8/16] Grant yourself RBAC on the Storage Account for data-plane operations" 
az role assignment create \ 
--assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" \ 
--assignee-principal-type User \ 
--role "Storage Blob Data Contributor" \ 
--scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-day7-storage-security-cli/providers/Microsoft.Storage/storageAccounts/stday7ehab01cli" 
echo "[9/16] Create VNet/Subnet for Private Endpoint" 
az network vnet create \ 
--name vnet-day7-cli \ 
--resource-group rg-day7-storage-security-cli \ 
--location westeurope \ 
--address-prefixes 10.20.0.0/16 \ 
--subnet-name subnet-day7-cli \ 
--subnet-prefixes 10.20.1.0/24 
echo "[10/16] Disable PE network policies on the subnet (required for Private Endpoint)" 
az network vnet subnet update \ 
--name subnet-day7-cli \ 
--vnet-name vnet-day7-cli \ 
--resource-group rg-day7-storage-security-cli \ 
--disable-private-endpoint-network-policies true 
echo "[11/16] Create Private Endpoint targeting 'blob' subresource of the storage account" 
az network private-endpoint create \ 
--name pe-day7-blob-cli \ 
--resource-group rg-day7-storage-security-cli \ 
--location westeurope \ 
--vnet-name vnet-day7-cli \ 
--subnet subnet-day7-cli \ 
--private-connection-resource-id "$(az storage account show -g rg-day7-storage-security-cli -n stday7ehab01cli --query id -o tsv)" \ 
--group-ids blob \ 
--connection-name pe-day7-blob-cli-conn 
echo "[12/16] Create Private DNS zone and link VNet" 
az network private-dns zone create \ 
--resource-group rg-day7-storage-security-cli \ 
--name privatelink.blob.core.windows.net 
az network private-dns link vnet create \ 
--resource-group rg-day7-storage-security-cli \ 
--zone-name privatelink.blob.core.windows.net \ 
--name vnet-day7-cli-link \ 
--virtual-network vnet-day7-cli \ 
--registration-enabled false 
echo "[13/16] Attach DNS zone to the Private Endpoint" 
az network private-endpoint dns-zone-group create \ 
--resource-group rg-day7-storage-security-cli \ 
--endpoint-name pe-day7-blob-cli \ 
--name pe-day7-blob-cli-dzg \ 
--private-dns-zone privatelink.blob.core.windows.net \ 
--zone-name privatelink.blob.core.windows.net 
echo "[14/16] Disable public network access for the storage account (private-only)" 
az storage account update \ 
--resource-group rg-day7-storage-security-cli \ 
--name stday7ehab01cli \ 
--public-network-access Disabled 
echo "[15/16] Optional smoke test: temporarily allow, upload, list, then re-lock" 
# Allow temporarily to perform data-plane tests from your client 
az storage account update \ 
--resource-group rg-day7-storage-security-cli \ 
--name stday7ehab01cli \ 
--default-action Allow 
printf 'day7 storage security test\n' > day7.txt 
az storage blob upload \ 
--account-name stday7ehab01cli \ 
--container-name day7-container-cli \ 
--name day7.txt \ 
--file ./day7.txt \ 
--auth-mode login \ 
--overwrite true 
az storage blob list \ 
--account-name stday7ehab01cli \ 
--container-name day7-container-cli \ 
--auth-mode login \ 
--output table 
# Re-lock and keep only your IPv4 
az storage account update \ 
--resource-group rg-day7-storage-security-cli \ 
--name stday7ehab01cli \ 
--default-action Deny \ 
--bypass None 
az storage account network-rule add \ 
--resource-group rg-day7-storage-security-cli \ 
--account-name stday7ehab01cli \ 
--ip-address "$(curl -4 -s https://api.ipify.org)" 
echo "[16/16] Done. Storage account is private-only with PE + DNS. Container exists and RBAC is in place." 
EOF 
chmod +x ~/azure-administrator-labs/day7-storage-security/day7-storage-security-cli.sh 
# --- PowerShell (Az) --- 
cat > ~/azure-administrator-labs/day7-storage-security/Day7-Storage-Security.ps1 << 'EOF' 
# Day7 — Storage Security (PowerShell + Az modules) 
# RG, Storage Account (HTTPS only + TLS 1.2), Network rules, Container via ARM (control plane), 
# RBAC (data-plane role), VNet/Subnet with PE policies disabled, Private Endpoint + Private DNS. 
# 
# Notes: 
# - Replace <YOUR_SUBSCRIPTION_ID> and <UNIQUE_STORAGE_ACCOUNT_NAME_PS> before running. 
# - This script uses Az.* modules (Install-Module Az -Scope CurrentUser -Repository PSGallery). 
# - Some steps may require Contributor/Owner permissions. 
# [1] Login and set subscription 
Connect-AzAccount 
Set-AzContext -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" 
# [2] Create Resource Group (idempotent) 
New-AzResourceGroup -Name "rg-day7-storage-security-ps" -Location "westeurope" 
# [3] Create secure Storage Account (HTTPS only, TLS1.2, no public blob) 
# Use a globally-unique, lowercase name (3-24 chars). 
$saName = "stehabday7ps01" 
New-AzStorageAccount ` 
-Name $saName ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Location "westeurope" ` 
-SkuName "Standard_LRS" ` 
-Kind "StorageV2" ` 
-EnableHttpsTrafficOnly $true ` 
-MinimumTlsVersion "TLS1_2" ` 
-AllowBlobPublicAccess $false 
# [4] Lock down public access to Selected networks (deny by default, no bypass) and allow your IPv4 
Update-AzStorageAccountNetworkRuleSet ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Name $saName ` 
-DefaultAction Deny ` 
-Bypass None 
$ipv4 = (Invoke-RestMethod -Uri "https://api.ipify.org") 
Add-AzStorageAccountNetworkRule ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Name $saName ` 
-IPAddressOrRange $ipv4 
# [5] Create Blob container via ARM (control plane) to avoid storage firewall issues 
# API version and properties are validated by RP. publicAccess=None => private container. 
New-AzResource ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-ResourceType "Microsoft.Storage/storageAccounts/blobServices/containers" ` 
-Name "$saName/default/day7-container-ps" ` 
-ApiVersion "2023-01-01" ` 
-PropertyObject @{ publicAccess = "None" } ` 
-Force | Out-Null 
# [6] Grant yourself RBAC (Storage Blob Data Contributor) at the container scope 
$ctx = Get-AzContext 
$subId = $ctx.Subscription.Id 
$upn = $ctx.Account.Id # typically user@domain 
$containerScope = "/subscriptions/$subId/resourceGroups/rg-day7-storage-security-ps/providers/Microsoft.Storage/storageAccounts/$saName/blobServices/default/containers/day7-container-ps" 
New-AzRoleAssignment ` 
-SignInName $upn ` 
-RoleDefinitionName "Storage Blob Data Contributor" ` 
-Scope $containerScope 
# [7] Create VNet/Subnet and disable PE network policies 
$vnet = New-AzVirtualNetwork ` 
-Name "vnet-day7-ps" ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Location "westeurope" ` 
-AddressPrefix "10.30.0.0/16" 
$subnet = Add-AzVirtualNetworkSubnetConfig ` 
-Name "subnet-day7-ps" ` 
-AddressPrefix "10.30.1.0/24" ` 
-VirtualNetwork $vnet ` 
-PrivateEndpointNetworkPoliciesFlag "Disabled" 
$null = Set-AzVirtualNetwork -VirtualNetwork $vnet 
# [8] Create Private Endpoint for 'blob' subresource 
$sa = Get-AzStorageAccount -Name $saName -ResourceGroupName "rg-day7-storage-security-ps" 
$peConn = New-AzPrivateLinkServiceConnection ` 
-Name "pe-day7-blob-ps-conn" ` 
-PrivateLinkServiceId $sa.Id ` 
-GroupId "blob" 
New-AzPrivateEndpoint ` 
-Name "pe-day7-blob-ps" ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Location "westeurope" ` 
-Subnet (Get-AzVirtualNetworkSubnetConfig -Name "subnet-day7-ps" -VirtualNetwork (Get-AzVirtualNetwork -Name "vnet-day7-ps" -ResourceGroupName "rg-day7-storage-security-ps")) ` 
-PrivateLinkServiceConnection $peConn | Out-Null 
# [9] Private DNS zone + link + zone group 
$zone = New-AzPrivateDnsZone -Name "privatelink.blob.core.windows.net" -ResourceGroupName "rg-day7-storage-security-ps" 
New-AzPrivateDnsVirtualNetworkLink ` 
-Name "vnet-day7-ps-link" ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-ZoneName $zone.Name ` 
-VirtualNetworkId (Get-AzVirtualNetwork -Name "vnet-day7-ps" -ResourceGroupName "rg-day7-storage-security-ps").Id ` 
-EnableRegistration:$false | Out-Null 
# Attach DNS zone group to the Private Endpoint 
New-AzPrivateDnsZoneGroup ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Name "pe-day7-blob-ps-dzg" ` 
-PrivateEndpointName "pe-day7-blob-ps" ` 
-PrivateDnsZoneConfig @(New-AzPrivateDnsZoneConfig -Name "blobcfg" -PrivateDnsZoneId $zone.Id) | Out-Null 
# [10] Disable public network access for the storage account 
Update-AzStorageAccount ` 
-ResourceGroupName "rg-day7-storage-security-ps" ` 
-Name $saName ` 
-PublicNetworkAccess "Disabled" 
# Done. 
Write-Host "Day7 PowerShell flow completed. Storage account is private-only with PE + DNS; container exists; RBAC set." 
