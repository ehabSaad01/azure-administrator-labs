#!/usr/bin/env bash
set -euo pipefail

# === Inputs (replace subscription id if you will run this script) ===
SUBSCRIPTION_ID="<your_subscription_id>"
RESOURCE_GROUP_NAME="rg-day9-storage-security"
LOCATION_NAME="westeurope"
KEY_VAULT_NAME="kvday9weu31733"
KEY_NAME="cmk-day9"
STORAGE_ACCOUNT_NAME="stday9secweu31733"
CONTAINER_NAME="enc-test"

# === 0) Context ===
az account set --subscription "${SUBSCRIPTION_ID}"

# === 1) Resource Group ===
az group create \
  --name "${RESOURCE_GROUP_NAME}" \
  --location "${LOCATION_NAME}"

# === 2) Key Vault (RBAC + network hardening) ===
az keyvault create \
  --name "${KEY_VAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --location "${LOCATION_NAME}" \
  --enable-rbac-authorization true \
  --public-network-access Enabled

az keyvault update \
  --name "${KEY_VAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --default-action Deny \
  --bypass AzureServices \
  --enable-purge-protection true

MYIP="$(curl -4 -s ifconfig.me || echo 0.0.0.0)"
az keyvault network-rule add \
  --name "${KEY_VAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --ip-address "${MYIP}/32"

# Grant current user temporary admin on KV to manage keys
USER_OID="$(az ad signed-in-user show --query id --output tsv)"
KV_ID="$(az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query id --output tsv)"
az role assignment create \
  --assignee-object-id "${USER_OID}" \
  --assignee-principal-type "User" \
  --role "Key Vault Administrator" \
  --scope "${KV_ID}"

# === 3) Key + Rotation policy ===
az keyvault key create \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${KEY_NAME}" \
  --kty "RSA" \
  --size "3072"

cat > /tmp/rotation-policy.json <<'JSON'
{
  "lifetimeActions": [
    { "trigger": { "timeAfterCreate": "P12M", "timeBeforeExpiry": null }, "action": { "type": "Rotate" } },
    { "trigger": { "timeBeforeExpiry": "P30D" }, "action": { "type": "Notify" } }
  ],
  "attributes": { "expiryTime": "P24M" }
}
JSON

az keyvault key rotation-policy update \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${KEY_NAME}" \
  --value "/tmp/rotation-policy.json"

# === 4) Storage account (secure-by-default) + identity + firewall ===
az storage account create \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --location "${LOCATION_NAME}" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --https-only true \
  --allow-blob-public-access false

az storage account update \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --assign-identity

az storage account update \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --default-action "Deny" \
  --bypass "AzureServices"

az storage account network-rule add \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --ip-address "${MYIP}"

# === 5) Grant storage MI crypto rights on KV (RBAC) ===
SA_PID="$(az storage account show --resource-group "${RESOURCE_GROUP_NAME}" --name "${STORAGE_ACCOUNT_NAME}" --query "identity.principalId" --output tsv)"
az role assignment create \
  --assignee-object-id "${SA_PID}" \
  --assignee-principal-type "ServicePrincipal" \
  --role "Key Vault Crypto Service Encryption User" \
  --scope "${KV_ID}"

# === 6) Bind account-level CMK (auto-version) ===
az storage account update \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --encryption-key-source "Microsoft.Keyvault" \
  --encryption-key-vault "https://${KEY_VAULT_NAME}.vault.azure.net" \
  --encryption-key-name "${KEY_NAME}" \
  --encryption-key-version ""

# === 7) Encryption Scopes ===
az storage account encryption-scope create \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --name "scope-mm" \
  --key-source "Microsoft.Storage"

az storage account encryption-scope create \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --name "scope-cmk" \
  --key-source "Microsoft.KeyVault" \
  --key-uri "$(az keyvault key show --vault-name "${KEY_VAULT_NAME}" --name "${KEY_NAME}" --query "key.kid" --output tsv)"

# === 8) Container with enforced CMK scope ===
az storage container create \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --name "${CONTAINER_NAME}" \
  --public-access "off" \
  --default-encryption-scope "scope-cmk" \
  --prevent-encryption-scope-override true \
  --auth-mode "login"
