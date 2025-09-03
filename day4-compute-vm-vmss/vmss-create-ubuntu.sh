#!/usr/bin/env bash
set -euo pipefail

# Variables
RESOURCE_GROUP="rg-day4-compute"
LOCATION="westeurope"
VNET_NAME="vnet-day4"
SUBNET_NAME="subnet-vm"

VMSS_NAME="vmss-day4-demo"
VM_SIZE="Standard_B2s"
ADMIN_USER="azureuser"

# Autoscale settings
AS_NAME="autoscale-${VMSS_NAME}"
MIN_COUNT=2
MAX_COUNT=6
DEFAULT_COUNT=2

# 1) Create VMSS (Uniform, Ubuntu 22.04)
az vmss create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VMSS_NAME}" \
  --orchestration-mode "Uniform" \
  --image "Ubuntu2204" \
  --vm-sku "${VM_SIZE}" \
  --instance-count "${DEFAULT_COUNT}" \
  --admin-username "${ADMIN_USER}" \
  --generate-ssh-keys \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --upgrade-policy-mode "automatic"

# 2) Autoscale profile + rules (CPU >70% 5m out, <30% 5m in)
az monitor autoscale create \
  --resource-group "${RESOURCE_GROUP}" \
  --resource "${VMSS_NAME}" \
  --resource-type "Microsoft.Compute/virtualMachineScaleSets" \
  --name "${AS_NAME}" \
  --min-count "${MIN_COUNT}" \
  --max-count "${MAX_COUNT}" \
  --count "${DEFAULT_COUNT}"

az monitor autoscale rule create \
  --resource-group "${RESOURCE_GROUP}" \
  --autoscale-name "${AS_NAME}" \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 1

az monitor autoscale rule create \
  --resource-group "${RESOURCE_GROUP}" \
  --autoscale-name "${AS_NAME}" \
  --condition "Percentage CPU < 30 avg 5m" \
  --scale in 1

# 3) Install NGINX on all instances
INSTANCE_IDS=$(az vmss list-instances \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VMSS_NAME}" \
  --query "[].instanceId" \
  --output tsv)

for ID in ${INSTANCE_IDS}; do
  az vmss run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VMSS_NAME}" \
    --instance-id "${ID}" \
    --command-id "RunShellScript" \
    --scripts "sudo apt-get update -y" \
             "sudo apt-get install -y nginx" \
             "sudo systemctl enable --now nginx"
done

# 4) Load Balancer: probe + rule for port 80
LB_NAME=$(az network lb list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?contains(name,'${VMSS_NAME}')].name | [0]" \
  --output tsv)

az network lb probe create \
  --resource-group "${RESOURCE_GROUP}" \
  --lb-name "${LB_NAME}" \
  --name "http-probe-80" \
  --protocol "Http" \
  --port 80 \
  --request-path "/"

FE_NAME=$(az network lb show --resource-group "${RESOURCE_GROUP}" --name "${LB_NAME}" --query "frontendIpConfigurations[0].name" --output tsv)
BEP_NAME=$(az network lb show --resource-group "${RESOURCE_GROUP}" --name "${LB_NAME}" --query "backendAddressPools[0].name" --output tsv)

az network lb rule create \
  --resource-group "${RESOURCE_GROUP}" \
  --lb-name "${LB_NAME}" \
  --name "http-rule-80" \
  --protocol "Tcp" \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name "${FE_NAME}" \
  --backend-pool-name "${BEP_NAME}" \
  --probe-name "http-probe-80" \
  --idle-timeout 4 \
  --enable-tcp-reset true

# 5) Output Public IP
az network public-ip list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].{name:name,ip:ipAddress}" \
  --output table

echo "Open: http://<PUBLIC_IP_FROM_TABLE>"
