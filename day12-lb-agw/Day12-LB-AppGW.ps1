<# 
Day12: Azure Load Balancer + Application Gateway (PowerShell)
English comments. Secure-by-default. Assumes VMs/VNet exist from Portal.
#>

param(
  [string]$Subscription = "88b94352-6cdb-4d24-af7a-ec22a366b617",
  [string]$ResourceGroup = "rg-day12-lb",
  [string]$Location = "westeurope",
  [string]$VNetName = "vnet12weu",
  [string]$SubnetBackend = "snet-backend",
  [string]$SubnetAgw = "snet-agw",
  [string]$LbName = "lb12weu",
  [string]$BePoolName = "bepool12",
  [string]$ProbeName = "hp-http-80",
  [string]$RuleName = "lbr-http-80",
  [string]$NsgName = "nsg-backend12weu",
  [string]$AgwName = "agw12weu",
  [string]$LawName = "law12weu"
)

# Subscription
Select-AzSubscription -Subscription $Subscription | Out-Null

# Resolve backend IPs
$ipA = (Get-AzVM -ResourceGroupName $ResourceGroup -Name "vm12a" -Status).PrivateIps
$ipB = (Get-AzVM -ResourceGroupName $ResourceGroup -Name "vm12b" -Status).PrivateIps

# ===== Load Balancer: probe + rule ensure =====
$lb = Get-AzLoadBalancer -ResourceGroupName $ResourceGroup -Name $LbName

# Ensure HTTP probe on /healthz
$probe = $lb.Probes | Where-Object Name -eq $ProbeName
if (-not $probe) {
  $probe = Add-AzLoadBalancerProbeConfig -LoadBalancer $lb -Name $ProbeName -Protocol Http -Port 80 -RequestPath "/healthz"
  $lb | Set-AzLoadBalancer | Out-Null
  $lb = Get-AzLoadBalancer -ResourceGroupName $ResourceGroup -Name $LbName
}

# Ensure rule maps 80->80 with probe
$rule = $lb.LoadBalancingRules | Where-Object Name -eq $RuleName
if ($rule) {
  $rule.BackendPort = 80
  $rule.FrontendPort = 80
  $rule.Protocol = "Tcp"
  $rule.Probe = ($lb.Probes | Where-Object Name -eq $ProbeName)
  $lb | Set-AzLoadBalancer | Out-Null
}

# ===== NSG: allow LB probe, AGW data path, Internet data path =====
$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -Name $NsgName
function Ensure-Rule($n,$p,$src,$dst,$port){
  if (-not ($nsg.SecurityRules | Where-Object Name -eq $n)) {
    $rule = New-AzNetworkSecurityRuleConfig -Name $n -Description $n -Access Allow -Protocol Tcp `
      -Direction Inbound -Priority $p -SourceAddressPrefix $src -SourcePortRange * `
      -DestinationAddressPrefix $dst -DestinationPortRange $port
    $nsg.SecurityRules += $rule
  }
}
Ensure-Rule -n "allow-lb-probe-80" -p 100 -src "AzureLoadBalancer" -dst "VirtualNetwork" -port 80
# AGW subnet prefix
$agwSubnet = (Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName).Subnets | Where-Object Name -eq $SubnetAgw
Ensure-Rule -n "allow-agw-80" -p 110 -src $agwSubnet.AddressPrefix -dst "VirtualNetwork" -port 80
Ensure-Rule -n "allow-lb-data-80" -p 120 -src "Internet" -dst "VirtualNetwork" -port 80
$nsg | Set-AzNetworkSecurityGroup | Out-Null
# Associate NSG to backend subnet
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $VNetName
$beSubnet = $vnet.Subnets | Where-Object Name -eq $SubnetBackend
$beSubnet.NetworkSecurityGroup = $nsg
Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null

# ===== Application Gateway: backend pool + probe + http settings + path map =====
$gw = Get-AzApplicationGateway -ResourceGroupName $ResourceGroup -Name $AgwName

# Ensure backend pool be-web has VM IPs
$be = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $gw -Name "be-web" -ErrorAction SilentlyContinue
if (-not $be) {
  $be = Add-AzApplicationGatewayBackendAddressPool -ApplicationGateway $gw -Name "be-web"
}
$be.BackendAddresses = @(
  (New-AzApplicationGatewayBackendAddress -IpAddress $ipA),
  (New-AzApplicationGatewayBackendAddress -IpAddress $ipB)
)

# Ensure custom probe
$probeAgw = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $gw -Name $ProbeName -ErrorAction SilentlyContinue
if (-not $probeAgw) {
  $probeAgw = Add-AzApplicationGatewayProbeConfig -ApplicationGateway $gw -Name $ProbeName `
    -Protocol Http -HostName "127.0.0.1" -Path "/healthz" -Interval 5 -Timeout 5 -UnhealthyThreshold 2
} else {
  $probeAgw.Protocol = "Http"
  $probeAgw.HostName = "127.0.0.1"
  $probeAgw.Path = "/healthz"
  $probeAgw.Interval = 5
  $probeAgw.Timeout = 5
  $probeAgw.UnhealthyThreshold = 2
}

# Bind probe to first HTTP settings
$http = Get-AzApplicationGatewayBackendHttpSettings -ApplicationGateway $gw | Select-Object -First 1
$http.Probe = $probeAgw

# URL path map with /api/* and default /*
$upm = Get-AzApplicationGatewayUrlPathMapConfig -ApplicationGateway $gw -Name "upm-web" -ErrorAction SilentlyContinue
if (-not $upm) {
  $prApi = New-AzApplicationGatewayPathRuleConfig -Name "pr-api" -Paths "/api/*" -BackendAddressPool $be -BackendHttpSettings $http
  $upm = Add-AzApplicationGatewayUrlPathMapConfig -ApplicationGateway $gw -Name "upm-web" `
    -DefaultBackendAddressPool $be -DefaultBackendHttpSettings $http -PathRule $prApi
}

# Convert first routing rule to PathBasedRouting if needed
$rule = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $gw | Select-Object -First 1
$rule.RuleType = "PathBasedRouting"
$rule.UrlPathMap = $upm

# Commit App Gateway changes
Set-AzApplicationGateway -ApplicationGateway $gw | Out-Null

# ===== Diagnostics to Log Analytics =====
$law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $LawName -ErrorAction SilentlyContinue
if (-not $law) {
  $law = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $LawName -Location $Location
}

# LB diagnostics settings
$lbId = $lb.Id
Set-AzDiagnosticSetting -Name "lb-diag" -ResourceId $lbId -WorkspaceId $law.ResourceId `
  -Category "LoadBalancerAlertEvent","LoadBalancerProbeHealthStatus","LoadBalancerRuleCounter" `
  -MetricCategory "AllMetrics" -Enabled $true

# AppGW diagnostics settings
$gwId = $gw.Id
Set-AzDiagnosticSetting -Name "agw-diag" -ResourceId $gwId -WorkspaceId $law.ResourceId `
  -Category "ApplicationGatewayAccessLog","ApplicationGatewayPerformanceLog","ApplicationGatewayFirewallLog" `
  -MetricCategory "AllMetrics" -Enabled $true

# ===== Outputs =====
$lbIp  = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Name "pip12weu").IpAddress
$agwIp = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Name "agw-pip12weu").IpAddress
Write-Host ("LB Public IP:  {0}" -f $lbIp)
Write-Host ("AGW Public IP: {0}" -f $agwIp)
