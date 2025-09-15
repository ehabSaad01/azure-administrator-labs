# Day13 — NAT Gateway (PowerShell, long params, no loops)
# Replace <your_subscription_id>. All names/CIDRs are explicit for clarity.

$SubscriptionId = "<your_subscription_id>"
$RgName         = "rg-day13-nat"
$Location       = "westeurope"
$VnetName       = "vnet13weu"
$VnetCidr       = "10.13.0.0/16"
$SubnetName     = "snet-backend13"
$SubnetCidr     = "10.13.1.0/24"
$NsgName        = "nsg-backend13"
$PipName        = "pip13weu"
$NatName        = "natg13weu"
$BastSubnetName = "AzureBastionSubnet"
$BastSubnetCidr = "10.13.100.0/26"
$BastionPip     = "pip-bast13weu"
$BastionName    = "bast13weu"
$VmName         = "vm13a"

# 0) Subscription
Select-AzSubscription -SubscriptionId $SubscriptionId

# 1) Resource Group — logical container for access control and cleanup
New-AzResourceGroup -Name $RgName -Location $Location -ErrorAction SilentlyContinue | Out-Null

# 2) VNet + Subnet — private space for workloads (backend)
$vnet = New-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Location $Location -AddressPrefix @($VnetCidr) -ErrorAction SilentlyContinue
if (-not $vnet) { $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName }
$backendSubnet = Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetCidr -VirtualNetwork $vnet
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

# 3) NSG — secure-by-default outbound (DNS + 80/443 allowed)
$nsg = New-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $RgName -Location $Location -ErrorAction SilentlyContinue
if (-not $nsg) { $nsg = Get-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $RgName }

$rule1 = New-AzNetworkSecurityRuleConfig -Name "Allow-DNS-Azure" -Description "Allow DNS to Azure DNS" -Access Allow -Protocol *  -Direction Outbound -Priority 200  -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix "168.63.129.16" -DestinationPortRange 53
$rule2 = New-AzNetworkSecurityRuleConfig -Name "Allow-HTTP-HTTPS" -Description "Allow HTTP/HTTPS to Internet" -Access Allow -Protocol Tcp -Direction Outbound -Priority 210  -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Internet -DestinationPortRange 80,443
$rule3 = New-AzNetworkSecurityRuleConfig -Name "Deny-Internet-All" -Description "Deny any other Internet egress" -Access Deny  -Protocol *  -Direction Outbound -Priority 4096 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Internet -DestinationPortRange *

$nsg.SecurityRules.Clear()
$nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg -SecurityRule $rule1,$rule2,$rule3

# Attach NSG to backend subnet
$vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName
$backendSubnet = Set-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -AddressPrefix $SubnetCidr -NetworkSecurityGroup $nsg
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

# 4) Public IP for NAT — stable outbound identity (64K SNAT ports)
$pip = New-AzPublicIpAddress -Name $PipName -ResourceGroupName $RgName -Location $Location -AllocationMethod Static -Sku Standard -IpAddressVersion IPv4 -ErrorAction SilentlyContinue
if (-not $pip) { $pip = Get-AzPublicIpAddress -Name $PipName -ResourceGroupName $RgName }

# 5) NAT Gateway — egress only (SNAT/PAT) and bind the PIP
$nat = New-AzNatGateway -Name $NatName -ResourceGroupName $RgName -Location $Location -Sku Standard -PublicIpAddress $pip -ErrorAction SilentlyContinue
if (-not $nat) { $nat = Get-AzNatGateway -Name $NatName -ResourceGroupName $RgName }

# Associate NAT to backend subnet
$vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName
$backendSubnet = Set-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -AddressPrefix $SubnetCidr -NetworkSecurityGroup $nsg -NatGateway $nat
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

# 6) Bastion — admin access without VM public ports
$vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName
$bastSubnetCfg = Add-AzVirtualNetworkSubnetConfig -Name $BastSubnetName -AddressPrefix $BastSubnetCidr -VirtualNetwork $vnet
$vnet = Set-AzVirtualNetwork -VirtualNetwork $vnet

$bastPip = New-AzPublicIpAddress -Name $BastionPip -ResourceGroupName $RgName -Location $Location -AllocationMethod Static -Sku Standard -IpAddressVersion IPv4 -ErrorAction SilentlyContinue
if (-not $bastPip) { $bastPip = Get-AzPublicIpAddress -Name $BastionPip -ResourceGroupName $RgName }

New-AzBastion -Name $BastionName -ResourceGroupName $RgName -PublicIpAddress $bastPip -VirtualNetwork $vnet -Location $Location -ErrorAction SilentlyContinue | Out-Null

# 7) Test VM — no NIC Public IP; egress must go via NAT
$cred = New-Object -TypeName PSCredential -ArgumentList "azureuser",(ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force)
New-AzVM -ResourceGroupName $RgName -Name $VmName -Location $Location -Image "Ubuntu2204" -Size "Standard_B1s" -VirtualNetworkName $VnetName -SubnetName $SubnetName -PublicIpAddressName $null -GenerateSshKey -Credential $cred -ErrorAction SilentlyContinue

# Validate later from vm13a over Bastion: curl -s https://ifconfig.me
