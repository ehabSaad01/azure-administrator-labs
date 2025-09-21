
Day18 — Application Gateway WAF (Internal-only)

Goal: Private-only Application Gateway (WAF_v2) مع WAF policy بوضع Prevention، خادمين Ubuntu/NGINX خلف Backend pool، /healthz probe، وDiagnostic settings إلى Log Analytics وStorage. لا Public IP على الـ VMs. الإدارة عبر Azure Bastion فقط.

Architecture

RG: rg-day18-agw • Region: West Europe

VNet: vnet18weu (10.18.0.0/16)

agwsub18 (10.18.0.0/27) — Application Gateway

backsub18 (10.18.2.0/24) — Backends: 10.18.2.10, 10.18.2.11

AzureBastionSubnet (10.18.3.0/26) — Bastion

clientsub18 (10.18.4.0/24) — Internal client

NSG: nsg18back (Allow AGW→80, Bastion→22, Deny VNet inbound)

AGW: agw18weu (Private IP 10.18.0.10)

WAF policy: waf18weu (Prevention)

Logs: la18weu + sa18logs<unique>

Runbooks

CLI: ./day18-agw-waf-cli-long.sh ← استبدل <your_subscription_id> وsa18logs<unique> قبل التشغيل.

PowerShell: pwsh ./Day18-Application-Gateway-WAF.ps1 ← حدّث <your_subscription_id> وsa18logs<unique>.
curl -I http://10.18.0.10/
curl -i 'http://10.18.0.10/?id=%27%20OR%201%3D1'   # Expect 403

ApplicationGatewayFirewallLog
| where action_s == "Blocked"
| project TimeGenerated, clientIp_s, requestUri_s, ruleSetVersion_s, ruleId_s
| order by TimeGenerated desc


git add day18-application-gateway-waf/*
git commit -m "Day18: Application Gateway WAF — CLI and PowerShell scripts"
git push -u origin main

