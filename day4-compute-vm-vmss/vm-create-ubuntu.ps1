Param(
  [string]$ResourceGroup = "rg-day4-compute",
  [string]$Location = "westeurope",
  [string]$VnetName = "vnet-day4",
  [string]$VnetCidr = "10.10.0.0/16",
  [string]$SubnetName = "subnet-vm",
  [string]$SubnetCidr = "10.10.1.0/24",
  [string]$VmName = "vm-day4-demo",
  [string]$AdminUser = "azureuser"
)

# Requires Azure CLI. Run from PowerShell: pwsh or Windows PowerShell.
# Login first: az login --use-device-code

az group create --name $ResourceGroup --location $Location

az network vnet create `
  --resource-group $ResourceGroup `
  --name $VnetName `
  --address-prefix $VnetCidr `
  --subnet-name $SubnetName `
  --subnet-prefix $SubnetCidr

az vm create `
  --resource-group $ResourceGroup `
  --name $VmName `
  --image Ubuntu2204 `
  --size Standard_B2s `
  --admin-username $AdminUser `
  --generate-ssh-keys `
  --vnet-name $VnetName `
  --subnet $SubnetName `
  --public-ip-sku Standard `
  --nsg-rule SSH

az vm open-port --resource-group $ResourceGroup --name $VmName --port 80  --priority 1001
az vm open-port --resource-group $ResourceGroup --name $VmName --port 443 --priority 1002

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $VmName `
  --command-id RunShellScript `
  --scripts "sudo apt-get update -y" "sudo apt-get install -y nginx" "sudo systemctl enable --now nginx"

az vm list-ip-addresses --resource-group $ResourceGroup --name $VmName --output table
