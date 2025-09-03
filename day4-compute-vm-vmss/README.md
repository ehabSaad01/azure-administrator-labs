# Day4 – Azure Compute: VM and VMSS (AZ-104)

## Prerequisites
- Azure CLI logged in: `az login --use-device-code`
- Subscription selected: `az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"`

## 1) Single VM (Ubuntu)
- Create resource group, VNet/Subnet
- Create VM with SSH
- Open ports: 80, 443
- Verify NGINX

## 2) VM Scale Set (VMSS)
- Create VMSS (Uniform, Ubuntu, B2s, 2 instances)
- Create autoscale profile (min=2, max=6, default=2)
- Add rules: out (+1 @ CPU>70% avg 5m), in (-1 @ CPU<30% avg 5m)
- Install NGINX on all instances via RunCommand
- Create LB HTTP probe and rule on port 80
- Verify public IP

## 3) Cleanup
Delete the whole resource group when done.

## Notes
- Use long options in CLI for learning clarity.
- Regions and UI can change; CLI is the source of truth in these scripts.
