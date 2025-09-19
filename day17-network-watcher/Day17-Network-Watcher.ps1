# =========================================
# Day17 - Network Watcher (PowerShell long-form)
# No variables. No loops. English comments only.
# Region: westeurope
# RGs: NetworkWatcherRG, rg-day17-netwatch
# Resources: cm17, la17weu, sa17flow, vm17a, vm17b, vnet17weu, vnet-branch17
# Requires: Az.Accounts, Az.Network, Az.OperationalInsights, Az.Resources, Az.Storage
# =========================================

# ---[0] Ensure the regional Network Watcher exists
# Purpose: Network Watcher is a regional resource required for Connection Monitor and packet capture.
# If the resource already exists, this command will simply return it.
Get-AzNetworkWatcher -Name "NetworkWatcher_westeurope" -ResourceGroupName "NetworkWatcherRG" -ErrorAction SilentlyContinue `
  | Format-Table -AutoSize
# If nothing returned, create it (idempotent for the region+RG).
New-AzNetworkWatcher -Name "NetworkWatcher_westeurope" -ResourceGroupName "NetworkWatcherRG" -Location "westeurope" `
  -ErrorAction SilentlyContinue `
  | Format-Table -AutoSize

# ---[1] Inventory: confirm scope and core resources exist
# Purpose: Quick visibility that the lab resources are present and in the expected RG/region.
Get-AzResourceGroup -Name "rg-day17-netwatch" | Format-Table -AutoSize
Get-AzVirtualNetwork -Name "vnet17weu" -ResourceGroupName "rg-day17-netwatch" | Format-Table -AutoSize
Get-AzVirtualNetwork -Name "vnet-branch17" -ResourceGroupName "rg-day17-netwatch" | Format-Table -AutoSize
Get-AzVM -Name "vm17a" -ResourceGroupName "rg-day17-netwatch" -Status | Format-Table -AutoSize
Get-AzVM -Name "vm17b" -ResourceGroupName "rg-day17-netwatch" -Status | Format-Table -AutoSize

# ---[2] Connection Monitor v2: show definition
# Purpose: Display current Connection Monitor configuration and state.
Get-AzNetworkWatcherConnectionMonitor -NetworkWatcherName "NetworkWatcher_westeurope" -ResourceGroupName "NetworkWatcherRG" -Name "cm17" `
  | Format-List *

# ---[3] Packet capture to Storage: create -> show -> stop -> delete
# Purpose: Start a short packet capture on vm17a writing into sa17flow. No protocol filters for simplicity.
# Note: TargetVirtualMachineId comes from Get-AzVM. StorageAccountId comes from Get-AzStorageAccount.
New-AzNetworkWatcherPacketCapture `
  -NetworkWatcherName "NetworkWatcher_westeurope" `
  -ResourceGroupName "NetworkWatcherRG" `
  -PacketCaptureName "pc17-vm17a-ps" `
  -TargetVirtualMachineId (Get-AzVM -ResourceGroupName "rg-day17-netwatch" -Name "vm17a").Id `
  -StorageAccountId (Get-AzStorageAccount -ResourceGroupName "rg-day17-netwatch" -Name "sa17flow").Id `
  -TimeLimitInSeconds 120 `
  -BytesToCapturePerPacket 96 `
  | Format-Table -AutoSize

# Show capture status and provisioning state.
Get-AzNetworkWatcherPacketCapture `
  -NetworkWatcherName "NetworkWatcher_westeurope" `
  -ResourceGroupName "NetworkWatcherRG" `
  -PacketCaptureName "pc17-vm17a-ps" `
  | Select-Object Name, ProvisioningState, PacketCaptureStatus, StopReason `
  | Format-Table -AutoSize

# Stop the capture (safe if already stopped). Then remove the capture resource (blob remains in Storage).
Stop-AzNetworkWatcherPacketCapture `
  -NetworkWatcherName "NetworkWatcher_westeurope" `
  -ResourceGroupName "NetworkWatcherRG" `
  -PacketCaptureName "pc17-vm17a-ps"

Remove-AzNetworkWatcherPacketCapture `
  -NetworkWatcherName "NetworkWatcher_westeurope" `
  -ResourceGroupName "NetworkWatcherRG" `
  -PacketCaptureName "pc17-vm17a-ps" `
  -Confirm:$false

# ---[4] Log Analytics KQL queries from PowerShell (no variables; inline workspace lookup)
# Purpose: Validate Virtual Network Flow Logs ingestion and Connection Monitor results via KQL.
# WorkspaceId is obtained inline from the la17weu workspace.
# 4a) Virtual Network Flow Logs (Traffic Analytics), last 1 hour summary
Invoke-AzOperationalInsightsQuery `
  -WorkspaceId (Get-AzOperationalInsightsWorkspace -ResourceGroupName "rg-day17-netwatch" -Name "la17weu").CustomerId `
  -Query "NTANetAnalytics | where TimeGenerated > ago(1h) | summarize flows=count() by FlowDirection, L4Protocol, TargetResourceType | top 20 by flows desc" `
  -Timespan ([System.TimeSpan]::FromHours(1))

# 4b) Connection Monitor results by test group (success/fail/avg RTT) over the last 1 hour
Invoke-AzOperationalInsightsQuery `
  -WorkspaceId (Get-AzOperationalInsightsWorkspace -ResourceGroupName "rg-day17-netwatch" -Name "la17weu").CustomerId `
  -Query "NWConnectionMonitorTestResult | where TimeGenerated > ago(1h) | where ConnectionMonitorResourceId has '/cm17' | summarize Success=countif(TestResult=='Succeeded'), Failed=countif(TestResult=='Failed'), AvgRTTms=avg(AvgRoundTripTimeMs) by TestGroupName, bin(TimeGenerated, 5m) | sort by TimeGenerated desc" `
  -Timespan ([System.TimeSpan]::FromHours(1))
