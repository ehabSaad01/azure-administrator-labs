<#
Day8 – Storage Data Protection (PowerShell)
Goals:
- Secure-by-default Storage Account
- Enable Versioning, Soft Delete (Blobs/Containers), Change Feed
- Create containers: ver-soft, audit-worm-locked
- Apply WORM (time-based, locked)
- Versioning + Soft Delete demo
- Lifecycle policy for cost control
#>

# ---------------------------
# PS-1: Connect and set context
# Why: Ensure actions run in the correct subscription.
# ---------------------------
Connect-AzAccount
Set-AzContext -Subscription "<SUBSCRIPTION_ID>"   # TODO: replace
(Get-AzContext).Subscription | Format-List

# ---------------------------
# PS-2: Create secure Storage Account
# Why: Enforce HTTPS-only, TLS 1.2, and disable anonymous access.
# ---------------------------
$rg  = "rg-day8-storage-protection"
$loc = "westeurope"
$sa  = "stday8dataprotectps"   # change if not globally unique

New-AzStorageAccount `
  -ResourceGroupName $rg `
  -Name $sa `
  -Location $loc `
  -SkuName Standard_LRS `
  -Kind StorageV2 `
  -EnableHttpsTrafficOnly $true `
  -MinimumTlsVersion TLS1_2 `
  -AllowBlobPublicAccess $false | Out-Null

# ---------------------------
# PS-3: Enable Data Protection levers
# Why: Versioning + Soft deletes + Change Feed on the blob service.
# ---------------------------

# PS-3.1: Versioning
Update-AzStorageBlobServiceProperty -ResourceGroupName $rg -StorageAccountName $sa -IsVersioningEnabled $true | Out-Null
(Get-AzStorageBlobServiceProperty -ResourceGroupName $rg -AccountName $sa).IsVersioningEnabled

# PS-3.2: Blob Soft Delete (7 days)
Enable-AzStorageBlobDeleteRetentionPolicy -ResourceGroupName $rg -AccountName $sa -RetentionDays 7 -PassThru

# PS-3.3: Container Soft Delete (7 days)
Enable-AzStorageContainerDeleteRetentionPolicy -ResourceGroupName $rg -AccountName $sa -RetentionDays 7 -PassThru

# PS-3.4: Change Feed
Update-AzStorageBlobServiceProperty -ResourceGroupName $rg -StorageAccountName $sa -EnableChangeFeed $true | Out-Null
(Get-AzStorageBlobServiceProperty -ResourceGroupName $rg -AccountName $sa).ChangeFeed

# ---------------------------
# PS-4: Create containers
# Why: Separate scenarios for versioning/soft-delete vs WORM compliance.
# ---------------------------
New-AzRmStorageContainer -ResourceGroupName $rg -AccountName $sa -Name "ver-soft" | Out-Null
New-AzRmStorageContainer -ResourceGroupName $rg -AccountName $sa -Name "audit-worm-locked" | Out-Null

# ---------------------------
# PS-5: WORM (immutability) on audit-worm-locked
# Why: Time-based retention for 1 day, then lock (WORM).
# ---------------------------
Set-AzRmStorageContainerImmutabilityPolicy `
  -ResourceGroupName $rg `
  -StorageAccountName $sa `
  -ContainerName "audit-worm-locked" `
  -ImmutabilityPeriod 1 `
  -AllowProtectedAppendWrite $false | Out-Null

(Get-AzRmStorageContainerImmutabilityPolicy -ResourceGroupName $rg -AccountName $sa -ContainerName "audit-worm-locked") |
  Lock-AzRmStorageContainerImmutabilityPolicy -Force
Get-AzRmStorageContainerImmutabilityPolicy -ResourceGroupName $rg -AccountName $sa -ContainerName "audit-worm-locked"

# ---------------------------
# PS-6: Versioning + Soft Delete demo (on ver-soft)
# Why: Show overwrites create versions; soft delete is reversible.
# ---------------------------
$ctx = New-AzStorageContext -StorageAccountName $sa -UseConnectedAccount

"Retention=7; Policy=v1" | Set-Content -Path ".\policy-v1.txt" -Encoding UTF8
Set-AzStorageBlobContent -File ".\policy-v1.txt" -Container "ver-soft" -Blob "policy.txt" -Context $ctx -Force | Out-Null

"Retention=7; Policy=v2 - changed" | Set-Content -Path ".\policy-v2.txt" -Encoding UTF8
Set-AzStorageBlobContent -File ".\policy-v2.txt" -Container "ver-soft" -Blob "policy.txt" -Context $ctx -Force | Out-Null

Get-AzStorageBlob -Container "ver-soft" -Context $ctx -IncludeVersion |
  Where-Object { $_.Name -eq "policy.txt" } |
  Select-Object Name, VersionId, IsLatest, LastModified

Remove-AzStorageBlob -Container "ver-soft" -Blob "policy.txt" -Context $ctx -Force
Restore-AzStorageBlob -Container "ver-soft" -Blob "policy.txt" -Context $ctx

# ---------------------------
# PS-7: Lifecycle policy
# Why: Control cost by tiering base blobs and deleting old versions.
# ---------------------------
$policy = @{
  Rules = @(
    @{
      Enabled = $true
      Name = "ver-soft-lifecycle"
      Type = "Lifecycle"
      Definition = @{
        Filters = @{
          BlobTypes   = @("blockBlob")
          PrefixMatch = @("ver-soft/")
        }
        Actions = @{
          BaseBlob = @{
            TierToCool    = @{ DaysAfterModificationGreaterThan = 30 }
            TierToArchive = @{ DaysAfterModificationGreaterThan = 90 }
          }
          Version = @{
            Delete = @{ DaysAfterCreationGreaterThan = 30 }
          }
        }
      }
    }
  )
}
Set-AzStorageAccountManagementPolicy -ResourceGroupName $rg -AccountName $sa -Policy $policy | Out-Null
(Get-AzStorageAccountManagementPolicy -ResourceGroupName $rg -AccountName $sa).Policy
