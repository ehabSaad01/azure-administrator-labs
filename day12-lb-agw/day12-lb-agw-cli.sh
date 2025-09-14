#!/usr/bin/env bash
set -euo pipefail
# Day12: Azure Load Balancer + Application Gateway (CLI)
# English comments. Long options. Secure-by-default.

# ===== Context =====
SUBSCRIPTION="88b94352-6cdb-4d24-af7a-ec22a366b617"
RG="rg-day12-lb"
LOC="westeurope"
VNET="vnet12weu"
SNET_AGW="snet-agw"
SNET_BE="snet-backend"

# LB
PIP_LB="pip12weu"
LB="lb12weu"
FE_LB="fe-lb12"
BEP_LB="bepool12"
PROBE_LB="hp-http-80"
RULE_LB="lbr-http-80"

# NSG
NSG_BE="nsg-backend12weu"

# App Gateway
AGW="agw12weu"
AGW_PIP="agw-pip12weu"

# Log Analytics
LAW="law12weu"

# ===== Login / Subscription =====
# Ensure correct subscription
az account set --subscription "$SUBSCRIPTION"

# ===== Helper: capture backend private IPs (created in Portal) =====
IP_A="$(az vm show --resource-group "$RG" --name vm12a -d --query privateIps -o tsv)"
IP_B="$(az vm show --resource-group "$RG" --name vm12b -d --query privateIps -o tsv)"

# ===== Load Balancer: ensure probe + rule + pool membership + outbound =====
# Create HTTP probe on /healthz (idempotent-ish)
az network lb probe show --resource-group "$RG" --lb-name "$LB" --name "$PROBE_LB" >/dev/null 2>&1 \
 || az network lb probe create --resource-group "$RG" --lb-name "$LB" \
      --name "$PROBE_LB" --protocol Http --port 80 --path /healthz

# Ensure NICs are in backend pool
for VM in vm12a vm12b; do
  NIC_ID="$(az vm show -g "$RG" -n "$VM" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
  IPCFG="$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].name" -o tsv)"
  az network nic ip-config address-pool add \
    --resource-group "$RG" \
    --nic-name "$(basename "$NIC_ID")" \
    --ip-config-name "$IPCFG" \
    --address-pool "$BEP_LB" \
    --lb-name "$LB" \
    --only-show-errors || true
done

# Fix/ensure LB rule uses backend-port 80 and correct probe
FE_NAME="$(az network lb frontend-ip list -g "$RG" --lb-name "$LB" --query "[0].name" -o tsv)"
az network lb rule show -g "$RG" --lb-name "$LB" -n "$RULE_LB" >/dev/null 2>&1 \
 && az network lb rule update -g "$RG" --lb-name "$LB" -n "$RULE_LB" \
      --protocol Tcp --frontend-ip "$FE_NAME" --frontend-port 80 \
      --backend-pool-name "$BEP_LB" --backend-port 80 \
      --probe "$PROBE_LB" --idle-timeout 4 --enable-tcp-reset true --floating-ip false \
 || az network lb rule create -g "$RG" --lb-name "$LB" -n "$RULE_LB" \
      --protocol Tcp --frontend-ip "$FE_NAME" --frontend-port 80 \
      --backend-pool-name "$BEP_LB" --backend-port 80 \
      --probe "$PROBE_LB" --idle-timeout 4 --enable-tcp-reset true --floating-ip false

# Ensure outbound rule exists (skip if NAT Gateway is used on the subnet)
az network lb outbound-rule show -g "$RG" --lb-name "$LB" -n ob-all >/dev/null 2>&1 \
 || az network lb outbound-rule create -g "$RG" --lb-name "$LB" -n ob-all \
      --address-pool "$BEP_LB" --protocol All --frontend-ip-configs "$FE_NAME"

# ===== NSG: backend subnet rules =====
# Allow LB health probe
az network nsg rule create -g "$RG" --nsg-name "$NSG_BE" --name allow-lb-probe-80 \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes AzureLoadBalancer --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges 80 --only-show-errors || true

# Allow AppGW data path from its subnet to backend port 80
az network vnet subnet show -g "$RG" -n "$SNET_AGW" --vnet-name "$VNET" --query addressPrefix -o tsv >/dev/null
AGW_SUBNET_PREFIX="$(az network vnet subnet show -g "$RG" -n "$SNET_AGW" --vnet-name "$VNET" --query addressPrefix -o tsv)"
az network nsg rule create -g "$RG" --nsg-name "$NSG_BE" --name allow-agw-80 \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$AGW_SUBNET_PREFIX" --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges 80 --only-show-errors || true

# Allow Internet -> backend 80 (needed for LB data path to VMs with no Public IP)
az network nsg rule create -g "$RG" --nsg-name "$NSG_BE" --name allow-lb-data-80 \
  --priority 120 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges 80 --only-show-errors || true

# Associate NSG to backend subnet
NSG_ID="$(az network nsg show -g "$RG" -n "$NSG_BE" --query id -o tsv)"
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SNET_BE" --network-security-group "$NSG_ID" >/dev/null

# ===== Application Gateway: ensure backend pool, probe, http settings, path map =====
# Ensure backend pool with VM private IPs
az network application-gateway address-pool show -g "$RG" --gateway-name "$AGW" -n be-web >/dev/null 2>&1 \
 || az network application-gateway address-pool create -g "$RG" --gateway-name "$AGW" -n be-web \
      --servers "$IP_A" "$IP_B"

# Create/Update custom HTTP probe with explicit Host
az network application-gateway probe show -g "$RG" --gateway-name "$AGW" -n hp-http-80 >/dev/null 2>&1 \
 && az network application-gateway probe update -g "$RG" --gateway-name "$AGW" -n hp-http-80 \
      --protocol Http --port 80 --path /healthz --interval 5 --timeout 5 --threshold 2 --host 127.0.0.1 \
 || az network application-gateway probe create -g "$RG" --gateway-name "$AGW" -n hp-http-80 \
      --protocol Http --port 80 --path /healthz --interval 5 --timeout 5 --threshold 2 --host 127.0.0.1

# Bind probe to first HTTP settings (usually http-80)
HTTPSET="$(az network application-gateway http-settings list -g "$RG" --gateway-name "$AGW" --query "[0].name" -o tsv)"
az network application-gateway http-settings update -g "$RG" --gateway-name "$AGW" -n "$HTTPSET" --probe hp-http-80

# Create URL path map and bind to existing routing rule (convert to PathBased)
az network application-gateway url-path-map show -g "$RG" --gateway-name "$AGW" -n upm-web >/dev/null 2>&1 \
 || az network application-gateway url-path-map create -g "$RG" --gateway-name "$AGW" -n upm-web \
      --rule-name pr-api --paths /api/* --address-pool be-web --http-settings "$HTTPSET" \
      --default-address-pool be-web --default-http-settings "$HTTPSET"

# Find rule name and convert it to PathBasedRouting using the map
RULE_NAME="$(az network application-gateway rule list -g "$RG" --gateway-name "$AGW" --query "[0].name" -o tsv)"
az network application-gateway rule update -g "$RG" --gateway-name "$AGW" -n "$RULE_NAME" \
  --rule-type PathBasedRouting --url-path-map upm-web

# ===== Diagnostics to Log Analytics =====
# Workspace (create if missing)
az monitor log-analytics workspace show -g "$RG" -n "$LAW" >/dev/null 2>&1 \
 || az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOC"
LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"

# LB diagnostics
az monitor diagnostic-settings create \
  --name lb-diag --resource "/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.Network/loadBalancers/$LB" \
  --workspace "$LAW_ID" \
  --logs '[{"category":"LoadBalancerAlertEvent","enabled":true},{"category":"LoadBalancerProbeHealthStatus","enabled":true},{"category":"LoadBalancerRuleCounter","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  --only-show-errors || true

# AppGW diagnostics
az monitor diagnostic-settings create \
  --name agw-diag --resource "/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.Network/applicationGateways/$AGW" \
  --workspace "$LAW_ID" \
  --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayPerformanceLog","enabled":true},{"category":"ApplicationGatewayFirewallLog","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  --only-show-errors || true

# ===== Outputs =====
echo "LB Public IP:  $(az network public-ip show -g "$RG" -n "$PIP_LB" --query ipAddress -o tsv)"
echo "AGW Public IP: $(az network public-ip show -g "$RG" -n "$AGW_PIP" --query ipAddress -o tsv)"
echo "Backend health (AGW):"
az network application-gateway show-backend-health -g "$RG" -n "$AGW" \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{ip:address,health:health}" -o table
