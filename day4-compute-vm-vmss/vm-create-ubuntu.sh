#!/usr/bin/env bash
set -euo pipefail

# Variables
RESOURCE_GROUP="rg-day4-compute"
LOCATION="westeurope"
VNET_NAME="vnet-day4"
VNET_CIDR="10.10.0.0/16"
SUBNET_NAME="subnet-vm"
SUBNET_CIDR="10.10.1.0/24"
VM_NAME="vm-day4-demo"
ADMIN_USER="azureuser"

# Create RG and network
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}"

az network vnet create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VNET_NAME}" \
  --address-prefix "${VNET_CIDR}" \
  --subnet-name "${SUBNET_NAME}" \
  --subnet-prefix "${SUBNET_CIDR}"

# Create VM (Ubuntu 22.04, B2s). SSH only during create.
az vm create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --image "Ubuntu2204" \
  --size "Standard_B2s" \
  --admin-username "${ADMIN_USER}" \
  --generate-ssh-keys \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --public-ip-sku "Standard" \
  --nsg-rule "SSH"

# Open web ports with explicit priorities
az vm open-port --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --port 80  --priority 1001
az vm open-port --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --port 443 --priority 1002

# Optional: install NGINX via RunCommand
az vm run-command invoke \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --command-id "RunShellScript" \
  --scripts "sudo apt-get update -y" "sudo apt-get install -y nginx" "sudo systemctl enable --now nginx"

# Output public IP
az vm list-ip-addresses --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --output table
echo "VM ready. SSH: ssh ${ADMIN_USER}@<PUBLIC_IP>"
