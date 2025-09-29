#!/usr/bin/env bash
# Purpose: Provision Day21 lab: RG, LAW, VNet/Subnet+NSG, NAT Gateway, Public LB, VMSS, Custom Script, Autoscale, Diagnostics, NATGW metric alert.
# Notes:
# - Long-form Azure CLI commands. No loops.
# - Safe to run multiple times; resources use fixed names.
# - Region: West Europe.

set -e

# ---[ Resource Group ]---
# Create a logical container for all resources in West Europe.
az group create \
  --name rg-day21-compute \
  --location westeurope

# ---[ Log Analytics Workspace ]---
# Collect logs/metrics (used by the Load Balancer diagnostics).
az monitor log-analytics workspace create \
  --resource-group rg-day21-compute \
  --workspace-name law21weu \
  --location westeurope

# ---[ Virtual Network + Subnet ]---
# Create an isolated network with a single application subnet.
az network vnet create \
  --resource-group rg-day21-compute \
  --name vnet21weu \
  --location westeurope \
  --address-prefixes 10.21.0.0/16 \
  --subnet-name subnet-app21 \
  --subnet-prefixes 10.21.1.0/24

# ---[ NSG + Inbound rule for AzureLoadBalancer on TCP/80 ]---
# Allow only Load Balancer probes/traffic on port 80 toward the subnet.
az network nsg create \
  --resource-group rg-day21-compute \
  --name nsg-subnet-app21 \
  --location westeurope

az network nsg rule create \
  --resource-group rg-day21-compute \
  --nsg-name nsg-subnet-app21 \
  --name AllowAzureLoadBalancerInBound-80 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes AzureLoadBalancer \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 80

az network vnet subnet update \
  --resource-group rg-day21-compute \
  --vnet-name vnet21weu \
  --name subnet-app21 \
  --network-security-group nsg-subnet-app21

# ---[ NAT Gateway + Public IP + Subnet Association ]---
# Provide stable outbound SNAT for all VMs without assigning public IPs per instance.
az network public-ip create \
  --resource-group rg-day21-compute \
  --name pip-nat21weu \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

az network nat gateway create \
  --resource-group rg-day21-compute \
  --name natgw21weu \
  --location westeurope \
  --public-ip-addresses pip-nat21weu \
  --idle-timeout 4 \
  --zones 1 2 3

az network vnet subnet update \
  --resource-group rg-day21-compute \
  --vnet-name vnet21weu \
  --name subnet-app21 \
  --nat-gateway natgw21weu

# ---[ Public Load Balancer ]---
# Expose HTTP/80 through a Standard Public LB with health probe and rule.
az network public-ip create \
  --resource-group rg-day21-compute \
  --name pip-lb21weu \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

az network lb create \
  --resource-group rg-day21-compute \
  --name lb21weu \
  --location westeurope \
  --sku Standard \
  --public-ip-address pip-lb21weu \
  --frontend-ip-name fe-lb21weu \
  --backend-pool-name bepool21

az network lb probe create \
  --resource-group rg-day21-compute \
  --lb-name lb21weu \
  --name hp-tcp-80 \
  --protocol Tcp \
  --port 80 \
  --interval 5 \
  --threshold 2

az network lb rule create \
  --resource-group rg-day21-compute \
  --lb-name lb21weu \
  --name lbr-80 \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name fe-lb21weu \
  --backend-pool-name bepool21 \
  --probe-name hp-tcp-80 \
  --idle-timeout 4 \
  --disable-outbound-snat true \
  --floating-ip false

# ---[ VMSS (Linux/Uniform) ]---
# Create a 2-instance Ubuntu VMSS, no per-VM public IP, joined to the LB backend pool.
az vmss create \
  --resource-group rg-day21-compute \
  --name vmss21weu \
  --location westeurope \
  --orchestration-mode Uniform \
  --image Ubuntu2204 \
  --upgrade-policy-mode Manual \
  --instance-count 2 \
  --vm-sku Standard_B2s \
  --authentication-type ssh \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name vnet21weu \
  --subnet subnet-app21 \
  --public-ip-per-vm false \
  --lb lb21weu \
  --backend-pool-name bepool21

# ---[ Custom Script Extension ]---
# Install Nginx and publish a simple landing page; store command in protected settings only.
az vmss extension set \
  --resource-group rg-day21-compute \
  --vmss-name vmss21weu \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --version 2.1 \
  --protected-settings '{"commandToExecute":"/bin/bash -c \"sudo apt-get update -y && sudo apt-get install -y nginx && echo '\''Day21 VMSS + LB + NATGW Lab'\'' | sudo tee /var/www/html/index.html && sudo systemctl enable --now nginx\""}'

# ---[ Autoscale: CPU-based ]---
# Min=2, Max=5, Default=2, scale out >60% avg 5m, scale in <30% avg 5m, 5m cooldown.
az monitor autoscale create \
  --resource-group rg-day21-compute \
  --name autoscale-vmss21 \
  --resource "$(az vmss show --resource-group rg-day21-compute --name vmss21weu --query id --output tsv)" \
  --min-count 2 \
  --max-count 5 \
  --count 2

az monitor autoscale rule create \
  --resource-group rg-day21-compute \
  --autoscale-name autoscale-vmss21 \
  --condition "Percentage CPU > 60 avg 5m" \
  --scale out 1 \
  --cooldown 5

az monitor autoscale rule create \
  --resource-group rg-day21-compute \
  --autoscale-name autoscale-vmss21 \
  --condition "Percentage CPU < 30 avg 5m" \
  --scale in 1 \
  --cooldown 5

# ---[ Diagnostics for Load Balancer ]---
# Send LB logs and metrics to Log Analytics workspace.
az monitor diagnostic-settings create \
  --name diag-lb21 \
  --resource "$(az network lb show --resource-group rg-day21-compute --name lb21weu --query id --output tsv)" \
  --workspace "$(az monitor log-analytics workspace show --resource-group rg-day21-compute --workspace-name law21weu --query id --output tsv)" \
  --logs '[{"category":"LoadBalancerAlertEvent","enabled":true},{"category":"LoadBalancerProbeHealthStatus","enabled":true},{"category":"LoadBalancerRuleCounter","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'

# ---[ NAT Gateway Metric Alert ]---
# Alert when NAT Gateway SNAT port utilization reaches 80% (visible in Azure Monitor Alerts).
az monitor metrics alert create \
  --resource-group rg-day21-compute \
  --name natgw-snat-util-80 \
  --scopes "$(az network nat gateway show --resource-group rg-day21-compute --name natgw21weu --query id --output tsv)" \
  --description "Alert when NAT GW SNAT port utilization >= 80%" \
  --condition "avg SnatPortUtilization >= 80" \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --severity 2

# ---[ End of script ]---
