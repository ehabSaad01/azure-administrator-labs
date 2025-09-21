# File: Day18-Application-Gateway-WAF.ps1
# Purpose: Attach regional WAF policy (Prevention), add /healthz probe, HTTP settings, listener, rule, and diagnostics.
# Style: Long parameters. English comments. Secure-by-default.

# 0) Subscription context — replace before running
Select-AzSubscription -SubscriptionId "<your_subscription_id>"

# 1) Handles
$ResourceGroupName = "rg-day18-agw"
$GatewayName       = "agw18weu"
$WorkspaceName     = "la18weu"
$StorageName       = "sa18logs<unique>"

# 2) Ensure regional WAF policy exists and set to Prevention
New-AzApplicationGatewayFirewallPolicy `
  -Name "waf18weu" `
  -ResourceGroupName $ResourceGroupName `
  -Location "westeurope" `
  -ErrorAction SilentlyContinue | Out-Null

Set-AzApplicationGatewayFirewallPolicySetting `
  -Name "waf18weu" `
  -ResourceGroupName $ResourceGroupName `
  -Mode Prevention | Out-Null

# 3) Attach policy to the Application Gateway
$Waf   = Get-AzApplicationGatewayFirewallPolicy -Name "waf18weu" -ResourceGroupName $ResourceGroupName
$Agw   = Get-AzApplicationGateway -Name $GatewayName -ResourceGroupName $ResourceGroupName
$Agw.WebApplicationFirewallConfiguration = New-AzApplicationGatewayWebApplicationFirewallConfiguration `
  -Enabled $true `
  -FirewallPolicyId $Waf.Id
Set-AzApplicationGateway -ApplicationGateway $Agw | Out-Null

# 4) Create custom health probe (/healthz) and HTTP settings
$Agw = Get-AzApplicationGateway -Name $GatewayName -ResourceGroupName $ResourceGroupName

$Probe = New-AzApplicationGatewayProbeConfig `
  -Name "probe18" `
  -Protocol Http `
  -HostName "127.0.0.1" `
  -Path "/healthz" `
  -Interval 30 `
  -Timeout 60 `
  -UnhealthyThreshold 3 `
  -PickHostNameFromBackendHttpSettings:$false `
  -Port 80

$HttpSettings = New-AzApplicationGatewayBackendHttpSetting `
  -Name "httpset18" `
  -Port 80 `
  -Protocol Http `
  -CookieBasedAffinity Disabled `
  -RequestTimeout 30 `
  -Probe $Probe

# 5) Backend pool with static IPs
$Pool = New-AzApplicationGatewayBackendAddressPool `
  -Name "pool18" `
  -BackendIPAddresses 10.18.2.10,10.18.2.11

# 6) Ensure frontend port 80 exists
$FrontendPort = ($Agw.FrontendPorts | Where-Object { $_.Port -eq 80 } | Select-Object -First 1)
if (-not $FrontendPort) {
  $FrontendPort = New-AzApplicationGatewayFrontendPort -Name "fp-80" -Port 80
  $Agw.FrontendPorts += $FrontendPort
}

# 7) Listener and rule
$FrontendIp = $Agw.FrontendIpConfigurations[0]
$Listener = New-AzApplicationGatewayHttpListener `
  -Name "lstn18-http" `
  -Protocol Http `
  -FrontendIpConfiguration $FrontendIp `
  -FrontendPort $FrontendPort

$Rule = New-AzApplicationGatewayRequestRoutingRule `
  -Name "rule18" `
  -RuleType Basic `
  -HttpListener $Listener `
  -BackendAddressPool $Pool `
  -BackendHttpSettings $HttpSettings

# 8) Add components to the gateway configuration and apply
$Agw.BackendAddressPools += $Pool
$Agw.Probes += $Probe
$Agw.BackendHttpSettingsCollection += $HttpSettings
$Agw.HttpListeners += $Listener
$Agw.RequestRoutingRules += $Rule
Set-AzApplicationGateway -ApplicationGateway $Agw | Out-Null

# 9) Diagnostics: Log Analytics + Storage
$Agw = Get-AzApplicationGateway -Name $GatewayName -ResourceGroupName $ResourceGroupName
$Law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
$Stg = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageName

New-AzDiagnosticSetting `
  -Name "diag-agw18-la" `
  -ResourceId $Agw.Id `
  -WorkspaceId $Law.ResourceId `
  -EnabledLog @{Category="ApplicationGatewayAccessLog"; Enabled=$true}, @{Category="ApplicationGatewayFirewallLog"; Enabled=$true} `
  -MetricCategory "AllMetrics" -MetricEnabled $true `
  -ErrorAction SilentlyContinue | Out-Null

New-AzDiagnosticSetting `
  -Name "diag-agw18-stor" `
  -ResourceId $Agw.Id `
  -StorageAccountId $Stg.Id `
  -EnabledLog @{Category="ApplicationGatewayAccessLog"; Enabled=$true}, @{Category="ApplicationGatewayFirewallLog"; Enabled=$true} `
  -MetricCategory "AllMetrics" -MetricEnabled $true `
  -ErrorAction SilentlyContinue | Out-Null

# 10) Backend health snapshot
Get-AzApplicationGatewayBackendHealth -Name $GatewayName -ResourceGroupName $ResourceGroupName | Format-Table -AutoSize
