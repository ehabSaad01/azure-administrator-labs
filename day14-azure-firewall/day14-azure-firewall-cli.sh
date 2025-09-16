#!/usr/bin/env bash
set -e
# Day14 — Azure Firewall (SNAT + DNAT) — Minimal az CLI
az config set extension.use_dynamic_install=yes_without_prompt

echo "[1/12] RG"
az group create --name rg-day14-firewall --location westeurope

echo "[2/12] VNet + subnets"
az network vnet create --resource-group rg-day14-firewall --name vnet14weu --location westeurope --address-prefixes 10.14.0.0/16 --subnet-name placeholder-subnet --subnet-prefixes 10.14.255.0/24
az network vnet subnet create --resource-group rg-day14-firewall --vnet-name vnet14weu --name AzureFirewallSubnet --address-prefixes 10.14.0.0/26
az network vnet subnet create --resource-group rg-day14-firewall --vnet-name vnet14weu --name snet-backend14 --address-prefixes 10.14.1.0/24
az network vnet subnet delete --resource-group rg-day14-firewall --vnet-name vnet14weu --name placeholder-subnet

echo "[3/12] LAW"
az monitor log-analytics workspace create --resource-group rg-day14-firewall --workspace-name law14weu --location westeurope

echo "[4/12] PIP"
az network public-ip create --resource-group rg-day14-firewall --name pip-afw14 --location westeurope --sku Standard --version IPv4 --allocation-method Static

echo "[5/12] Policy"
az network firewall policy create --resource-group rg-day14-firewall --name afwpol14 --location westeurope --tier Standard --threat-intel-mode Alert

echo "[6/12] Firewall"
az network firewall create --resource-group rg-day14-firewall --name afw14weu --location westeurope --sku AZFW_VNet --tier Standard
az network firewall ip-config create --resource-group rg-day14-firewall --firewall-name afw14weu --name afw-ipconfig --public-ip-address pip-afw14 --vnet-name vnet14weu
az network firewall update --resource-group rg-day14-firewall --name afw14weu --firewall-policy "$(az network firewall policy show --resource-group rg-day14-firewall --name afwpol14 --query id --output tsv)"
AFW_PRIV_IP_cli="$(az network firewall show --resource-group rg-day14-firewall --name afw14weu --query "ipConfigurations[0].privateIpAddress" --output tsv)"; echo "[Info] FW private IP=${AFW_PRIV_IP_cli}"

echo "[7/12] Route"
az network route-table create --resource-group rg-day14-firewall --name rt-backend14 --location westeurope
az network route-table route create --resource-group rg-day14-firewall --route-table-name rt-backend14 --name default-to-afw --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address "${AFW_PRIV_IP_cli}"

echo "[8/12] NSG"
az network nsg create --resource-group rg-day14-firewall --name nsg-backend14 --location westeurope
az network nsg rule create --resource-group rg-day14-firewall --nsg-name nsg-backend14 --name allow-ssh-from-internet-test --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --source-port-ranges "*" --destination-address-prefixes 10.14.1.0/24 --destination-port-ranges 22
az network vnet subnet update --resource-group rg-day14-firewall --vnet-name vnet14weu --name snet-backend14 --network-security-group nsg-backend14 --route-table rt-backend14

echo "[9/12] VM"
az network nic create --resource-group rg-day14-firewall --name nic-vm14a --vnet-name vnet14weu --subnet snet-backend14
az vm create --resource-group rg-day14-firewall --name vm14a --location westeurope --nics nic-vm14a --image Ubuntu2204 --size Standard_B2s --admin-username azureuser --authentication-type ssh --generate-ssh-keys
VM14A_PRIV_IP_cli="$(az vm show --resource-group rg-day14-firewall --name vm14a --show-details --query privateIps --output tsv)"; echo "[Info] VM private IP=${VM14A_PRIV_IP_cli}"

echo "[10/12] RCG"
az network firewall policy rule-collection-group create --resource-group rg-day14-firewall --policy-name afwpol14 --name rcg-main --priority 100

echo "[11/12] Rules DNS/Web"
az network firewall policy rule-collection-group collection add --resource-group rg-day14-firewall --policy-name afwpol14 --rcg-name rcg-main --name rc-allow-dns --collection-priority 200 --action Allow --rule-type NetworkRule --rule-name dns-any --description "Allow DNS" --source-addresses 10.14.1.0/24 --destination-addresses "*" --destination-ports 53 --ip-protocols TCP UDP
az network firewall policy rule-collection-group collection add --resource-group rg-day14-firewall --policy-name afwpol14 --rcg-name rcg-main --name rc-allow-web --collection-priority 300 --action Allow --rule-type ApplicationRule --rule-name web-allowed --description "Allow Web" --source-addresses 10.14.1.0/24 --protocols Http=80 Https=443 --target-fqdns ifconfig.io aka.ms microsoft.com ubuntu.com github.com

echo "[12/12] DNAT"
PIP_AFW14_cli="$(az network public-ip show --resource-group rg-day14-firewall --name pip-afw14 --query ipAddress --output tsv)"; echo "[Info] FW Public IP=${PIP_AFW14_cli}"
az network firewall policy rule-collection-group collection add --resource-group rg-day14-firewall --policy-name afwpol14 --rcg-name rcg-main --name rc-dnat-admin --collection-priority 100 --action Dnat --rule-type NatRule --rule-name ssh-to-vm14a --description "DNAT SSH" --source-addresses "*" --destination-addresses "${PIP_AFW14_cli}" --destination-ports 22 --translated-address "${VM14A_PRIV_IP_cli}" --translated-port 22 --ip-protocols TCP

echo "DONE"
