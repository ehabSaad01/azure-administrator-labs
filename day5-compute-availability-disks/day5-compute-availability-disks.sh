#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Variables
# ==============================
SUBSCRIPTION="<your_subscription_id>"   # REQUIRED
RG="rg-day5-compute"
LOC="westeurope"
VNET="vnet-day5"
SUBNET="subnet-app"
ADDRESS_PREFIXES="10.20.0.0/16"
SUBNET_PREFIX="10.20.1.0/24"
NSG="nsg-day5"
PIP="pip-day5"
LB="lb-day5"
FE="fe-web"
BP="bp-web"
PROBE="hp-80"
RULE="lr-80"
VM_A="vm5-a"
VM_B="vm5-b"
VM_SIZE="Standard_B2s"
ADMIN_USER="ehab"
DATA_DISK_A="data5-a"
SNAP_A="snap-data5-a"
RESTORE_DISK_B="data5-restored-zone2"
CLOUD_INIT_FILE="cloud-init-nginx.yaml"

# ==============================
# 0) Subscription
# ==============================
az account set \
  --subscription "$SUBSCRIPTION"

# ==============================
# 1) Resource Group
# ==============================
az group create \
  --name "$RG" \
  --location "$LOC"

# ==============================
# 2) Network: VNet + Subnet
# ==============================
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOC" \
  --address-prefixes "$ADDRESS_PREFIXES" \
  --subnet-name "$SUBNET" \
  --subnet-prefixes "$SUBNET_PREFIX"

# ==============================
# 3) NSG + Allow HTTP (priority 100) and associate to Subnet
# ==============================
az network nsg create \
  --resource-group "$RG" \
  --name "$NSG" \
  --location "$LOC"

az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG" \
  --name "allow-http-80" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 80

az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --network-security-group "$NSG"

# ==============================
# 4) Public IP (Standard, static, IPv4)
# ==============================
az network public-ip create \
  --resource-group "$RG" \
  --name "$PIP" \
  --location "$LOC" \
  --sku Standard \
  --allocation-method Static \
  --version IPv4

# ==============================
# 5) Load Balancer + Frontend + Backend Pool
# ==============================
az network lb create \
  --resource-group "$RG" \
  --name "$LB" \
  --sku Standard \
  --location "$LOC" \
  --public-ip-address "$PIP" \
  --frontend-ip-name "$FE" \
  --backend-pool-name "$BP"

az network lb probe create \
  --resource-group "$RG" \
  --lb-name "$LB" \
  --name "$PROBE" \
  --protocol Http \
  --port 80 \
  --path "/"

az network lb rule create \
  --resource-group "$RG" \
  --lb-name "$LB" \
  --name "$RULE" \
  --protocol Tcp \
  --frontend-ip-name "$FE" \
  --backend-pool-name "$BP" \
  --frontend-port 80 \
  --backend-port 80 \
  --probe-name "$PROBE"

# ==============================
# 6) Cloud-init file (nginx + banner)
# ==============================
cat > "$CLOUD_INIT_FILE" <<'CLOUD'
#cloud-config
packages:
  - nginx
runcmd:
  - bash -lc 'echo "Hello from $(hostname)" > /var/www/html/index.nginx-debian.html'
  - systemctl enable --now nginx
CLOUD

# ==============================
# 7) VM A in Zone 1 (no Public IP)
# ==============================
az vm create \
  --resource-group "$RG" \
  --name "$VM_A" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" \
  --size "$VM_SIZE" \
  --location "$LOC" \
  --zone 1 \
  --admin-username "$ADMIN_USER" \
  --authentication-type "ssh" \
  --generate-ssh-keys \
  --vnet-name "$VNET" \
  --subnet "$SUBNET" \
  --public-ip-address "" \
  --custom-data "$CLOUD_INIT_FILE"

# ==============================
# 8) VM B in Zone 2 (no Public IP)
# ==============================
az vm create \
  --resource-group "$RG" \
  --name "$VM_B" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" \
  --size "$VM_SIZE" \
  --location "$LOC" \
  --zone 2 \
  --admin-username "$ADMIN_USER" \
  --authentication-type "ssh" \
  --generate-ssh-keys \
  --vnet-name "$VNET" \
  --subnet "$SUBNET" \
  --public-ip-address "" \
  --custom-data "$CLOUD_INIT_FILE"

# ==============================
# 9) Add both NICs to LB backend pool
# ==============================
NIC_A_ID=$(az vm show --resource-group "$RG" --name "$VM_A" --query "networkProfile.networkInterfaces[0].id" --output tsv)
NIC_B_ID=$(az vm show --resource-group "$RG" --name "$VM_B" --query "networkProfile.networkInterfaces[0].id" --output tsv)
NIC_A_NAME=$(az network nic show --ids "$NIC_A_ID" --query "name" --output tsv)
NIC_B_NAME=$(az network nic show --ids "$NIC_B_ID" --query "name" --output tsv)

az network nic ip-config address-pool add \
  --resource-group "$RG" \
  --nic-name "$NIC_A_NAME" \
  --ip-config-name "ipconfig1" \
  --lb-name "$LB" \
  --address-pool "$BP"

az network nic ip-config address-pool add \
  --resource-group "$RG" \
  --nic-name "$NIC_B_NAME" \
  --ip-config-name "ipconfig1" \
  --lb-name "$LB" \
  --address-pool "$BP"

# ==============================
# 10) Data disk on VM A: create + attach (caching None) + resize to 128 GiB
# ==============================
az disk create \
  --resource-group "$RG" \
  --name "$DATA_DISK_A" \
  --location "$LOC" \
  --sku Premium_LRS \
  --size-gb 64

az vm disk attach \
  --resource-group "$RG" \
  --vm-name "$VM_A" \
  --name "$DATA_DISK_A" \
  --caching None

az disk update \
  --resource-group "$RG" \
  --name "$DATA_DISK_A" \
  --size-gb 128

# ==============================
# 11) Snapshot + Restore to Zone 2 and attach to VM B
# ==============================
az snapshot create \
  --resource-group "$RG" \
  --name "$SNAP_A" \
  --location "$LOC" \
  --source "$DATA_DISK_A"

az disk create \
  --resource-group "$RG" \
  --name "$RESTORE_DISK_B" \
  --location "$LOC" \
  --source "$SNAP_A" \
  --zone 2

az vm disk attach \
  --resource-group "$RG" \
  --vm-name "$VM_B" \
  --name "$RESTORE_DISK_B" \
  --caching None

# ==============================
# 12) Output: Public IP of LB
# ==============================
az network public-ip show \
  --resource-group "$RG" \
  --name "$PIP" \
  --query "ipAddress" \
  --output tsv
