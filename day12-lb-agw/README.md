# Day12 — Azure Load Balancer + Application Gateway
Run either script:
- `./day12-lb-agw-cli.sh`  # Azure CLI
- `pwsh ./Day12-LB-AppGW.ps1`  # PowerShell (Az module)

Both assume resources from the Portal exist (RG/VNet/VMs/LB/AGW).
They enforce health probes, rules, NSG, URL path map, and diagnostics.
