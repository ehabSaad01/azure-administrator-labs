#!/usr/bin/env bash
set -e
# English comments: Day16 end-to-end. No variables. Long options only.

# 1) Resource Group
az group create --name rg-day16-vpn --location westeurope

# 2) Core VNet (10.16.0.0/16) + subnets
az network vnet create \
  --resource-group rg-day16-vpn \
  --name vnet16weu \
  --location westeurope \
  --address-prefixes 10.16.0.0/16 \
  --subnet-name snet-app16 \
  --subnet-prefixes 10.16.1.0/24

# GatewaySubnet for core VNet (/27)
az network vnet subnet create \
  --resource-group rg-day16-vpn \
  --vnet-name vnet16weu \
  --name GatewaySubnet \
  --address-prefixes 10.16.255.0/27

# 3) Branch VNet (10.26.0.0/16) + subnets
az network vnet create \
  --resource-group rg-day16-vpn \
  --name vnet-branch16 \
  --location westeurope \
  --address-prefixes 10.26.0.0/16 \
  --subnet-name snet-branch16 \
  --subnet-prefixes 10.26.1.0/24

# GatewaySubnet for branch VNet (/27)
az network vnet subnet create \
  --resource-group rg-day16-vpn \
  --vnet-name vnet-branch16 \
  --name GatewaySubnet \
  --address-prefixes 10.26.255.0/27

# 4) Public IPs for both gateways (Standard, Static)
az network public-ip create \
  --resource-group rg-day16-vpn \
  --name gwpip16 \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

az network public-ip create \
  --resource-group rg-day16-vpn \
  --name gwpip-branch16 \
  --location westeurope \
  --sku Standard \
  --allocation-method Static

# 5) Core VPN Gateway with BGP + P2S basics (IKEv2 + OpenVPN)
# English: Use ASN 65515 for the Azure gateway, client pool 172.16.16.0/24, and enable both protocols.
az network vnet-gateway create \
  --resource-group rg-day16-vpn \
  --name vpngw16 \
  --location westeurope \
  --public-ip-addresses gwpip16 \
  --vnet vnet16weu \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --generation Generation2 \
  --enable-bgp true \
  --asn 65515 \
  --client-protocol IkeV2 OpenVPN \
  --address-prefixes 172.16.16.0/24

# 6) Branch VPN Gateway with BGP (different private ASN)
az network vnet-gateway create \
  --resource-group rg-day16-vpn \
  --name vpngw-branch16 \
  --location westeurope \
  --public-ip-addresses gwpip-branch16 \
  --vnet vnet-branch16 \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --generation Generation2 \
  --enable-bgp true \
  --asn 65020

# 7) VNet-to-VNet connection (Route-based, PSK, BGP enabled)
az network vpn-connection create \
  --resource-group rg-day16-vpn \
  --name conn-vnet16-to-branch16 \
  --vnet-gateway1 vpngw16 \
  --vnet-gateway2 vpngw-branch16 \
  --shared-key "Az@Day16_S2S#2025" \
  --enable-bgp true

# 8) P2S root certificate (upload Base64 public cert data)
# English: Replace <BASE64_ROOT_CERT> with the Base64 contents of Day16-P2S-Root.cer.
az network vnet-gateway root-cert create \
  --resource-group rg-day16-vpn \
  --gateway-name vpngw16 \
  --name day16Root \
  --public-cert-data "<BASE64_ROOT_CERT>"

# 9) P2S: advertise branch route to clients (so P2S can reach 10.26.0.0/16)
az network vnet-gateway update \
  --resource-group rg-day16-vpn \
  --name vpngw16 \
  --custom-routes 10.26.0.0/16 \
  --client-protocol IkeV2 OpenVPN \
  --address-prefixes 172.16.16.0/24

# 10) NSG for app subnet (allow SSH only from P2S pool)
az network nsg create \
  --resource-group rg-day16-vpn \
  --name nsg-app16 \
  --location westeurope

az network nsg rule create \
  --resource-group rg-day16-vpn \
  --nsg-name nsg-app16 \
  --name allow-ssh-p2s \
  --priority 1000 \
  --access Allow \
  --direction Inbound \
  --protocol Tcp \
  --source-address-prefixes 172.16.16.0/24 \
  --source-port-ranges "*" \
  --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges 22

az network vnet subnet update \
  --resource-group rg-day16-vpn \
  --vnet-name vnet16weu \
  --name snet-app16 \
  --network-security-group nsg-app16

# 11) NSG for branch subnet (allow SSH only from P2S pool)
az network nsg create \
  --resource-group rg-day16-vpn \
  --name nsg-branch16 \
  --location westeurope

az network nsg rule create \
  --resource-group rg-day16-vpn \
  --nsg-name nsg-branch16 \
  --name allow-ssh-p2s \
  --priority 1000 \
  --access Allow \
  --direction Inbound \
  --protocol Tcp \
  --source-address-prefixes 172.16.16.0/24 \
  --source-port-ranges "*" \
  --destination-address-prefixes VirtualNetwork \
  --destination-port-ranges 22

az network vnet subnet update \
  --resource-group rg-day16-vpn \
  --vnet-name vnet-branch16 \
  --name snet-branch16 \
  --network-security-group nsg-branch16

# 12) Test VMs (no Public IP)
az vm create \
  --resource-group rg-day16-vpn \
  --name vm16test \
  --location westeurope \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --authentication-type ssh \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name vnet16weu \
  --subnet snet-app16 \
  --public-ip-address ""

az vm create \
  --resource-group rg-day16-vpn \
  --name vmbranch16 \
  --location westeurope \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --authentication-type ssh \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name vnet-branch16 \
  --subnet snet-branch16 \
  --public-ip-address ""

# 13) Generate VPN client packages (download URL printed)
az network vnet-gateway vpn-client generate \
  --resource-group rg-day16-vpn \
  --name vpngw16 \
  --authentication-method EAPTLS \
  --client-protocol IkeV2 \
  --processor-arch Amd64 -o json

az network vnet-gateway vpn-client generate \
  --resource-group rg-day16-vpn \
  --name vpngw16 \
  --authentication-method EAPTLS \
  --client-protocol OpenVPN -o json
