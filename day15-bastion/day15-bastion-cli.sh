#!/usr/bin/env bash
set -euo pipefail
# Day15 — Azure Bastion secure admin path (no Public IP on VMs)
# Re-runnable AZ CLI with long options. English comments only.

SUBSCRIPTION="<your_subscription_id>"
LOC="westeurope"

RG="rg-day15-bastion"
VNET="vnet15weu"
VNET_CIDR="10.15.0.0/16"
SNET_APP="snet-app15"
SNET_APP_CIDR="10.15.1.0/24"
SNET_BAS="AzureBastionSubnet"
SNET_BAS_CIDR="10.15.0.0/26"
NSG_APP="nsg-app15"
PIP_BAST="pip-bast15weu"
BAST="bast15weu"
VM="vm15a"
TAGS="env=lab day=15 owner=ehab"

SSH_PUBKEY_PATH="${HOME}/.ssh/id_rsa.pub"

az account set --subscription "${SUBSCRIPTION}"

az group create --name "${RG}" --location "${LOC}" --tags ${TAGS}

az network vnet create \
  --resource-group "${RG}" --name "${VNET}" --location "${LOC}" \
  --address-prefixes "${VNET_CIDR}" \
  --subnet-name "${SNET_APP}" --subnet-prefixes "${SNET_APP_CIDR}" \
  --tags ${TAGS}

az network vnet subnet create \
  --resource-group "${RG}" --vnet-name "${VNET}" \
  --name "${SNET_BAS}" --address-prefixes "${SNET_BAS_CIDR}"

az network nsg create \
  --resource-group "${RG}" --name "${NSG_APP}" --location "${LOC}" --tags ${TAGS}

az network nsg rule create \
  --resource-group "${RG}" --nsg-name "${NSG_APP}" --name "allow-ssh-from-bastion" \
  --priority 100 --access Allow --direction Inbound --protocol Tcp \
  --source-address-prefixes "${SNET_BAS_CIDR}" --source-port-ranges "*" \
  --destination-address-prefixes "*" --destination-port-ranges 22

az network nsg rule create \
  --resource-group "${RG}" --nsg-name "${NSG_APP}" --name "deny-vnet-inbound" \
  --priority 200 --access Deny --direction Inbound --protocol "*" \
  --source-address-prefixes "VirtualNetwork" --source-port-ranges "*" \
  --destination-address-prefixes "*" --destination-port-ranges "*"

az network vnet subnet update \
  --resource-group "${RG}" --vnet-name "${VNET}" --name "${SNET_APP}" \
  --network-security-group "${NSG_APP}"

az network public-ip create \
  --resource-group "${RG}" --name "${PIP_BAST}" --location "${LOC}" \
  --sku Standard --allocation-method Static --tags ${TAGS}

az network bastion create \
  --resource-group "${RG}" --name "${BAST}" --location "${LOC}" \
  --vnet-name "${VNET}" --public-ip-address "${PIP_BAST}" \
  --sku Basic --tags ${TAGS}

if [[ ! -f "${SSH_PUBKEY_PATH}" ]]; then
  ssh-keygen -t rsa -b 2048 -f "${HOME}/.ssh/id_rsa" -N "" 1>/dev/null
fi

az vm create \
  --resource-group "${RG}" --name "${VM}" --location "${LOC}" \
  --image "Ubuntu2204" --size "Standard_B1s" \
  --admin-username "azureuser" \
  --ssh-key-values "$(cat "${SSH_PUBKEY_PATH}")" \
  --vnet-name "${VNET}" --subnet "${SNET_APP}" \
  --public-ip-address "" --nsg "" \
  --assign-identity \
  --tags ${TAGS}

az vm boot-diagnostics enable --resource-group "${RG}" --name "${VM}"

echo "Done Day15. VM without Public IP. Bastion ready."
