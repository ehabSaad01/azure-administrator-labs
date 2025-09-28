#!/usr/bin/env bash
# Purpose: End-to-end deployment for Azure DNS Private Resolver (secure-by-default).
# Style: Long options only. No variables. No loops. English comments only.
# Prereqs: 'az login' and proper subscription context. Replace <your_subscription_id> and storage name.

set -euo pipefail

# 1) Resource Group
az group create --name rg-day19-fd --location westeurope

# 2) Log Analytics Workspace (30d retention)
az monitor log-analytics workspace create --resource-group rg-day19-fd --workspace-name la19weu --location westeurope --sku PerGB2018 --retention-time 30

# 3) Storage Account for archival (use a globally-unique name)
az storage account create --resource-group rg-day19-fd --name sa19logsx1234567 --location westeurope --sku Standard_LRS --kind StorageV2 --https-only true --min-tls-version TLS1_2 --allow-blob-public-access false
# Lock down network: deny by default, allow trusted Azure services
az storage account update --resource-group rg-day19-fd --name sa19logsx1234567 --default-action Deny --bypass AzureServices
# Blob safety: versioning + soft delete (14d)
az storage account blob-service-properties update --resource-group rg-day19-fd --account-name sa19logsx1234567 --enable-versioning true --enable-delete-retention true --delete-retention-days 14

# 4) Virtual Network and subnets
az network vnet create --resource-group rg-day19-fd --name vnet19weu --location westeurope --address-prefixes 10.19.0.0/24 --subnet-name snet-pdr-inbound --subnet-prefixes 10.19.0.0/28
az network vnet subnet update --resource-group rg-day19-fd --vnet-name vnet19weu --name snet-pdr-inbound --delegations Microsoft.Network/dnsResolvers
az network vnet subnet create --resource-group rg-day19-fd --vnet-name vnet19weu --name snet-pdr-outbound --address-prefixes 10.19.0.16/28 --delegations Microsoft.Network/dnsResolvers
az network vnet subnet create --resource-group rg-day19-fd --vnet-name vnet19weu --name snet-workload --address-prefixes 10.19.0.64/26

# 5) Private DNS Resolver (core)
az network dns-resolver create --resource-group rg-day19-fd --name pdr19weu --location westeurope --virtual-network "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu"
az network dns-resolver inbound-endpoint create --resource-group rg-day19-fd --dns-resolver-name pdr19weu --name inep19weu --location westeurope --ip-configurations '[{"name":"ipconfig1","private-ip-allocation-method":"Dynamic","subnet":{"id":"/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu/subnets/snet-pdr-inbound"}}]'
az network dns-resolver outbound-endpoint create --resource-group rg-day19-fd --dns-resolver-name pdr19weu --name outep19weu --location westeurope --subnet "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu/subnets/snet-pdr-outbound"

# 6) Forwarding Ruleset + sample rule + VNet link
az network dns-resolver forwarding-ruleset create --resource-group rg-day19-fd --name drs19weu --location westeurope --outbound-endpoints "[{\"id\":\"/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/dnsResolvers/pdr19weu/outboundEndpoints/outep19weu\"}]"
az network dns-resolver forwarding-rule create --resource-group rg-day19-fd --ruleset-name drs19weu --name fr-microsoft --domain-name "microsoft.com." --forwarding-rule-state Enabled --target-dns-servers ip=1.1.1.1 port=53 ip=8.8.8.8 port=53
az network dns-resolver forwarding-ruleset vnet-link create --resource-group rg-day19-fd --ruleset-name drs19weu --name drs19weu-vnet19weu-link --virtual-network "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu"

# 7) Private DNS zone + link + test record
az network private-dns zone create --resource-group rg-day19-fd --name priv19.local
az network private-dns link vnet create --resource-group rg-day19-fd --zone-name priv19.local --name vnet19weu-link --virtual-network "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu" --registration-enabled false
az network private-dns record-set a add-record --resource-group rg-day19-fd --zone-name priv19.local --record-set-name app1 --ipv4-address 10.19.0.100

# 8) Test VM without Public IP
az vm create --resource-group rg-day19-fd --name vm19u1 --location westeurope --image Ubuntu2204 --size Standard_B2s --admin-username ehabadmin --generate-ssh-keys --vnet-name vnet19weu --subnet snet-workload --public-ip-address ""

# 9) DNS Security Policy + Diagnostics (DNSQueryLogs)
az network dns-resolver policy create --resource-group rg-day19-fd --dns-resolver-policy-name secp19weu --location westeurope
az network dns-resolver policy vnet-link create --resource-group rg-day19-fd --policy-name secp19weu --name secp19weu-vnet19weu-link --virtual-network "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/virtualNetworks/vnet19weu"
az monitor diagnostic-settings create --name diag-secp19weu --resource "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Network/dnsResolverPolicies/secp19weu" --workspace "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.OperationalInsights/workspaces/la19weu" --storage-account "/subscriptions/<your_subscription_id>/resourceGroups/rg-day19-fd/providers/Microsoft.Storage/storageAccounts/sa19logsx1234567" --logs '[{"category":"DnsResponse","enabled":true,"retentionPolicy":{"enabled":false,"days":0}}]'

# End
