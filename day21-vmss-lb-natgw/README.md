# Day21 – VMSS + Public Load Balancer + Autoscale + NAT Gateway

## Architecture
- Single VNet (`vnet21weu`) with app subnet (`subnet-app21`).
- Subnet-level NSG allowing only **AzureLoadBalancer** to TCP/80.
- NAT Gateway (`natgw21weu`) with a Standard Static Public IP for stable outbound SNAT.
- Standard Public Load Balancer (`lb21weu`) with:
  - Frontend IP (`fe-lb21weu`) on a Static Public IP.
  - Backend pool (`bepool21`) targeting the VMSS NICs.
  - TCP probe on port 80 and an LB rule 80→80.
- VM Scale Set (`vmss21weu`) Ubuntu 22.04, 2 instances, no per-VM public IPs, backend-joined.
- Custom Script installs Nginx and publishes a simple page.
- Autoscale: Min=2, Max=5, Scale-out when CPU>60% avg 5m, Scale-in when CPU<30% avg 5m.
- Diagnostics: LB logs+metrics to Log Analytics (`law21weu`).
- Alert: NAT Gateway `SnatPortUtilization >= 80%`.

## Test
1. Get the LB Public IP from `lb21weu` → Frontend configuration → `fe-lb21weu`.
2. Browse `http://<LB_Public_IP>`; you should see: `Day21 VMSS + LB + NATGW Lab`.
3. Check probes: `lb21weu → Health probes → hp-tcp-80 → Backend instances`.
4. Generate CPU load (optional) to trigger autoscale.

## Cleanup
- Delete the resource group to remove all resources:
  - CLI: `az group delete --name rg-day21-compute --yes --no-wait`
  - PowerShell: `Remove-AzResourceGroup -Name rg-day21-compute -Force -AsJob`

