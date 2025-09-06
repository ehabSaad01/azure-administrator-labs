param(
  [string]$SubscriptionId = "<your_subscription_id>",
  [string]$ResourceGroup  = "rg-day6-storage",
  [string]$Location       = "westeurope",
  [string]$St1            = "stday6weu01ehab",
  [string]$St2            = "stday6weu02ehab",
  [string]$ContainerName  = "cn-app",
  [string]$DlFileSystem   = "fs-raw",
  [string]$FileShareName  = "fs-app",
  [string]$QueueName      = "q-app",
  [string]$TableName      = "appdata"
)

# Modules assumed in Cloud Shell: Az.Accounts, Az.Resources, Az.Storage
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null

# RG
New-AzResourceGroup -Name $ResourceGroup -Location $Location -ErrorAction SilentlyContinue | Out-Null

# Accounts
$common = @{
  ResourceGroupName = $ResourceGroup
  Location          = $Location
  Kind              = "StorageV2"
  SkuName           = "Standard_ZRS"
  EnableHttpsTrafficOnly = $true
  MinimumTlsVersion      = "TLS1_2"
  AllowBlobPublicAccess  = $false
  AllowSharedKeyAccess   = $true
  Tags = @{ project="az104-day6"; owner="ehab"; env="lab" }
}

New-AzStorageAccount @common -Name $St1 | Out-Null
New-AzStorageAccount @common -Name $St2 -EnableHierarchicalNamespace $true | Out-Null

# Keys + Contexts
$key1 = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $St1)[0].Value
$key2 = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $St2)[0].Value
$ctx1 = New-AzStorageContext -StorageAccountName $St1 -StorageAccountKey $key1
$ctx2 = New-AzStorageContext -StorageAccountName $St2 -StorageAccountKey $key2

# Data plane
New-AzStorageContainer -Name $ContainerName -Context $ctx1 -Permission Off -ErrorAction SilentlyContinue | Out-Null
New-AzDataLakeGen2FileSystem -Name $DlFileSystem -Context $ctx2 -ErrorAction SilentlyContinue | Out-Null
New-AzStorageShare -Name $FileShareName -Context $ctx1 -ErrorAction SilentlyContinue | Out-Null
New-AzStorageQueue -Name $QueueName -Context $ctx1 -ErrorAction SilentlyContinue | Out-Null
New-AzStorageTable -Name $TableName -Context $ctx1 -ErrorAction SilentlyContinue | Out-Null

# Table demo entity via Azure CLI to avoid extra modules
if (Get-Command az -ErrorAction SilentlyContinue) {
  & az storage entity insert --account-name $St1 --account-key $key1 `
    --table-name $TableName `
    --entity "PartitionKey=app" "RowKey=v1" "env=lab" "enabled=true" | Out-Null
}

# Protection via Azure CLI (more reliable across Az versions)
foreach ($acc in @($St1,$St2)) {
  & az storage account blob-service-properties update `
    -g $ResourceGroup -n $acc `
    --enable-versioning true `
    --enable-change-feed true `
    --enable-delete-retention true --delete-retention-days 7 `
    --enable-container-delete-retention true --container-delete-retention-days 7 `
    --enable-restore-policy true --restore-days 7 | Out-Null
}

& az storage account file-service-properties update `
  -g $ResourceGroup -n $St1 `
  --enable-delete-retention true --delete-retention-days 7 | Out-Null

# Lifecycle policies
$lcp1 = @'
{
  "rules":[{"name":"lc-cn-app","enabled":true,"type":"Lifecycle",
  "definition":{"filters":{"blobTypes":["blockBlob"],"prefixMatch":["cn-app/"]},
  "actions":{"baseBlob":{"tierToCool":{"daysAfterModificationGreaterThan":30},
                         "tierToArchive":{"daysAfterModificationGreaterThan":90},
                         "delete":{"daysAfterModificationGreaterThan":365}},
             "snapshot":{"delete":{"daysAfterCreationGreaterThan":30}},
             "version":{"delete":{"daysAfterCreationGreaterThan":30}}}}}]
}
'@
$lcp2 = @'
{
  "rules":[{"name":"lc-fs-raw","enabled":true,"type":"Lifecycle",
  "definition":{"filters":{"blobTypes":["blockBlob"],"prefixMatch":["fs-raw/"]},
  "actions":{"baseBlob":{"tierToCool":{"daysAfterModificationGreaterThan":14},
                         "tierToArchive":{"daysAfterModificationGreaterThan":60},
                         "delete":{"daysAfterModificationGreaterThan":365}},
             "snapshot":{"delete":{"daysAfterCreationGreaterThan":30}},
             "version":{"delete":{"daysAfterCreationGreaterThan":30}}}}}]
}
'@

$lcp1Path = Join-Path $env:TEMP "lc-st1.json"
$lcp2Path = Join-Path $env:TEMP "lc-st2.json"
$lcp1 | Set-Content -Path $lcp1Path -Encoding UTF8
$lcp2 | Set-Content -Path $lcp2Path -Encoding UTF8

& az storage account management-policy create -g $ResourceGroup -n $St1 --policy @$lcp1Path | Out-Null
& az storage account management-policy create -g $ResourceGroup -n $St2 --policy @$lcp2Path | Out-Null

# Output
Write-Host "Done. Primary endpoints:"
& az storage account show -g $ResourceGroup -n $St1 --query primaryEndpoints -o json
& az storage account show -g $ResourceGroup -n $St2 --query primaryEndpoints -o json
