#!/usr/bin/env bash
# File: day18-agw-waf-cli-long.sh
# Purpose: Build an internal-only Application Gateway (WAF_v2) with private frontend, two backend VMs, WAF policy (Prevention), and diagnostics.
# Style: Long options only. No variables. No loops. English comments. Secure-by-default. No Public IPs on VMs.
# NOTE: Replace <your_subscription_id> and <unique> before running.

set -e

# 1) Resource Group
az group create \
  --name rg-day18-agw \
  --location westeurope \
  --subscription <your_subscription_id>

# 2) Virtual Network and Subnets
az network vnet create \
  --resource-group rg-day18-agw \
  --name vnet18weu \
  --location westeurope \
  --address-prefixes 10.18.0.0/16 \
  --subnet-name agwsub18 \
  --subnet-prefixes 10.18.0.0/27

az network vnet subnet create \
  --resource-group rg-day18-agw \
  --vnet-name vnet18weu \
  --name backsub18 \
  --address-prefixes 10.18.2.0/24

az network vnet subnet create \
  --resource-group rg-day18-agw \
  --vnet-name vnet18weu \
  --name AzureBastionSubnet \
  --address-prefixes 10.18.3.0/26

az network vnet subnet create \
  --resource-group rg-day18-agw \
  --vnet-name vnet18weu \
  --name clientsub18 \
  --address-prefixes 10.18.4.0/24

# 3) NSG on backend subnet: allow AGW:80, allow Bastion:22, then deny VNet inbound
az network nsg create \
  --resource-group rg-day18-agw \
  --name nsg18back \
  --location westeurope

az network nsg rule create \
  --resource-group rg-day18-agw \
  --nsg-name nsg18back \
  --name allow-agw-to-backend-80 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.18.0.0/27 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 80

az network nsg rule create \
  --resource-group rg-day18-agw \
  --nsg-name nsg18back \
  --name allow-bastion-ssh-22 \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.18.3.0/26 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22

az network nsg rule create \
  --resource-group rg-day18-agw \
  --nsg-name nsg18back \
  --name deny-vnet-inbound \
  --priority 300 \
  --direction Inbound \
  --access Deny \
  --protocol '*' \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*'

az network vnet subnet update \
  --resource-group rg-day18-agw \
  --vnet-name vnet18weu \
  --name backsub18 \
  --network-security-group nsg18back

# 4) Azure Bastion (only Public IP in the design, for secure administration)
az network public-ip create \
  --resource-group rg-day18-agw \
  --name pip18bas \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

az network bastion create \
  --resource-group rg-day18-agw \
  --name bast18weu \
  --location westeurope \
  --public-ip-address pip18bas \
  --vnet-name vnet18weu

# 5) NICs with static private IPs for the backend VMs
az network nic create \
  --resource-group rg-day18-agw \
  --name nic-vm18a \
  --location westeurope \
  --vnet-name vnet18weu \
  --subnet backsub18 \
  --private-ip-address 10.18.2.10

az network nic create \
  --resource-group rg-day18-agw \
  --name nic-vm18b \
  --location westeurope \
  --vnet-name vnet18weu \
  --subnet backsub18 \
  --private-ip-address 10.18.2.11

# 6) Backend VMs without Public IPs (Ubuntu 22.04 LTS)
az vm create \
  --resource-group rg-day18-agw \
  --name vm18a \
  --location westeurope \
  --zone 1 \
  --nics nic-vm18a \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
  --size Standard_B1ms \
  --authentication-type ssh \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address ""

az vm create \
  --resource-group rg-day18-agw \
  --name vm18b \
  --location westeurope \
  --zone 2 \
  --nics nic-vm18b \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
  --size Standard_B1ms \
  --authentication-type ssh \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address ""

# 7) Install NGINX and /healthz on both VMs (Run Command)
az vm run-command invoke \
  --resource-group rg-day18-agw \
  --name vm18a \
  --command-id RunShellScript \
  --scripts "sudo apt-get update" "sudo apt-get install -y nginx" "echo vm18a | sudo tee /var/www/html/index.html" "echo ok | sudo tee /var/www/html/healthz" "sudo systemctl enable nginx" "sudo systemctl restart nginx"

az vm run-command invoke \
  --resource-group rg-day18-agw \
  --name vm18b \
  --command-id RunShellScript \
  --scripts "sudo apt-get update" "sudo apt-get install -y nginx" "echo vm18b | sudo tee /var/www/html/index.html" "echo ok | sudo tee /var/www/html/healthz" "sudo systemctl enable nginx" "sudo systemctl restart nginx"

# 8) Log Analytics workspace for AGW/WAF logs
az monitor log-analytics workspace create \
  --resource-group rg-day18-agw \
  --workspace-name la18weu \
  --location westeurope \
  --sku PerGB2018

# 9) Storage account for long-term archive (change <unique>)
az storage account create \
  --resource-group rg-day18-agw \
  --name sa18logs<unique> \
  --location westeurope \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

# 10) Application Gateway (WAF_v2) with private frontend (static IP inside agwsub18)
az network application-gateway create \
  --resource-group rg-day18-agw \
  --name agw18weu \
  --location westeurope \
  --sku WAF_v2 \
  --capacity 1 \
  --vnet-name vnet18weu \
  --subnet agwsub18 \
  --private-ip-address 10.18.0.10 \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --routing-rule-type Basic

# 11) Backend pool with VM private IPs
az network application-gateway address-pool create \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name pool18 \
  --servers 10.18.2.10 10.18.2.11

# 12) HTTP settings and custom health probe (/healthz)
az network application-gateway http-settings create \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name httpset18 \
  --port 80 \
  --protocol Http \
  --timeout 30 \
  --cookie-based-affinity Disabled

az network application-gateway probe create \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name probe18 \
  --protocol Http \
  --host 127.0.0.1 \
  --path /healthz \
  --interval 30 \
  --timeout 60 \
  --unhealthy-threshold 3 \
  --port 80

az network application-gateway http-settings update \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name httpset18 \
  --probe probe18

# 13) Listener and routing rule using default frontend IP/port created earlier
az network application-gateway http-listener create \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name lstn18-http \
  --frontend-ip appGatewayFrontendIP \
  --frontend-port appGatewayFrontendPort \
  --protocol Http

az network application-gateway rule create \
  --resource-group rg-day18-agw \
  --gateway-name agw18weu \
  --name rule18 \
  --rule-type Basic \
  --http-listener lstn18-http \
  --address-pool pool18 \
  --http-settings httpset18

# 14) Regional WAF Policy in Prevention mode and attach to AGW
az network application-gateway waf-policy create \
  --resource-group rg-day18-agw \
  --name waf18weu \
  --location westeurope

az network application-gateway waf-policy policy-setting update \
  --resource-group rg-day18-agw \
  --policy-name waf18weu \
  --mode Prevention

az network application-gateway update \
  --resource-group rg-day18-agw \
  --name agw18weu \
  --waf-policy "/subscriptions/<your_subscription_id>/resourceGroups/rg-day18-agw/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/waf18weu"

# 15) Diagnostic settings to Log Analytics and Storage (replace IDs)
# Get resource IDs (run and copy values into the next commands):
#   az resource show --resource-group rg-day18-agw --resource-type Microsoft.Network/applicationGateways --name agw18weu --query id --output tsv
#   az monitor log-analytics workspace show --resource-group rg-day18-agw --workspace-name la18weu --query id --output tsv
#   az storage account show --resource-group rg-day18-agw --name sa18logs<unique> --query id --output tsv

az monitor diagnostic-settings create \
  --name diag-agw18-la \
  --resource "/subscriptions/<your_subscription_id>/resourceGroups/rg-day18-agw/providers/Microsoft.Network/applicationGateways/agw18weu" \
  --workspace "/subscriptions/<your_subscription_id>/resourceGroups/rg-day18-agw/providers/Microsoft.OperationalInsights/workspaces/la18weu" \
  --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayFirewallLog","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

az monitor diagnostic-settings create \
  --name diag-agw18-stor \
  --resource "/subscriptions/<your_subscription_id>/resourceGroups/rg-day18-agw/providers/Microsoft.Network/applicationGateways/agw18weu" \
  --storage-account "/subscriptions/<your_subscription_id>/resourceGroups/rg-day18-agw/providers/Microsoft.Storage/storageAccounts/sa18logs<unique>" \
  --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayFirewallLog","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# 16) Quick checks
az network application-gateway show \
  --resource-group rg-day18-agw \
  --name agw18weu \
  --query "frontendIpConfigurations[0].privateIpAddress" \
  --output tsv

az network application-gateway show-backend-health \
  --resource-group rg-day18-agw \
  --name agw18weu \
  --output table
