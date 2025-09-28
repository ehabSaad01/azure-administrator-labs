# Purpose: End-to-end deployment for Azure DNS Private Resolver (secure-by-default).
# Style: Long parameters only. No pre-set variables if avoidable. English comments only.
# Prereqs: Connect-AzAccount; Az modules: Az.Accounts, Az.Network, Az.PrivateDns, Az.Monitor, Az.OperationalInsights, Az.DnsResolver.

# 1) Resource Group
New-AzResourceGroup -Name rg-day19-pdr -Location westeurope

# 2) Log Analytics Workspace (for DNSQueryLogs)
New-AzOperationalInsightsWorkspace -ResourceGroupName rg-day19-pdr -Name la19weu -Location westeurope -Sku PerGB2018 -RetentionInDays 30

# 3) Storage Account (secure baseline for archival)
New-AzStorageAccount -ResourceGroupName rg-day19-pdr -Name sa19logsx1234567 -Location westeurope -SkuName Standard_LRS -Kind StorageV2 -EnableHttpsTrafficOnly $true -MinimumTlsVersion TLS1_2 -AllowBlobPublicAccess $false
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName rg-day19-pdr -Name sa19logsx1234567 -DefaultAction Deny -Bypass AzureServices
Set-AzStorageBlobServiceProperty -ResourceGroupName rg-day19-pdr -AccountName sa19logsx1234567 -EnableVersioning $true -EnableDeleteRetentionPolicy $true -DeleteRetentionPolicyDays 14

# 4) Virtual Network and subnets (pipeline, no temp variables)
New-AzVirtualNetwork -Name vnet19weu -ResourceGroupName rg-day19-pdr -Location westeurope -AddressPrefix "10.19.0.0/24" -Subnet @(@{Name="snet-pdr-inbound"; AddressPrefix="10.19.0.0/28"})
(Get-AzVirtualNetwork -Name vnet19weu -ResourceGroupName rg-day19-pdr) | Set-AzVirtualNetworkSubnetConfig -Name snet-pdr-inbound -AddressPrefix "10.19.0.0/28" -Delegation (New-AzDelegation -Name "dnsres-in" -ServiceName "Microsoft.Network/dnsResolvers") | Set-AzVirtualNetwork
(Get-AzVirtualNetwork -Name vnet19weu -ResourceGroupName rg-day19-pdr) | Add-AzVirtualNetworkSubnetConfig -Name snet-pdr-outbound -AddressPrefix "10.19.0.16/28" -Delegation (New-AzDelegation -Name "dnsres-out" -ServiceName "Microsoft.Network/dnsResolvers") | Set-AzVirtualNetwork
(Get-AzVirtualNetwork -Name vnet19weu -ResourceGroupName rg-day19-pdr) | Add-AzVirtualNetworkSubnetConfig -Name snet-workload -AddressPrefix "10.19.0.64/26" | Set-AzVirtualNetwork

# 5) Private DNS Resolver (core service)
New-AzDnsResolver -Name pdr19weu -ResourceGroupName rg-day19-pdr -Location westeurope -VirtualNetworkId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu"
New-AzDnsResolverInboundEndpoint -DnsResolverName pdr19weu -ResourceGroupName rg-day19-pdr -Name inep19weu -Location westeurope -IpConfiguration (New-AzDnsResolverIPConfigurationObject -PrivateIPAllocationMethod "Dynamic" -SubnetId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu/subnets/snet-pdr-inbound" -Name "ipconfig1")
New-AzDnsResolverOutboundEndpoint -DnsResolverName pdr19weu -ResourceGroupName rg-day19-pdr -Name outep19weu -Location westeurope -SubnetId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu/subnets/snet-pdr-outbound"

# 6) Forwarding Ruleset + VNet link + sample rule
New-AzDnsForwardingRuleset -Name drs19weu -ResourceGroupName rg-day19-pdr -Location westeurope -DnsResolverOutboundEndpoint (Get-AzDnsResolverOutboundEndpoint -DnsResolverName pdr19weu -ResourceGroupName rg-day19-pdr -Name outep19weu)
New-AzDnsForwardingRulesetVirtualNetworkLink -Name drs19weu-vnet19weu-link -ResourceGroupName rg-day19-pdr -VirtualNetworkId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu" -DnsForwardingRulesetName drs19weu
New-AzDnsForwardingRulesetForwardingRule -Name fr-microsoft -ResourceGroupName rg-day19-pdr -DnsForwardingRulesetName drs19weu -DomainName "microsoft.com." -TargetDnsServer (New-AzDnsResolverTargetDnsServerObject -IpAddress "1.1.1.1" -Port 53), (New-AzDnsResolverTargetDnsServerObject -IpAddress "8.8.8.8" -Port 53) -Enabled $true

# 7) Private DNS zone + link + A record
New-AzPrivateDnsZone -ResourceGroupName rg-day19-pdr -Name "priv19.local"
New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName rg-day19-pdr -ZoneName "priv19.local" -Name "vnet19weu-link" -VirtualNetworkId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu" -EnableRegistration $false
New-AzPrivateDnsRecordSet -ResourceGroupName rg-day19-pdr -ZoneName "priv19.local" -Name "app1" -RecordType "A" -Ttl 300 -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address "10.19.0.100")

# 8) DNS Security Policy + Diagnostics (DNSQueryLogs)
New-AzDnsResolverPolicy -Name secp19weu -ResourceGroupName rg-day19-pdr -Location westeurope
New-AzDnsResolverPolicyVirtualNetworkLink -Name secp19weu-vnet19weu-link -ResourceGroupName rg-day19-pdr -VirtualNetworkId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/virtualNetworks/vnet19weu" -DnsResolverPolicyName secp19weu
New-AzDiagnosticSetting -Name "diag-secp19weu" -ResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-day19-pdr/providers/Microsoft.Network/dnsResolverPolicies/secp19weu" -WorkspaceId (Get-AzOperationalInsightsWorkspace -ResourceGroupName rg-day19-pdr -Name la19weu).ResourceId -StorageAccountId (Get-AzStorageAccount -ResourceGroupName rg-day19-pdr -Name sa19logsx1234567).Id -Category "DnsResponse" -Enabled $true
