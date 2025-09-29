<#
Purpose: Provision Day21 lab using Az PowerShell with long parameters and clear comments.
Notes:
- Requires Az modules and an authenticated session (Connect-AzAccount).
- Uses variables for readability; no loops.
- Region: West Europe.
#>

# ---[ Connect ]---
# Connect-AzAccount  # Uncomment if needed

# ---[ Parameters / Names ]---
$Location = "westeurope"
$RgName = "rg-day21-compute"
$LawName = "law21weu"
$VnetName = "vnet21weu"
$VnetPrefix = "10.21.0.0/16"
$SubnetName = "subnet-app21"
$SubnetPrefix = "10.21.1.0/24"
$NsgName = "nsg-subnet-app21"
$NatPipName = "pip-nat21weu"
$NatGwName = "natgw21weu"
$LbPipName = "pip-lb21weu"
$LbName = "lb21weu"
$FeName = "fe-lb21weu"
$BePoolName = "bepool21"
$ProbeName = "hp-tcp-80"
$RuleName = "lbr-80"
$VmssName = "vmss21weu"
$AutoscaleName = "autoscale-vmss21"
$DiagName = "diag-lb21"
$AlertName = "natgw-snat-util-80"

# ---[ Resource Group ]---
New-AzResourceGroup -Name $RgName -Location $Location | Out-Null

# ---[ Log Analytics Workspace ]---
New-AzOperationalInsightsWorkspace -ResourceGroupName $RgName -Name $LawName -Location $Location -Sku "PerGB2018" | Out-Null
$Law = Get-AzOperationalInsightsWorkspace -ResourceGroupName $RgName -Name $LawName

# ---[ Virtual Network + Subnet ]---
$SubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix
$Vnet = New-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Location $Location -AddressPrefix $VnetPrefix -Subnet $SubnetConfig

# ---[ NSG + Rule Allow AzureLoadBalancer:80/TCP ]---
$Nsg = New-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $RgName -Location $Location
$Rule = Add-AzNetworkSecurityRuleConfig -Name "AllowAzureLoadBalancerInBound-80" -NetworkSecurityGroup $Nsg -Priority 100 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix "AzureLoadBalancer" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 80
$Nsg | Set-AzNetworkSecurityGroup | Out-Null
$Vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName
Set-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet -AddressPrefix $SubnetPrefix -NetworkSecurityGroup $Nsg | Out-Null
$Vnet | Set-AzVirtualNetwork | Out-Null

# ---[ NAT Gateway + Public IP + Subnet Association ]---
$NatPip = New-AzPublicIpAddress -Name $NatPipName -ResourceGroupName $RgName -Location $Location -Sku Standard -AllocationMethod Static
$NatGw = New-AzNatGateway -Name $NatGwName -ResourceGroupName $RgName -Location $Location -PublicIpAddress $NatPip -Sku Standard -IdleTimeoutInMinutes 4 -Zone 1,2,3
$Vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName
$Subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet
$Subnet.NatGateway = $NatGw
$Vnet | Set-AzVirtualNetwork | Out-Null

# ---[ Public Load Balancer ]---
$LbPip = New-AzPublicIpAddress -Name $LbPipName -ResourceGroupName $RgName -Location $Location -Sku Standard -AllocationMethod Static
$FeIpCfg = New-AzLoadBalancerFrontendIpConfig -Name $FeName -PublicIpAddress $LbPip
$BePool = New-AzLoadBalancerBackendAddressPoolConfig -Name $BePoolName
$Probe = New-AzLoadBalancerProbeConfig -Name $ProbeName -Protocol Tcp -Port 80 -IntervalInSeconds 5 -ProbeCount 2
$Rule = New-AzLoadBalancerRuleConfig -Name $RuleName -FrontendIpConfiguration $FeIpCfg -BackendAddressPool $BePool -Probe $Probe -Protocol Tcp -FrontendPort 80 -BackendPort 80 -IdleTimeoutInMinutes 4 -DisableOutboundSNAT
$Lb = New-AzLoadBalancer -Name $LbName -ResourceGroupName $RgName -Location $Location -Sku "Standard" -FrontendIpConfiguration $FeIpCfg -BackendAddressPool $BePool -Probe $Probe -LoadBalancingRule $Rule

# ---[ VMSS (Linux/Uniform) ]---
$Subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet
$IpConfig = New-AzVmssIpConfig -Name "ipconfig1" -SubnetId $Subnet.Id -LoadBalancerBackendAddressPoolsId $Lb.BackendAddressPools[0].Id
$VmssConfig = New-AzVmssConfig -Location $Location -SkuCapacity 2 -SkuName "Standard_B2s" -UpgradePolicyMode "Manual"
Set-AzVmssOsProfile -VirtualMachineScaleSet $VmssConfig -ComputerNamePrefix "vmss21" -AdminUsername "azureuser" -LinuxConfiguration (New-AzVmssLinuxConfigurationObject -DisablePasswordAuthentication -SshPublicKey "/home/azureuser/.ssh/authorized_keys" "ssh-rsa PLACEHOLDER")
# Note: Generate SSH keys if needed; portal/CLI usually handles this. For pure PS, you can adjust SSH key injection as required.
Set-AzVmssStorageProfile -VirtualMachineScaleSet $VmssConfig -ImageReferenceOffer "UbuntuServer" -ImageReferencePublisher "Canonical" -ImageReferenceSku "22_04-lts-gen2" -ImageReferenceVersion "latest"
Add-AzVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $VmssConfig -Name "nicconfig1" -Primary $true -IPConfiguration $IpConfig
$Vmss = New-AzVmss -ResourceGroupName $RgName -Name $VmssName -VirtualMachineScaleSet $VmssConfig

# ---[ Custom Script Extension ]---
# Install Nginx and publish a simple page; keep command only in protected settings.
Set-AzVmssExtension `
  -ResourceGroupName $RgName `
  -VMScaleSetName $VmssName `
  -Name "CustomScript" `
  -Publisher "Microsoft.Azure.Extensions" `
  -Type "CustomScript" `
  -TypeHandlerVersion "2.1" `
  -ProtectedSettingString '{"commandToExecute":"/bin/bash -c \"sudo apt-get update -y && sudo apt-get install -y nginx && echo ''Day21 VMSS + LB + NATGW Lab'' | sudo tee /var/www/html/index.html && sudo systemctl enable --now nginx\""}'

# ---[ Autoscale: CPU-based ]---
# Create autoscale setting and two CPU rules (out/in).
$VmssId = (Get-AzVmss -ResourceGroupName $RgName -VMScaleSetName $VmssName).Id
$Setting = New-AzAutoscaleSetting -ResourceGroupName $RgName -Name $AutoscaleName -TargetResourceId $VmssId -MetricBased -DefaultProfile -AutoscaleProfileCapacityMin 2 -AutoscaleProfileCapacityMax 5 -AutoscaleProfileCapacityDefault 2 -Location $Location
Add-AzAutoscaleRule -AutoscaleSetting $Setting -MetricName "Percentage CPU" -MetricResourceId $VmssId -Operator GreaterThan -Threshold 60 -TimeGrain (New-TimeSpan -Minutes 1) -TimeWindow (New-TimeSpan -Minutes 5) -ScaleActionDirection Increase -ScaleActionType ChangeCount -ScaleActionValue 1 -ScaleActionCooldown (New-TimeSpan -Minutes 5) | Out-Null
Add-AzAutoscaleRule -AutoscaleSetting $Setting -MetricName "Percentage CPU" -MetricResourceId $VmssId -Operator LessThan -Threshold 30 -TimeGrain (New-TimeSpan -Minutes 1) -TimeWindow (New-TimeSpan -Minutes 5) -ScaleActionDirection Decrease -ScaleActionType ChangeCount -ScaleActionValue 1 -ScaleActionCooldown (New-TimeSpan -Minutes 5) | Out-Null
Set-AzAutoscaleSetting -AutoscaleSetting $Setting | Out-Null

# ---[ Diagnostics for Load Balancer ]---
# Send LB logs and metrics to the Log Analytics workspace.
$LbId = (Get-AzLoadBalancer -ResourceGroupName $RgName -Name $LbName).Id
Set-AzDiagnosticSetting -Name $DiagName -ResourceId $LbId -WorkspaceId $Law.ResourceId -Enabled $true -Category "LoadBalancerAlertEvent","LoadBalancerProbeHealthStatus","LoadBalancerRuleCounter" -MetricCategory "AllMetrics" -MetricEnabled $true | Out-Null

# ---[ NAT Gateway Metric Alert (SnatPortUtilization >= 80%) ]---
$NatGwId = (Get-AzNatGateway -ResourceGroupName $RgName -Name $NatGwName).Id
$Criteria = New-AzMetricAlertRuleV2Criteria -MetricName "SnatPortUtilization" -TimeAggregation Average -Operator GreaterThanOrEqual -Threshold 80
New-AzMetricAlertRuleV2 -Name $AlertName -ResourceGroupName $RgName -WindowSize (New-TimeSpan -Minutes 5) -Frequency (New-TimeSpan -Minutes 5) -TargetResourceScope $NatGwId -Condition $Criteria -Severity 2 -Description "Alert when NAT GW SNAT port utilization >= 80%" | Out-Null

# ---[ End of script ]---
