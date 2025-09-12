#!/usr/bin/env bash
set -euo pipefail

# =========================
# Day11 Monitoring — CLI
# Long options + idempotent
# =========================
# Prereqs: az login already done.

# -------- Variables --------
SUBSCRIPTION="${SUBSCRIPTION:-<your_subscription_id>}"
RG="${RG:-rg-day11-monitor}"
LOC="${LOC:-westeurope}"
LA="${LA:-la11weu}"
AG="${AG:-ag11weu}"
EMAIL="${EMAIL:-<your_email@example.com>}"   # Required for Action Group email channel
VM_ID="${VM_ID:-}"                           # Optional: VM resource ID for CPU alert

# -------- Helpers --------
log(){ printf "[%s] %s\n" "$(date -u +%H:%M:%S)" "$*"; }

# -------- Bootstrap --------
log "Setting subscription"
az account set --subscription "${SUBSCRIPTION}"

log "Ensuring resource group"
az group create --name "${RG}" --location "${LOC}" --output table >/dev/null

# -------- Log Analytics Workspace --------
log "Creating Log Analytics workspace: ${LA}"
az monitor log-analytics workspace create \
  --resource-group "${RG}" \
  --workspace-name "${LA}" \
  --location "${LOC}" \
  --output table >/dev/null || true

log "Setting retention to 30 days"
az monitor log-analytics workspace update \
  --resource-group "${RG}" \
  --workspace-name "${LA}" \
  --retention-time 30 \
  --output table >/dev/null

LA_ID="$(az monitor log-analytics workspace show -g "${RG}" -w "${LA}" --query id -o tsv)"
log "LA_ID=${LA_ID}"

# -------- Action Group (email) --------
log "Creating Action Group: ${AG}"
az monitor action-group create \
  --resource-group "${RG}" \
  --name "${AG}" \
  --short-name "${AG}" \
  --action "Primary" email "${EMAIL}" \
  --output table >/dev/null

AG_ID="$(az monitor action-group show -g "${RG}" -n "${AG}" --query id -o tsv)"
log "AG_ID=${AG_ID}"

# -------- Export Activity Log to LA (subscription-level Diagnostic setting) --------
SUB_ID="$(az account show --query id -o tsv)"
SUB_SCOPE="/subscriptions/${SUB_ID}"

log "Creating subscription-level Diagnostic setting to export Activity Log to ${LA}"
az monitor diagnostic-settings create \
  --name "ds-activity-to-${LA}" \
  --resource "${SUB_SCOPE}" \
  --workspace "${LA_ID}" \
  --logs '[{"category":"Administrative","enabled":true},{"category":"Policy","enabled":true},{"category":"Security","enabled":true},{"category":"ServiceHealth","enabled":true},{"category":"ResourceHealth","enabled":true},{"category":"Autoscale","enabled":true},{"category":"Recommendation","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  --output none || true

# -------- Metric Alert on VM CPU --------
if [[ -n "${VM_ID}" ]]; then
  log "Creating Metric Alert: Percentage CPU > 75 for 5m"
  az monitor metrics alert create \
    --name "vm-cpu-gt75m5" \
    --resource-group "${RG}" \
    --scopes "${VM_ID}" \
    --condition "avg Percentage CPU > 75" \
    --description "VM CPU > 75% for 5 minutes" \
    --evaluation-frequency 5m \
    --window-size 5m \
    --severity 3 \
    --action-group "${AG_ID}" \
    --output table >/dev/null
else
  log "Skipping CPU metric alert because VM_ID is empty. Export VM_ID='</subscriptions/.../resourceGroups/.../providers/Microsoft.Compute/virtualMachines/NAME>' to enable."
fi

# -------- Activity Log Alert: Resource Group delete --------
log "Creating Activity Log Alert for RG delete"
az monitor activity-log alert create \
  --name "activity-rg-delete" \
  --resource-group "${RG}" \
  --scopes "${SUB_SCOPE}" \
  --condition "category=Administrative and operationName=Microsoft.Resources/subscriptions/resourceGroups/delete" \
  --action-group "${AG_ID}" \
  --output table >/dev/null || true

# -------- Scheduled Query Alert: Heartbeat missing --------
log "Creating Scheduled Query Alert: Heartbeat missing >10m"
QUERY='Heartbeat
| summarize LastBeat = max(TimeGenerated) by Computer
| where LastBeat < ago(10m)'

az monitor scheduled-query create \
  --name "log-hb-missing-10m" \
  --resource-group "${RG}" \
  --scopes "${LA_ID}" \
  --description "Heartbeat missing >10m" \
  --condition "query=\"$QUERY\" time-aggregation=Count operator=GreaterThan threshold=0" \
  --evaluation-frequency 5m \
  --window-size 10m \
  --severity 3 \
  --action-groups "${AG_ID}" \
  --output table >/dev/null || true

log "Done."
