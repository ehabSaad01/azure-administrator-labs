# Day11 — Monitoring & Alerts
Scope: Azure Monitor, Log Analytics, Action Groups, Alerts, Workbooks (portal).

## Artifacts
- day11-monitoring-cli.sh  # Bash, long options
- Day11-Monitoring.ps1     # PowerShell Az
- kql/heartbeat-missing.kql
- kql/rg-delete.kql

## How to run (CLI)
export SUBSCRIPTION="<id>"; export RG="rg-day11-monitor"; export LOC="westeurope"; export LA="la11weu"; export AG="ag11weu"; export EMAIL="<you@example.com>"; \
bash day11-monitoring/day11-monitoring-cli.sh
