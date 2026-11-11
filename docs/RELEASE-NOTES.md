# RELAY AD Health Toolkit v0.1.0 — Community Edition preview

Read-only on-prem AD observations for one configured domain: DC inventory, FSMO ownership, inbound replication, DNS locator records, SYSVOL/NETLOGON access, raw W32Time status, direct privileged group membership, inactive account candidates, password policies and GPO inventory.

Includes validated JSON settings, bounded category jobs, explicit error/incomplete statuses, HTML/CSV output, manifests and hashes, isolated synthetic demo, offline tests and MIT licence. No credentials, dependency installation, telemetry or remediation.

Live target: 64-bit Windows PowerShell 5.1 with installed RSAT. PowerShell 7 supports demo/tests only in v0.1. Offline validation was performed on macOS/PowerShell 7.6.9; Windows/AD lab execution remains pending. The demo deliberately shows warnings and an error. This preview is not a compliance certification or full AD security audit.

See README for coverage boundaries and docs/VALIDATION.md for test evidence. For tailored checks or evidence interpretation, start with a non-confidential brief at https://n0hup.codeberg.page/tailored.html.
