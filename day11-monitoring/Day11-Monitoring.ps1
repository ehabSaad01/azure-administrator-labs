# ===============================
# Day11 Monitoring — PowerShell
# Az module, idempotent where possible
# ===============================
$ErrorActionPreference = 'Stop'

# -------- Variables --------
$Subscription = $env:SUBSCRIPTION; if ([string]::IsNullOrWhiteSpace($Subscription)) { $Subscription = "<your_subscription_id>" }
$Rg   = ${env:RG};  if ([string]::IsNullOrWhiteSpace($Rg)) { $Rg = "rg-day11-monitor" }
$Loc  = ${env:LOC}; if ([string]::IsNullOrWhiteSpace($Loc)) { $Loc = "westeurope" }
$La   = ${env:LA};  if ([string]::IsNullOrWhiteSpace($La)) { $La = "la11weu" }
$Ag   = ${env:AG};  if ([string]::IsNullOrWhiteSpace($Ag)) { $Ag = "ag11weu" }
$Email = ${env:EMAIL}; if ([string]::IsNullOrWhiteSpace($Email)) { $Email = "<your_email@example.com>" }
$VmId = ${env:VM_ID}  # optional

# -------- Context --------
Select-AzSubscription -SubscriptionId $Subscription | Out-Null

# -------- Resource Group --------
New-AzResourceGroup -Name $Rg -Location $Loc -Force | Out-Null

# -------- Log Analytics Workspace --------
$laObj = Get-AzOperationalInsightsWorkspace -ResourceGroupName $Rg -Name $La -ErrorAction SilentlyContinue
if (-not $laObj) {
    $laObj = New-AzOperationalInsightsWorkspace -ResourceGroupName $Rg -Name $La -Location $Loc -Sku "PerGB2018"
}
Set-AzOperationalInsightsWorkspace -ResourceGroupName $Rg -Name $La -RetentionInDays 30 | Out-Null
$laObj = Get-AzOperationalInsightsWorkspace -ResourceGroupName $Rg -Name $La
$LaId  = $laObj.ResourceId
Write-Host "LA_ID = $LaId"

# -------- Action Group (Email) --------
$recv = New-AzActionGroupReceiver -Name "Primary" -EmailReceiver $Email -UseCommonAlertSchema
$agObj = Get-AzActionGroup -ResourceGroupName $Rg -Name $Ag -ErrorAction SilentlyContinue
if (-not $agObj) {
    $agObj = New-AzActionGroup -ResourceGroupName $Rg -Name $Ag -ShortName $Ag -Receiver $recv
} else {
    Set-AzActionGroup -ResourceGroupName $Rg -Name $Ag -ShortName $Ag -Receiver $recv | Out-Null
}
$AgId = (Get-AzActionGroup -ResourceGroupName $Rg -Name $Ag).Id
Write-Host "AG_ID = $AgId"

# -------- Subscription-level Diagnostic Settings
$subId    = (Get-AzContext).Subscription.Id
$subScope = "/subscriptions/$subId"
$categories = @('Administrative','Policy','Security','ServiceHealth','ResourceHealth','Autoscale','Recommendation')

Set-AzDiagnosticSetting `
    -Name ("ds-activity-to-{0}" -f $La) `
    -ResourceId $subScope `
    -WorkspaceResourceId $LaId `
    -Category $categories `
    -Enabled $true | Out-Null

# -------- Metric Alert: VM CPU > 75 (optional)
if ($VmId) {
    New-AzMetricAlertRuleV2 `
        -Name "vm-cpu-gt75m5" `
        -ResourceGroupName $Rg `
        -Severity 3 `
        -WindowSize (New-TimeSpan -Minutes 5) `
        -Frequency (New-TimeSpan -Minutes 5) `
        -TargetResourceId $VmId `
        -Condition 'avg Percentage CPU > 75' `
        -ActionGroupId $AgId `
        -Enabled
} else {
    Write-Warning "Skipping CPU metric alert. Provide VM_ID env var."
}

# -------- Activity Log Alert: RG delete
$cond = New-AzActivityLogAlertCondition -Field "operationName" -Equal "Microsoft.Resources/subscriptions/resourceGroups/delete"
$alr = Get-AzActivityLogAlert -ResourceGroupName $Rg -Name "activity-rg-delete" -ErrorAction SilentlyContinue
if (-not $alr) {
    New-AzActivityLogAlert -Name "activity-rg-delete" -ResourceGroupName $Rg -Scope $subScope -Condition $cond -ActionGroupId $AgId | Out-Null
} else {
    Set-AzActivityLogAlert -Name "activity-rg-delete" -ResourceGroupName $Rg -Scope $subScope -Condition $cond -ActionGroupId $AgId | Out-Null
}

# -------- Scheduled Query Alert: Heartbeat missing
$Query = @"
Heartbeat
| summarize LastBeat = max(TimeGenerated) by Computer
| where LastBeat < ago(10m)
"@
$src  = New-AzScheduledQueryRuleSource -Query $Query -DataSourceId $LaId -QueryType ResultCount
$sch  = New-AzScheduledQueryRuleSchedule -FrequencyInMinutes 5 -TimeWindowInMinutes 10
$act  = New-AzScheduledQueryRuleAznsActionGroup -ActionGroup $AgId -EmailSubject "Heartbeat missing >10m"

$rule = Get-AzScheduledQueryRule -ResourceGroupName $Rg -Name "log-hb-missing-10m" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-AzScheduledQueryRule -ResourceGroupName $Rg -Location $Loc -Name "log-hb-missing-10m" -Description "Heartbeat missing >10m" -Severity 3 -Enabled -Action $act -Schedule $sch -Source $src | Out-Null
} else {
    Set-AzScheduledQueryRule -ResourceGroupName $Rg -Name "log-hb-missing-10m" -Description "Heartbeat missing >10m" -Severity 3 -Enabled -Action $act -Schedule $sch -Source $src | Out-Null
}

Write-Host "Done."
