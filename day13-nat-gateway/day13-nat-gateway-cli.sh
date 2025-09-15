#!/usr/bin/env bash
set -e

# Day13 — NAT Gateway (CLI, long options, no loops, no shorthand)
# Notes:
# - Replace <your_subscription_id> below.
# - Resource names and CIDRs are hardcoded for clarity.
# - Re-run specific lines if a create fails because the resource already exists.

# 0) Subscription
az account set --subscription "<your_subscription_id>"

# 1) Resource Group
# Logical container for access control, billing, and cleanup.
az group create --name "rg-day13-nat" --location "westeurope" --only-show-errors

# 2) Virtual Network + Subnet (backend)
# Private address space for workloads; subnet to later attach NSG and NAT Gateway.
az network vnet create \
  --resource-group "rg-day13-nat" \
  --name "vnet13weu" \
  --location "westeurope" \
  --address-prefixes "10.13.0.0/16" \
  --subnet-name "snet-backend13" \
  --subnet-prefixes "10.13.1.0/24" \
  --only-show-errors

# 3) Network Security Group
# Secure-by-default: allow DNS + 80/443; then deny other Internet egress.
az network nsg create --resource-group "rg-day13-nat" --name "nsg-backend13" --location "westeurope" --only-show-errors

# 3a) Allow DNS (Azure DNS 168.63.129.16:53)
az network nsg rule create \
  --resource-group "rg-day13-nat" \
  --nsg-name "nsg-backend13" \
  --name "Allow-DNS-Azure" \
  --priority 200 \
  --direction "Outbound" \
  --access "Allow" \
  --protocol "*" \
  --source-address-prefixes "VirtualNetwork" \
  --source-port-ranges "*" \
  --destination-address-prefixes "168.63.129.16" \
  --destination-port-ranges "53" \
  --only-show-errors

# 3b) Allow HTTP/HTTPS to Internet
az network nsg rule create \
  --resource-group "rg-day13-nat" \
  --nsg-name "nsg-backend13" \
  --name "Allow-HTTP-HTTPS" \
  --priority 210 \
  --direction "Outbound" \
  --access "Allow" \
  --protocol "Tcp" \
  --source-address-prefixes "VirtualNetwork" \
  --source-port-ranges "*" \
  --destination-address-prefixes "Internet" \
  --destination-port-ranges "80" "443" \
  --only-show-errors

# 3c) Deny all other Internet egress
az network nsg rule create \
  --resource-group "rg-day13-nat" \
  --nsg-name "nsg-backend13" \
  --name "Deny-Internet-All" \
  --priority 4096 \
  --direction "Outbound" \
  --access "Deny" \
  --protocol "*" \
  --source-address-prefixes "VirtualNetwork" \
  --source-port-ranges "*" \
  --destination-address-prefixes "Internet" \
  --destination-port-ranges "*" \
  --only-show-errors

# 3d) Attach NSG to backend subnet
az network vnet subnet update \
  --resource-group "rg-day13-nat" \
  --vnet-name "vnet13weu" \
  --name "snet-backend13" \
  --network-security-group "nsg-backend13" \
  --only-show-errors

# 4) Public IP for NAT (stable outbound identity; 64K SNAT ports)
az network public-ip create \
  --resource-group "rg-day13-nat" \
  --name "pip13weu" \
  --location "westeurope" \
  --sku "Standard" \
  --allocation-method "Static" \
  --version "IPv4" \
  --only-show-errors

# 5) NAT Gateway (egress only: SNAT/PAT) and bind the PIP
az network nat gateway create \
  --resource-group "rg-day13-nat" \
  --name "natg13weu" \
  --location "westeurope" \
  --sku "Standard" \
  --public-ip-addresses "pip13weu" \
  --only-show-errors

# 5a) Associate NAT Gateway to backend subnet
az network vnet subnet update \
  --resource-group "rg-day13-nat" \
  --vnet-name "vnet13weu" \
  --name "snet-backend13" \
  --nat-gateway "natg13weu" \
  --only-show-errors

# 6) Bastion (optional, for admin access without VM public ports)
# 6a) Create AzureBastionSubnet
az network vnet subnet create \
  --resource-group "rg-day13-nat" \
  --vnet-name "vnet13weu" \
  --name "AzureBastionSubnet" \
  --address-prefixes "10.13.100.0/26" \
  --only-show-errors

# 6b) Public IP for Bastion
az network public-ip create \
  --resource-group "rg-day13-nat" \
  --name "pip-bast13weu" \
  --location "westeurope" \
  --sku "Standard" \
  --allocation-method "Static" \
  --version "IPv4" \
  --only-show-errors

# 6c) Bastion host
az network bastion create \
  --resource-group "rg-day13-nat" \
  --name "bast13weu" \
  --location "westeurope" \
  --public-ip-address "pip-bast13weu" \
  --vnet-name "vnet13weu" \
  --only-show-errors

# 7) Test VM (no Public IP on NIC) — egress must go via NAT Gateway
az vm create \
  --resource-group "rg-day13-nat" \
  --name "vm13a" \
  --image "Ubuntu2204" \
  --size "Standard_B1s" \
  --authentication-type "ssh" \
  --generate-ssh-keys \
  --admin-username "azureuser" \
  --vnet-name "vnet13weu" \
  --subnet "snet-backend13" \
  --nsg "" \
  --public-ip-address "" \
  --only-show-errors

echo "CLI file ready. Later validate from vm13a: curl -s https://ifconfig.me (should show pip13weu)."
