# Day14 — Azure Firewall: DNAT/SNAT + Outbound Control

## Scope
Baseline Azure Firewall in VNet with outbound control (UDR + SNAT) and inbound DNAT.

## Topology
- VNet `vnet14weu` (10.14.0.0/16)
  - `AzureFirewallSubnet` (10.14.0.0/26)
  - `snet-backend14` (10.14.1.0/24)
- Firewall `afw14weu` + Policy `afwpol14`
- Public IP `pip-afw14`
- VM `vm14a` (no Public IP)
- Route table `rt-backend14` → `0.0.0.0/0` → Firewall private IP
- NSG `nsg-backend14` (temp SSH allow for DNAT test)
- Log Analytics `law14weu`

## Scripts
- `day14-azure-firewall-cli.sh` — Minimal az CLI.
- `Day14-Azure-Firewall.ps1` — Minimal Az PowerShell.

## Tests
VM (Run Command):
  nslookup github.com
  curl -s https://ifconfig.io
  curl -I https://github.com

DNAT from local:
  ssh -i /path/to/vm14a_key.pem azureuser@<PIP_AFW14> -p 22

## Cleanup
az group delete --name rg-day14-firewall --yes --no-wait
