# Day9 – Storage Security (Encryption, Scopes, CMK, SAS, RBAC)

## What this delivers
- SSE with CMK (Key Vault) + auto key version.
- Encryption Scopes (Microsoft-managed + CMK).
- Secure networking (deny-by-default, AzureServices bypass, IP rules).
- RBAC for data-plane, Stored Access Policy, Service SAS, User Delegation SAS.

## Files
- day9-storage-security-cli.sh  → Full CLI, long options, secure-by-default.
- Day9-Storage-Security.ps1     → Az PowerShell equivalent.

## Notes
- Replace <your_subscription_id> before running scripts.
- Names used: rg-day9-storage-security, kvday9weu31733, stday9secweu31733, cmk-day9, scope-mm, scope-cmk, enc-test.
