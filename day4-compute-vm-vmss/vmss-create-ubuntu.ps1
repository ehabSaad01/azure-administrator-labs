Param(
  [string]$ResourceGroup = "rg-day4-compute",
  [string]$Location = "westeurope",
  [string]$VnetName = "vnet-day4",
  [string]$SubnetName = "subnet-vm",
  [string]$VmssName = "vmss-day4-demo",
  [string]$VmSize = "Standard_B2s",
  [string]$AdminUser = "azureuser",
  [int]$MinCount = 2,
  [int]$MaxCount = 6,
  [int]$DefaultCount = 2
)

# Requires Azure CLI. Login first: az login --use-device-code

# 1) Create VMSS (Uniform, Ubuntu 22.04)
az vmss create `
  --resource-group $ResourceGroup `
  --name $VmssName `
  --orchestration-mode Uniform `
  --image Ubuntu2204 `
  --vm-sku $VmSize `
  --instance-count $DefaultCount `
  --admin-username $AdminUser `
  --generate-ssh-keys `
  --vnet-name $VnetName `
  --subnet $SubnetName `
  --upgrade-policy-mode automatic

# 2) Autoscale profile + rules
az monitor autoscale create `
  --resource-group $ResourceGroup `
  --resource $VmssName `
  --resource-type Microsoft.Compute/virtualMachineScaleSets `
  --name ("autoscale-" + $VmssName) `
  --min-count $MinCount `
  --max-count $MaxCount `
  --count $DefaultCount

az monitor autoscale rule create `
  --resource-group $ResourceGroup `
  --autoscale-name ("autoscale-" + $VmssName) `
  --condition "Percentage CPU > 70 avg 5m" `
  --scale out 1

az monitor autoscale rule create `
  --resource-group $ResourceGroup `
  --autoscale-name ("autoscale-" + $VmssName) `
  --condition "Percentage CPU < 30 avg 5m" `
  --scale in 1

# 3) Install NGINX on all instances
$instanceIds = az vmss list-instances `
  --resource-group $ResourceGroup `
  --name $VmssName `
  --query "[].instanceId" `
  --output tsv

foreach ($id in $instanceIds) {
  az vmss run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmssName `
    --instance-id $id `
    --command-id RunShellScript `
    --scripts "sudo apt-get update -y" "sudo apt-get install -y nginx" "sudo systemctl enable --now nginx"
}

# 4) Load Balancer: probe + rule for port 80
$lbName = az network lb list `
  --resource-group $ResourceGroup `
  --query "[?contains(name,'$VmssName')].name | [0]" `
  --output tsv

az network lb probe create `
  --resource-group $ResourceGroup `
  --lb-name $lbName `
  --name http-probe-80 `
  --protocol Http `
  --port 80 `
  --request-path /

$feName = az network lb show --resource-group $ResourceGroup --name $lbName --query "frontendIpConfigurations[0].name" --output tsv
$beName = az network lb show --resource-group $ResourceGroup --name $lbName --query "backendAddressPools[0].name" --output tsv

az network lb rule create `
  --resource-group $ResourceGroup `
  --lb-name $lbName `
  --name http-rule-80 `
  --protocol Tcp `
  --frontend-port 80 `
  --backend-port 80 `
  --frontend-ip-name $feName `
  --backend-pool-name $beName `
  --probe-name http-probe-80 `
  --idle-timeout 4 `
  --enable-tcp-reset true

# 5) Output Public IP
az network public-ip list `
  --resource-group $ResourceGroup `
  --query "[].{name:name,ip:ipAddress}" `
  --output table

Write-Host "Open: http://<PUBLIC_IP_FROM_TABLE>"
