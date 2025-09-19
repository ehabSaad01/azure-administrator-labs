# Day17 — Network Watcher

## What this includes
- day17-netwatch-cli-long.sh — Azure CLI (long options, no vars).
- Day17-Network-Watcher.ps1 — PowerShell (explicit params, no vars).

## How to run (CLI)
chmod +x day17-network-watcher/day17-netwatch-cli-long.sh
./day17-network-watcher/day17-netwatch-cli-long.sh

## How to run (PowerShell)
pwsh -File day17-network-watcher/Day17-Network-Watcher.ps1

## Notes
- Connection Monitor: cm17 (tg-branch, tg-internet).
- Virtual network flow logs → Storage sa17flow → Traffic Analytics in la17weu.
- Packet capture requires Network Watcher Agent on the VM.
