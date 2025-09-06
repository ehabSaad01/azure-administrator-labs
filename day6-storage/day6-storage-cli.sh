#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SUBSCRIPTION="${SUBSCRIPTION:-<your_subscription_id>}"
RG="${RG:-rg-day6-storage}"
LOC="${LOC:-westeurope}"

ST1="${ST1:-stday6weu01ehab}"   # StorageV2 بدون HNS
ST2="${ST2:-stday6weu02ehab}"   # StorageV2 مع HNS (Data Lake Gen2)

CN="${CN:-cn-app}"      # Blob container
DLFS="${DLFS:-fs-raw}"  # ADLS Gen2 file system
FS="${FS:-fs-app}"      # File share
QUEUE="${QUEUE:-q-app}" # Queue
TABLE="${TABLE:-appdata}"# Table

echo "Using SUBSCRIPTION=$SUBSCRIPTION RG=$RG LOC=$LOC"
echo "ST1=$ST1 ST2=$ST2 | CN=$CN DLFS=$DLFS FS=$FS QUEUE=$QUEUE TABLE=$TABLE"

# --- Auth / RG ---
az account set --subscription "$SUBSCRIPTION"
az group create --name "$RG" --location "$LOC" 1>/dev/null

# --- Storage Accounts ---
az storage account create \
  --name "$ST1" --resource-group "$RG" --location "$LOC" \
  --kind StorageV2 --sku Standard_ZRS \
  --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access true \
  --tags project=az104-day6 owner=ehab env=lab 1>/dev/null

az storage account create \
  --name "$ST2" --resource-group "$RG" --location "$LOC" \
  --kind StorageV2 --sku Standard_ZRS \
  --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access true \
  --enable-hierarchical-namespace true \
  --tags project=az104-day6 owner=ehab env=lab 1>/dev/null

# --- Keys ---
KEY1=$(az storage account keys list -g "$RG" -n "$ST1" --query "[0].value" -o tsv)
KEY2=$(az storage account keys list -g "$RG" -n "$ST2" --query "[0].value" -o tsv)

# --- Data plane objects ---
az storage container create --name "$CN"   --account-name "$ST1" --account-key "$KEY1" 1>/dev/null
az storage fs        create --name "$DLFS" --account-name "$ST2" --account-key "$KEY2" 1>/dev/null
az storage share     create --name "$FS"   --account-name "$ST1" --account-key "$KEY1" 1>/dev/null
az storage queue     create --name "$QUEUE"--account-name "$ST1" --account-key "$KEY1" 1>/dev/null
az storage table     create --name "$TABLE"--account-name "$ST1" --account-key "$KEY1" 1>/dev/null

# Demo entity in Table
az storage entity insert \
  --account-name "$ST1" --account-key "$KEY1" \
  --table-name "$TABLE" \
  --entity PartitionKey=app RowKey=v1 env=lab enabled=true 1>/dev/null

# --- Protection (Blob + Files) ---
for ACC in "$ST1" "$ST2"; do
  az storage account blob-service-properties update \
    -g "$RG" -n "$ACC" \
    --enable-versioning true \
    --enable-change-feed true \
    --enable-delete-retention true --delete-retention-days 7 \
    --enable-container-delete-retention true --container-delete-retention-days 7 \
    --enable-restore-policy true --restore-days 7 1>/dev/null
done

az storage account file-service-properties update \
  -g "$RG" -n "$ST1" \
  --enable-delete-retention true --delete-retention-days 7 1>/dev/null

# --- Lifecycle policies ---
cat > lc-st1.json <<'JSON'
{
  "rules": [
    {
      "name": "lc-cn-app",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["cn-app/"] },
        "actions": {
          "baseBlob": {
            "tierToCool":    { "daysAfterModificationGreaterThan": 30 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 90 },
            "delete":        { "daysAfterModificationGreaterThan": 365 }
          },
          "snapshot": { "delete": { "daysAfterCreationGreaterThan": 30 } },
          "version":  { "delete": { "daysAfterCreationGreaterThan": 30 } }
        }
      }
    }
  ]
}
JSON

az storage account management-policy create -g "$RG" -n "$ST1" --policy @lc-st1.json 1>/dev/null

cat > lc-st2.json <<'JSON'
{
  "rules": [
    {
      "name": "lc-fs-raw",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["fs-raw/"] },
        "actions": {
          "baseBlob": {
            "tierToCool":    { "daysAfterModificationGreaterThan": 14 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 60 },
            "delete":        { "daysAfterModificationGreaterThan": 365 }
          },
          "snapshot": { "delete": { "daysAfterCreationGreaterThan": 30 } },
          "version":  { "delete": { "daysAfterCreationGreaterThan": 30 } }
        }
      }
    }
  ]
}
JSON

az storage account management-policy create -g "$RG" -n "$ST2" --policy @lc-st2.json 1>/dev/null

# --- Quick checks ---
echo "Endpoints ST1:"; az storage account show -g "$RG" -n "$ST1" --query "primaryEndpoints" -o json
echo "Endpoints ST2:"; az storage account show -g "$RG" -n "$ST2" --query "primaryEndpoints" -o json
