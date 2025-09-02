#!/usr/bin/env bash
set -euo pipefail

# ===== Inputs =====
LOCATION="germanywestcentral"
RG="RG-Networking-Lab-cli"
VNET="vnet-lab-cli"
VNET_CIDR="10.30.0.0/16"

SUBNET_WEB="snet-web-cli"; SUBNET_WEB_CIDR="10.30.1.0/24"
SUBNET_APP="snet-app-cli"; SUBNET_APP_CIDR="10.30.2.0/24"
SUBNET_DB="snet-db-cli";   SUBNET_DB_CIDR="10.30.3.0/24"
SUBNET_BASTION="AzureBastionSubnet"; SUBNET_BASTION_CIDR="10.30.10.0/26"

NSG_WEB="nsg-web-cli"
NSG_APP="nsg-app-cli"
NSG_DB="nsg-db-cli"

PIP_WEB="pip-web-cli"
NIC_WEB="nic-web-cli"
VM_WEB="vm-web-cli"
VM_SIZE="Standard_D2as_v5"   # change if not available
VM_ZONE="2"                  # change if not available

# ===== Provisioning sequence =====
az group create --name "$RG" --location "$LOCATION"

az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --address-prefix "$VNET_CIDR" \
  --subnet-name "$SUBNET_WEB" \
  --subnet-prefix "$SUBNET_WEB_CIDR"

# create other subnets
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SUBNET_APP" --address-prefix "$SUBNET_APP_CIDR"
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SUBNET_DB"  --address-prefix "$SUBNET_DB_CIDR"
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SUBNET_BASTION" --address-prefix "$SUBNET_BASTION_CIDR"

# create NSGs
az network nsg create -g "$RG" -n "$NSG_WEB"
az network nsg create -g "$RG" -n "$NSG_APP"
az network nsg create -g "$RG" -n "$NSG_DB"

# attach NSGs to subnets
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET_WEB" --network-security-group "$NSG_WEB"
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET_APP" --network-security-group "$NSG_APP"
az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET_DB"  --network-security-group "$NSG_DB"

# allow HTTP and HTTPS inbound to web NSG
az network nsg rule create -g "$RG" --nsg-name "$NSG_WEB" -n allow-http \
  --priority 1000 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 80
az network nsg rule create -g "$RG" --nsg-name "$NSG_WEB" -n allow-https \
  --priority 1010 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 443

# note: open SSH only for your own IP if needed
# az network nsg rule create -g "$RG" --nsg-name "$NSG_WEB" -n allow-ssh \
#   --priority 1020 --direction Inbound --access Allow --protocol Tcp \
#   --source-address-prefixes YOUR_IP/32 --destination-port-ranges 22

# create public IP
az network public-ip create -g "$RG" -n "$PIP_WEB" --sku Standard --allocation-method Static

# create NIC and bind public IP
az network nic create -g "$RG" -n "$NIC_WEB" \
  --vnet-name "$VNET" --subnet "$SUBNET_WEB" \
  --public-ip-address "$PIP_WEB"

# create VM with cloud-init (installs nginx)
az vm create \
  --resource-group "$RG" \
  --name "$VM_WEB" \
  --nics "$NIC_WEB" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  --zone "$VM_ZONE" \
  --admin-username azureuser \
  --generate-ssh-keys \
  --custom-data "$(dirname "$0")/cloud-init-nginx.yaml"

# print public IP
az vm list-ip-addresses -g "$RG" -n "$VM_WEB" -o table

