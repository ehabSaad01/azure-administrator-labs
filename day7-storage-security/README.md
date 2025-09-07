# Day7 — Storage Security (Azure)
**Scope:** SAS, RBAC, Networking, Private Endpoints.

## Prereqs
- Azure CLI or Az PowerShell.
- Contributor on subscription/RG.
- Replace <YOUR_SUBSCRIPTION_ID> and unique storage names.

## Bash (CLI)
chmod +x day7-storage-security-cli.sh
./day7-storage-security-cli.sh

## PowerShell
pwsh -File ./Day7-Storage-Security.ps1

## Notes
- Container created via ARM to bypass storage firewall.
- RBAC = identity-based; SAS = resource-based.
- Public network access disabled after PE.

## Cleanup
az group delete -n rg-day7-storage-security-cli -y --no-wait
az group delete -n rg-day7-storage-security-ps -y --no-wait
