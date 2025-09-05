#!/usr/bin/env bash
set -euo pipefail

DEVICE="/dev/sdc"
PARTITION="/dev/sdc1"
MOUNTPOINT="/data"

# Show block devices
sudo lsblk

# If no filesystem exists, create partition and format as XFS
if ! lsblk -f | grep -q "$(basename "$PARTITION")"; then
  sudo parted "$DEVICE" --script mklabel gpt mkpart primary xfs 0% 100%
  sudo mkfs.xfs "$PARTITION"
fi

# Create mount point and mount the partition
sudo mkdir -p "$MOUNTPOINT"
UUID=$(sudo blkid -s UUID -o value "$PARTITION")
echo "UUID=$UUID $MOUNTPOINT xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
sudo df -h "$MOUNTPOINT"

# After resizing the disk from Azure portal
if command -v growpart >/dev/null 2>&1; then
  sudo growpart "$DEVICE" 1 || true
else
  sudo apt-get update -y
  sudo apt-get install -y cloud-guest-utils
  sudo growpart "$DEVICE" 1 || true
fi

# Expand XFS filesystem to use the new size
if command -v xfs_growfs >/dev/null 2>&1; then
  sudo xfs_growfs "$MOUNTPOINT" || true
else
  sudo apt-get install -y xfsprogs
  sudo xfs_growfs "$MOUNTPOINT" || true
fi

sudo df -h "$MOUNTPOINT"
