#!/usr/bin/env bash
set -euo pipefail

# Day8 – Storage Data Protection (CLI)
# Goals:
# - Create RG and secure Storage Account
# - Enable Versioning, Soft Delete (blobs/containers), Change Feed
# - Containers: ver-soft, audit-worm-locked
# - Apply WORM (time-based locked)
# - Versioning + Soft Delete demo
# - Lifecycle policy

SUBSCRIPTION="<SUBSCRIPTION_ID>"     # TODO: replace
RG="rg-day8-storage-protection"
LOC="westeurope"
SA="stday8dataprotectcli"            # change if name is taken

echo "[Info] Set subscription context"
az account set --subscription "$SUBSCRIPTION"

echo "[Info] Create resource group (idempotent)"
az group create \
  --name "$RG" \
  --location "$LOC" \
  --output table

echo "[Info] Create secure StorageV2 account"
az storage account create \
  --name "$SA" \
  --resource-group "$RG" \
  --location "$LOC" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output table

echo "[Info] Enable Versioning"
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-versioning true \
  --output table

echo "[Info] Enable Blob Soft Delete (7 days)"
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  --output table

echo "[Info] Enable Container Soft Delete (7 days)"
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-container-delete-retention true \
  --container-delete-retention-days 7 \
  --output table

echo "[Info] Enable Change Feed"
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-change-feed true \
  --output table

echo "[Info] Create containers"
az storage container create --name ver-soft --account-name "$SA" --auth-mode login --public-access off --output table
az storage container create --name audit-worm-locked --account-name "$SA" --auth-mode login --public-access off --output table

echo "[Info] Create WORM immutability policy (1 day, unlocked)"
ETAG_cli=$(
  az storage container immutability-policy create \
    --account-name "$SA" \
    --container-name audit-worm-locked \
    --period 1 \
    --allow-protected-append-writes false \
    --query etag --output tsv
)
echo "[Info] Policy ETag: $ETAG_cli"

echo "[Info] Lock WORM policy (container-scope)"
az storage container immutability-policy lock \
  --account-name "$SA" \
  --container-name audit-worm-locked \
  --if-match "$ETAG_cli" \
  --output table

echo "[Info] Show policy"
az storage container immutability-policy show \
  --account-name "$SA" \
  --container-name audit-worm-locked \
  --output json

echo "[Info] Versioning + Soft Delete demo on ver-soft"
echo "Retention=7; Policy=v1" > policy-v1.txt
az storage blob upload --account-name "$SA" --container-name ver-soft --name policy.txt --file policy-v1.txt --auth-mode login --overwrite false --output table

echo "Retention=7; Policy=v2 - changed content" > policy-v2.txt
az storage blob upload --account-name "$SA" --container-name ver-soft --name policy.txt --file policy-v2.txt --auth-mode login --overwrite true --output table

echo "[Info] List versions"
az storage blob list --account-name "$SA" --container-name ver-soft --include v --query "[?name=='policy.txt'].[name, versionId]" --output table

echo "[Info] Soft delete"
az storage blob delete --account-name "$SA" --container-name ver-soft --name policy.txt --auth-mode login --output table

echo "[Info] Undelete"
az storage blob undelete --account-name "$SA" --container-name ver-soft --name policy.txt --auth-mode login --output table

echo "[Info] Create Lifecycle policy JSON"
cat > policy-day8.json << 'JSON'
{
  "policy": {
    "rules": [
      {
        "enabled": true,
        "name": "ver-soft-lifecycle",
        "type": "Lifecycle",
        "definition": {
          "filters": {
            "blobTypes": [ "blockBlob" ],
            "prefixMatch": [ "ver-soft/" ]
          },
          "actions": {
            "baseBlob": {
              "tierToCool":    { "daysAfterModificationGreaterThan": 30 },
              "tierToArchive": { "daysAfterModificationGreaterThan": 90 }
            },
            "version": {
              "delete": { "daysAfterCreationGreaterThan": 30 }
            }
          }
        }
      }
    ]
  }
}
JSON

echo "[Info] Apply Lifecycle policy"
az storage account management-policy create \
  --account-name "$SA" \
  --resource-group "$RG" \
  --policy @policy-day8.json \
  --output table

echo "[Info] Done."
