#!/usr/bin/env bash
# =========================================
# Day17 - Network Watcher (CLI, long-form)
# No variables. No loops. English comments.
# Region: westeurope
# RGs: NetworkWatcherRG, rg-day17-netwatch
# Resources: cm17, la17weu, sa17flow, vm17a, vm17b, vnet17weu, vnet-branch17
# =========================================

# [0] Ensure Network Watcher is enabled in region
az network watcher configure \
  --resource-group NetworkWatcherRG \
  --locations westeurope \
  --enabled true

# [1] Inventory: resource group and core resources
az group show \
  --name rg-day17-netwatch \
  --output table

az network vnet show \
  --resource-group rg-day17-netwatch \
  --name vnet17weu \
  --output table

az network vnet show \
  --resource-group rg-day17-netwatch \
  --name vnet-branch17 \
  --output table

az vm show \
  --resource-group rg-day17-netwatch \
  --name vm17a \
  --show-details \
  --output table

az vm show \
  --resource-group rg-day17-netwatch \
  --name vm17b \
  --show-details \
  --output table

# [2] Connection Monitor v2: show definition and parts
az network watcher connection-monitor show \
  --location westeurope \
  --name cm17 \
  --output jsonc

az network watcher connection-monitor test-group list \
  --location westeurope \
  --connection-monitor cm17 \
  --output table

az network watcher connection-monitor test-configuration list \
  --location westeurope \
  --connection-monitor cm17 \
  --output table

# [3] Packet capture to Storage (create -> show -> stop -> delete)
# Creates a short capture on vm17a to sa17flow. No protocol filters.
az network watcher packet-capture create \
  --resource-group NetworkWatcherRG \
  --location westeurope \
  --name pc17-vm17a-cli \
  --vm vm17a \
  --vm-resource-group rg-day17-netwatch \
  --storage-account sa17flow \
  --time-limit 120 \
  --bytes-per-packet 96

az network watcher packet-capture show \
  --resource-group NetworkWatcherRG \
  --location westeurope \
  --name pc17-vm17a-cli \
  --output table

az network watcher packet-capture stop \
  --resource-group NetworkWatcherRG \
  --location westeurope \
  --name pc17-vm17a-cli

az network watcher packet-capture delete \
  --resource-group NetworkWatcherRG \
  --location westeurope \
  --name pc17-vm17a-cli \
  --yes

# [4] Log Analytics queries (replace 559fb329-20f6-4be1-b229-ccffe95a69e6 first)
# 4a) Virtual Network Flow Logs (Traffic Analytics), last 1 hour
az monitor log-analytics query \
  --workspace "559fb329-20f6-4be1-b229-ccffe95a69e6" \
  --analytics-query "NTANetAnalytics | where TimeGenerated > ago(1h) | summarize flows=count() by FlowDirection, L4Protocol, TargetResourceType | top 20 by flows desc" \
  --timespan PT1H \
  --output table

# 4b) Connection Monitor results by test group (success/fail/avg RTT)
az monitor log-analytics query \
  --workspace "559fb329-20f6-4be1-b229-ccffe95a69e6" \
  --analytics-query "NWConnectionMonitorTestResult | where TimeGenerated > ago(1h) | where ConnectionMonitorResourceId has '/cm17' | summarize Success=countif(TestResult=='Succeeded'), Failed=countif(TestResult=='Failed'), AvgRTTms=avg(AvgRoundTripTimeMs) by TestGroupName, bin(TimeGenerated, 5m) | sort by TimeGenerated desc" \
  --timespan PT1H \
  --output table
