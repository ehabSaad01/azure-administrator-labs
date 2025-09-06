#!/usr/bin/env bash
# Simple Azure Storage lab commands. Full option names. No loops. Minimal vars only for keys.

# 1) Select subscription
az account set --subscription "<your_subscription_id>"

# 2) Create resource group
az group create --name "rg-day6-storage" --location "westeurope"

# 3) Create storage account 1 (no HNS)
az storage account create \
  --name "stday6weu01ehab" \
  --resource-group "rg-day6-storage" \
  --location "westeurope" \
  --kind "StorageV2" \
  --sku "Standard_ZRS" \
  --https-only true \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --allow-shared-key-access true \
  --tags "project=az104-day6" "owner=ehab" "env=lab"

# 4) Create storage account 2 (with HNS)
az storage account create \
  --name "stday6weu02ehab" \
  --resource-group "rg-day6-storage" \
  --location "westeurope" \
  --kind "StorageV2" \
  --sku "Standard_ZRS" \
  --https-only true \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --allow-shared-key-access true \
  --enable-hierarchical-namespace true \
  --tags "project=az104-day6" "owner=ehab" "env=lab"

# 5) Get account keys
KEY1=$(az storage account keys list --resource-group "rg-day6-storage" --account-name "stday6weu01ehab" --query "[0].value" --output tsv)
KEY2=$(az storage account keys list --resource-group "rg-day6-storage" --account-name "stday6weu02ehab" --query "[0].value" --output tsv)

# 6a) Blob container on ST1
az storage container create \
  --name "cn-app" \
  --account-name "stday6weu01ehab" \
  --account-key "$KEY1" \
  --public-access "off"

# 6b) ADLS Gen2 filesystem on ST2
az storage fs create \
  --name "fs-raw" \
  --account-name "stday6weu02ehab" \
  --account-key "$KEY2"

# 6c) File share on ST1
az storage share create \
  --name "fs-app" \
  --account-name "stday6weu01ehab" \
  --account-key "$KEY1"

# 6d) Queue on ST1
az storage queue create \
  --name "q-app" \
  --account-name "stday6weu01ehab" \
  --account-key "$KEY1"

# 6e) Table on ST1
az storage table create \
  --name "appdata" \
  --account-name "stday6weu01ehab" \
  --account-key "$KEY1"

# 6f) Insert a demo entity into the table
az storage entity insert \
  --account-name "stday6weu01ehab" \
  --account-key "$KEY1" \
  --table-name "appdata" \
  --entity "PartitionKey=app" "RowKey=v1" "env=lab" "enabled=true"

# 7a) Enable blob protection on ST1
az storage account blob-service-properties update \
  --resource-group "rg-day6-storage" \
  --account-name "stday6weu01ehab" \
  --enable-versioning true \
  --enable-change-feed true \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 7 \
  --enable-restore-policy true \
  --restore-days 7

# 7b) Enable blob protection on ST2
az storage account blob-service-properties update \
  --resource-group "rg-day6-storage" \
  --account-name "stday6weu02ehab" \
  --enable-versioning true \
  --enable-change-feed true \
  --enable-delete-retention true \
  --delete-retention-days 7 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 7 \
  --enable-restore-policy true \
  --restore-days 7

# 7c) Enable file share soft delete on ST1
az storage account file-service-properties update \
  --resource-group "rg-day6-storage" \
  --account-name "stday6weu01ehab" \
  --enable-delete-retention true \
  --delete-retention-days 7

# 8a) Lifecycle policy for ST1
cat > "lc-st1.json" <<'JSON'
{
  "rules": [
    {
      "name": "lc-cn-app",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["cn-app/"]
        },
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

az storage account management-policy create \
  --resource-group "rg-day6-storage" \
  --account-name "stday6weu01ehab" \
  --policy @"lc-st1.json"

# 8b) Lifecycle policy for ST2
cat > "lc-st2.json" <<'JSON'
{
  "rules": [
    {
      "name": "lc-fs-raw",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["fs-raw/"]
        },
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

az storage account management-policy create \
  --resource-group "rg-day6-storage" \
  --account-name "stday6weu02ehab" \
  --policy @"lc-st2.json"

# 9) Quick checks
az storage account show --resource-group "rg-day6-storage" --name "stday6weu01ehab" --query "primaryEndpoints" --output json
az storage account show --resource-group "rg-day6-storage" --name "stday6weu02ehab" --query "primaryEndpoints" --output json
