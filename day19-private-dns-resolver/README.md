# Day19 — Azure Private DNS Resolver (pdr19weu)

## Overview
Managed, private DNS resolution inside Azure VNets. Inbound endpoint receives queries from VNet/Peering/VPN/ER. Outbound endpoint forwards conditionally via DNS forwarding ruleset to target DNS servers. No Public IP is required.

## Architecture (ASCII)
VM (snet-workload) -> 127.0.0.53 (systemd-resolved)
  -> Azure DNS (168.63.129.16)
    ├─ if name in Private DNS zone -> answer directly
    └─ if name matches ruleset -> Private Resolver (Outbound) -> Outbound endpoint -> Target DNS
(Direct test path) VM -> Inbound endpoint IP -> Private DNS zone (authoritative) -> answer

## Resources (RG: rg-day19-fd, LOC: westeurope)
- vnet19weu: 10.19.0.0/24
  - snet-pdr-inbound: 10.19.0.0/28 (delegated to Microsoft.Network/dnsResolvers)
  - snet-pdr-outbound: 10.19.0.16/28 (delegated to Microsoft.Network/dnsResolvers)
  - snet-workload: 10.19.0.64/26
- pdr19weu (DNS private resolver)
  - inep19weu (Inbound) -> IP: <fill-after-deploy>
  - outep19weu (Outbound)
- drs19weu (DNS forwarding ruleset)
  - rule: microsoft.com -> 1.1.1.1:53, 8.8.8.8:53
  - association: vnet19weu
- priv19.local (Private DNS zone) + A: app1 -> 10.19.0.100
- vm19u1 (Ubuntu, no Public IP)
- secp19weu (DNS Security Policy) + Diagnostic settings -> la19weu, sa19logs<unique>
- la19weu (Log Analytics), sa19logs<unique> (Storage + lifecycle)

## Tests
```bash
# Default path via Azure-provided DNS
nslookup app1.priv19.local

# Explicit query via Inbound endpoint (replace with actual IP)
nslookup app1.priv19.local <Inbound_IP>

# Ruleset outbound path for public domain
nslookup www.microsoft.com
KQL (Log Analytics: DNSQueryLogs)
kql
Copy code
// Volume over last 2 hours
DNSQueryLogs
| where TimeGenerated > ago(2h)
| summarize count() by bin(TimeGenerated, 5m)

// Private zone lookups
DNSQueryLogs
| where TimeGenerated > ago(2h)
| where QueryName endswith ".priv19.local"
| project TimeGenerated, QueryName, ResponseCode, VirtualNetworkId
| order by TimeGenerated desc

// Ruleset forwarding check
DNSQueryLogs
| where TimeGenerated > ago(2h)
| where QueryName endswith ".microsoft.com"
| summarize Requests=count() by ResponseCode
Alert (Monitor -> Alerts)
kql
Copy code
// DNS errors (SERVFAIL=2, NXDOMAIN=3, REFUSED=5) in last 5 minutes
DNSQueryLogs
| where TimeGenerated > ago(5m)
| where ResponseCode in (2,3,5)
| summarize ErrorCount = count()
Security notes
No Public IP on any workload. Delegated subnets for dnsResolvers only.

RBAC on RG. Storage TLS 1.2 minimum. Blob public access disabled.

Lifecycle moves logs to cool and deletes old data to control costs.

Cleanup
Delete VM, then pdr19weu, drs19weu, priv19.local, secp19weu, la19weu, sa19logs<unique>, and finally rg-day19-fd.
