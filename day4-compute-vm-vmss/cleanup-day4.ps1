Param(
  [string]$ResourceGroup = "rg-day4-compute"
)
az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Delete requested for $ResourceGroup."
