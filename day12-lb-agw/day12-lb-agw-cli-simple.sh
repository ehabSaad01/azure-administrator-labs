#!/usr/bin/env bash
# Day12 — Simple Azure CLI script (long options)

az account set --subscription 88b94352-6cdb-4d24-af7a-ec22a366b617

NIC_ID_VM12A=$(az vm show --resource-group rg-day12-lb --name vm12a --query "networkProfile.networkInterfaces[0].id" --output tsv)
NIC_NAME_VM12A=$(az network nic show --ids "$NIC_ID_VM12A" --query "name" --output tsv)
IPCFG_VM12A=$(az network nic show --ids "$NIC_ID_VM12A" --query "ipConfigurations[0].name" --output tsv)

NIC_ID_VM12B=$(az vm show --resource-group rg-day12-lb --name vm12b --query "networkProfile.networkInterfaces[0].id" --output tsv)
NIC_NAME_VM12B=$(az network nic show --ids "$NIC_ID_VM12B" --query "name" --output tsv)
IPCFG_VM12B=$(az network nic show --ids "$NIC_ID_VM12B" --query "ipConfigurations[0].name" --output tsv)

az network nic ip-config address-pool add --resource-group rg-day12-lb --nic-name "$NIC_NAME_VM12A" --ip-config-name "$IPCFG_VM12A" --lb-name lb12weu --address-pool bepool12
az network nic ip-config address-pool add --resource-group rg-day12-lb --nic-name "$NIC_NAME_VM12B" --ip-config-name "$IPCFG_VM12B" --lb-name lb12weu --address-pool bepool12

az network lb probe create --resource-group rg-day12-lb --lb-name lb12weu --name hp-http-80 --protocol Http --port 80 --path /healthz

FE_NAME=$(az network lb frontend-ip list --resource-group rg-day12-lb --lb-name lb12weu --query "[0].name" --output tsv)
az network lb rule create --resource-group rg-day12-lb --lb-name lb12weu --name lbr-http-80 --protocol Tcp --frontend-ip "$FE_NAME" --frontend-port 80 --backend-pool-name bepool12 --backend-port 80 --probe hp-http-80 --idle-timeout 4 --enable-tcp-reset true --floating-ip false
az network lb outbound-rule create --resource-group rg-day12-lb --lb-name lb12weu --name ob-all --address-pool bepool12 --protocol All --frontend-ip-configs "$FE_NAME"

AGW_SUBNET_PREFIX=$(az network vnet subnet show --resource-group rg-day12-lb --vnet-name vnet12weu --name snet-agw --query "addressPrefix" --output tsv)
az network nsg rule create --resource-group rg-day12-lb --nsg-name nsg-backend12weu --name allow-lb-probe-80 --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes AzureLoadBalancer --destination-address-prefixes VirtualNetwork --destination-port-ranges 80
az network nsg rule create --resource-group rg-day12-lb --nsg-name nsg-backend12weu --name allow-agw-80 --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "$AGW_SUBNET_PREFIX" --destination-address-prefixes VirtualNetwork --destination-port-ranges 80
az network nsg rule create --resource-group rg-day12-lb --nsg-name nsg-backend12weu --name allow-lb-data-80 --priority 120 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --destination-address-prefixes VirtualNetwork --destination-port-ranges 80

IP_VM12A=$(az vm show --resource-group rg-day12-lb --name vm12a --show-details --query "privateIps" --output tsv)
IP_VM12B=$(az vm show --resource-group rg-day12-lb --name vm12b --show-details --query "privateIps" --output tsv)
az network application-gateway address-pool create --resource-group rg-day12-lb --gateway-name agw12weu --name be-web
az network application-gateway address-pool update --resource-group rg-day12-lb --gateway-name agw12weu --name be-web --servers "$IP_VM12A" "$IP_VM12B"

az network application-gateway probe create --resource-group rg-day12-lb --gateway-name agw12weu --name hp-http-80 --protocol Http --host 127.0.0.1 --path /healthz --interval 5 --timeout 5 --threshold 2 --port 80
HTTPSET_NAME=$(az network application-gateway http-settings list --resource-group rg-day12-lb --gateway-name agw12weu --query "[0].name" --output tsv)
az network application-gateway http-settings update --resource-group rg-day12-lb --gateway-name agw12weu --name "$HTTPSET_NAME" --probe hp-http-80

az network application-gateway url-path-map create --resource-group rg-day12-lb --gateway-name agw12weu --name upm-web --rule-name pr-api --paths /api/* --address-pool be-web --http-settings "$HTTPSET_NAME" --default-address-pool be-web --default-http-settings "$HTTPSET_NAME"
RULE_NAME=$(az network application-gateway rule list --resource-group rg-day12-lb --gateway-name agw12weu --query "[0].name" --output tsv)
az network application-gateway rule update --resource-group rg-day12-lb --gateway-name agw12weu --name "$RULE_NAME" --rule-type PathBasedRouting --url-path-map upm-web

LAW_ID=$(az monitor log-analytics workspace show --resource-group rg-day12-lb --workspace-name law12weu --query "id" --output tsv)
az monitor diagnostic-settings create --name lb-diag --resource "/subscriptions/88b94352-6cdb-4d24-af7a-ec22a366b617/resourceGroups/rg-day12-lb/providers/Microsoft.Network/loadBalancers/lb12weu" --workspace "$LAW_ID" --logs '[{"category":"LoadBalancerAlertEvent","enabled":true},{"category":"LoadBalancerProbeHealthStatus","enabled":true},{"category":"LoadBalancerRuleCounter","enabled":true}]' --metrics '[{"category":"AllMetrics","enabled":true}]'
az monitor diagnostic-settings create --name agw-diag --resource "/subscriptions/88b94352-6cdb-4d24-af7a-ec22a366b617/resourceGroups/rg-day12-lb/providers/Microsoft.Network/applicationGateways/agw12weu" --workspace "$LAW_ID" --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayPerformanceLog","enabled":true},{"category":"ApplicationGatewayFirewallLog","enabled":true}]' --metrics '[{"category":"AllMetrics","enabled":true}]'

echo "LB Public IP:" && az network public-ip show --resource-group rg-day12-lb --name pip12weu --query "ipAddress" --output tsv
echo "AGW Public IP:" && az network public-ip show --resource-group rg-day12-lb --name agw-pip12weu --query "ipAddress" --output tsv
az network application-gateway show-backend-health --resource-group rg-day12-lb --name agw12weu --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{ip:address,health:health}" --output table
