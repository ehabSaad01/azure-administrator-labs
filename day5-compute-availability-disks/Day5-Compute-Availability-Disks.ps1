# Requires: Az PowerShell module
# Connect-AzAccount before running
# Set the subscription context
$Subscription = "<your_subscription_id>"
$ResourceGroupName = "rg-day5-compute"
$Location = "westeurope"
$VmNameA = "vm5-a"
$VmNameB = "vm5-b"
$DataDiskA = "data5-a"
$SnapshotA = "snap-data5-a"
$RestoreDiskB = "data5-restored-zone2"

Select-AzSubscription -SubscriptionId $Subscription

# 1) Create data disk and attach to VM A
$diskConfig = New-AzDiskConfig -Location $Location -SkuName "Premium_LRS" -CreateOption Empty -DiskSizeGB 64
$disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDiskA -Disk $diskConfig

$vmA = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmNameA
$vmA = Add-AzVMDataDisk -VM $vmA -Name $DataDiskA -CreateOption Attach -ManagedDiskId $disk.Id -Lun 1 -Caching None
Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vmA

# 2) Resize data disk to 128 GiB
$diskUpdate = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDiskA
$diskUpdate.DiskSizeGB = 128
Update-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDiskA -Disk $diskUpdate

# 3) Snapshot of data disk
$sourceDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDiskA
$snapConfig = New-AzSnapshotConfig -Location $Location -CreateOption Copy -SourceResourceId $sourceDisk.Id
$snapshot = New-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $SnapshotA -Snapshot $snapConfig

# 4) Create disk from snapshot in Zone 2 and attach to VM B
$diskFromSnapConfig = New-AzDiskConfig -Location $Location -CreateOption Copy -SourceResourceId $snapshot.Id -SkuName "Premium_LRS" -Zone "2"
$restoreDisk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $RestoreDiskB -Disk $diskFromSnapConfig

$vmB = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmNameB
$vmB = Add-AzVMDataDisk -VM $vmB -Name $RestoreDiskB -CreateOption Attach -ManagedDiskId $restoreDisk.Id -Lun 2 -Caching None
Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vmB
