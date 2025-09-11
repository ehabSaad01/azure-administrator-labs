#!/usr/bin/env bash
set -euo pipefail

# =======================
# Day10 — Identity & Governance (CLI)
# Secure-by-default. Long options.
# NOTE: Some data-plane actions (Key Vault secrets, Storage blobs) are skipped
#       because Public network access is Disabled. Use VM + MI for data-plane.
# =======================

# -------- Variables --------
SUBSCRIPTION="${SUBSCRIPTION:-<your_subscription_id>}"
LOC="${LOC:-westeurope}"

# Name suffix to avoid collisions with soft-deleted names
SUFFIX="${SUFFIX:-$(date +%Y%m%d%H%M)}"

RG="rg-day10-iam-gov"
VNET="vnetday10weu"
SNET_PE="snet-pe"
SNET_VM="snet-vm"
KV="kvday10weu${SUFFIX}"
SA="saday10weu${SUFFIX}"
VM="vmday10weu"
LA="laday10weu${SUFFIX}"
PE_KV="pe-kv-day10"
PE_SA="pe-sa-day10"

# -------- Select subscription --------
echo "[select] subscription"
az account set --subscription "$SUBSCRIPTION"

# -------- Resource Group --------
echo "[create] resource group"
az group create \
  --name "$RG" \
  --location "$LOC" \
  --tags env=lab owner=day10

# -------- Policy: Allowed locations --------
echo "[policy] assign 'Allowed locations' at RG scope"
ALLOWED_LOC_DEF=$(az policy definition list \
  --query "[?displayName=='Allowed locations'].name" -o tsv | head -n1)
az policy assignment create \
  --name pa-day10-allowed-locs \
  --display-name "Day10 Allowed locations" \
  --scope "$(az group show --name "$RG" --query id -o tsv)" \
  --policy "$ALLOWED_LOC_DEF" \
  --params "{\"listOfAllowedLocations\": {\"value\": [\"$LOC\"]}}"

# -------- Policy: Require tag env=lab --------
echo "[policy] require tag env=lab"
REQUIRE_TAG_DEF=$(az policy definition list \
  --query "[?displayName=='Require a tag and its value on resources'].name" -o tsv | head -n1)
az policy assignment create \
  --name pa-day10-require-tag-env \
  --display-name "Day10 Require tag env" \
  --scope "$(az group show --name "$RG" --query id -o tsv)" \
  --policy "$REQUIRE_TAG_DEF" \
  --params "{\"tagName\":{\"value\":\"env\"},\"tagValue\":{\"value\":\"lab\"}}"

# -------- Policy: Require tag owner=day10 --------
echo "[policy] require tag owner=day10"
az policy assignment create \
  --name pa-day10-require-tag-owner \
  --display-name "Day10 Require tag owner" \
  --scope "$(az group show --name "$RG" --query id -o tsv)" \
  --policy "$REQUIRE_TAG_DEF" \
  --params "{\"tagName\":{\"value\":\"owner\"},\"tagValue\":{\"value\":\"day10\"}}"

# -------- VNet + Subnets --------
echo "[network] vnet and subnets"
az network vnet create \
  --name "$VNET" \
  --resource-group "$RG" \
  --location "$LOC" \
  --address-prefixes 10.20.0.0/16 \
  --subnet-name "$SNET_PE" \
  --subnet-prefixes 10.20.0.0/24 \
  --tags env=lab owner=day10

az network vnet subnet create \
  --name "$SNET_VM" \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --address-prefixes 10.20.1.0/24

# -------- Key Vault (RBAC, PNA Disabled) --------
echo "[keyvault] create RBAC-only with public access disabled"
az keyvault create \
  --name "$KV" \
  --resource-group "$RG" \
  --location "$LOC" \
  --enable-rbac-authorization true \
  --enable-purge-protection true \
  --retention-days 90 \
  --public-network-access Disabled \
  --sku standard \
  --tags env=lab owner=day10

# -------- Storage Account (keyless, PNA Disabled) --------
echo "[storage] create secure storage account"
az storage account create \
  --name "$SA" \
  --resource-group "$RG" \
  --location "$LOC" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-shared-key-access false \
  --min-tls-version TLS1_2 \
  --public-network-access Disabled \
  --https-only true \
  --tags env=lab owner=day10

# -------- Private DNS zones --------
echo "[dns] private dns zones and links"
KV_ZONE="privatelink.vaultcore.azure.net"
BLOB_ZONE="privatelink.blob.core.windows.net"

az network private-dns zone create \
  --resource-group "$RG" \
  --name "$KV_ZONE"

az network private-dns zone create \
  --resource-group "$RG" \
  --name "$BLOB_ZONE"

az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "$KV_ZONE" \
  --name link-kv-zone \
  --virtual-network "$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)" \
  --registration-enabled false

az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "$BLOB_ZONE" \
  --name link-blob-zone \
  --virtual-network "$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)" \
  --registration-enabled false

# -------- Private Endpoint for Key Vault --------
echo "[pe] key vault private endpoint"
KV_ID=$(az keyvault show --name "$KV" --query id -o tsv)
az network private-endpoint create \
  --name "$PE_KV" \
  --resource-group "$RG" \
  --location "$LOC" \
  --vnet-name "$VNET" \
  --subnet "$SNET_PE" \
  --private-connection-resource-id "$KV_ID" \
  --group-ids vault \
  --connection-name "pec-kv-day10" \
  --tags env=lab owner=day10

az network private-endpoint dns-zone-group create \
  --resource-group "$RG" \
  --endpoint-name "$PE_KV" \
  --name "zg-kv" \
  --private-dns-zone "$KV_ZONE"

# -------- Private Endpoint for Storage (blob) --------
echo "[pe] storage blob private endpoint"
SA_ID=$(az storage account show --name "$SA" --resource-group "$RG" --query id -o tsv)
az network private-endpoint create \
  --name "$PE_SA" \
  --resource-group "$RG" \
  --location "$LOC" \
  --vnet-name "$VNET" \
  --subnet "$SNET_PE" \
  --private-connection-resource-id "$SA_ID" \
  --group-ids blob \
  --connection-name "pec-sa-day10" \
  --tags env=lab owner=day10

az network private-endpoint dns-zone-group create \
  --resource-group "$RG" \
  --endpoint-name "$PE_SA" \
  --name "zg-sa" \
  --private-dns-zone "$BLOB_ZONE"

# -------- VM with System-assigned MI and no Public IP --------
echo "[vm] create VM with system-assigned identity and no public ip"
ADMIN="${ADMIN:-azureuser}"
SSH_PUB="${SSH_PUB:-$HOME/.ssh/id_rsa.pub}"

az vm create \
  --name "$VM" \
  --resource-group "$RG" \
  --location "$LOC" \
  --image "Ubuntu2204" \
  --admin-username "$ADMIN" \
  --ssh-key-values "$SSH_PUB" \
  --vnet-name "$VNET" \
  --subnet "$SNET_VM" \
  --public-ip-address "" \
  --assign-identity

# -------- RBAC assignments for the VM identity --------
echo "[rbac] assign roles to VM managed identity"
PRINCIPAL_ID=$(az vm show --name "$VM" --resource-group "$RG" --query "identity.principalId" -o tsv)

# Key Vault: Secrets User
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID"

# Storage: Blob Data Contributor
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$SA_ID"

# -------- Log Analytics + Diagnostic settings --------
echo "[log] create LA workspace"
az monitor log-analytics workspace create \
  --resource-group "$RG" \
  --workspace-name "$LA" \
  --location "$LOC" \
  --tags env=lab owner=day10

LA_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LA" --query id -o tsv)

echo "[log] diagnostics for Key Vault"
KV_DIAG_CATS=$(az monitor diagnostic-settings categories list --resource "$KV_ID" --query "[?categoryType=='Logs'].name" -o tsv | tr '\n' ' ')
az monitor diagnostic-settings create \
  --name diag-kv-day10 \
  --resource "$KV_ID" \
  --workspace "$LA_ID" \
  $(for c in $KV_DIAG_CATS; do echo --logs "category=$c,enabled=true"; done)

echo "[log] diagnostics for Storage (account scope)"
SA_DIAG_CATS=$(az monitor diagnostic-settings categories list --resource "$SA_ID" --query "[?categoryType=='Logs'].name" -o tsv | tr '\n' ' ')
az monitor diagnostic-settings create \
  --name diag-sa-day10 \
  --resource "$SA_ID" \
  --workspace "$LA_ID" \
  $(for c in $SA_DIAG_CATS; do echo --logs "category=$c,enabled=true"; done)

echo "[done] Day10 provisioning via CLI complete."
echo "Names:"
echo "  KV=$KV"
echo "  SA=$SA"
echo "  LA=$LA"
