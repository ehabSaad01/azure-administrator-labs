# Day15 — Azure Bastion (secure admin without Public IP)

## Goal
Secure admin via Azure Bastion over 443. No Public IP on VMs. Subnet-level NSG restricts SSH 22 only from AzureBastionSubnet.

## Contents
- day15-bastion-cli.sh  (AZ CLI, long options, re-runnable)
- Day15-Bastion.ps1     (Az PowerShell)
- This README

## Variables
Subscription, region, names, CIDRs, and tags at top of each script.

## How to run
Bash:
  chmod +x day15-bastion-cli.sh
  ./day15-bastion-cli.sh

PowerShell:
  pwsh -File ./Day15-Bastion.ps1 -Subscription "<your_subscription_id>"
