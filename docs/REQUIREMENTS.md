# Requirements

## Runtime matrix

| Environment | v0.1 behavior | Verification |
|---|---|---|
| 64-bit Windows PowerShell 5.1 / Windows 11 Pro or Enterprise management host | Intended live + demo | Documentation checked; AD lab run pending |
| 64-bit Windows PowerShell 5.1 / Windows Server 2019, 2022, 2025 management host | Intended live + demo | Documentation checked; AD lab run pending |
| PowerShell 7 / Windows | Demo and tests only; live blocked | Full native RSAT/GPO integration not claimed |
| PowerShell 7 / macOS | Demo and tests only; live blocked | 7.6.9 executed locally |
| PowerShell 7 / Linux | Demo and tests by design; live blocked | Not executed locally |
| 32-bit Windows PowerShell | Live blocked | Use 64-bit host |

Use an OS still supported by the vendor and your organisation. This matrix is an implementation target, not proof that each OS has been integration-tested. No Entra ID, Microsoft Graph or Microsoft 365 dependencies are used.

## Installed components

Live: Microsoft `ActiveDirectory` module (RSAT AD DS/LDS tools / RSAT-AD-PowerShell), `GroupPolicy` (Group Policy Management), `DnsClient` (`Resolve-DnsName`) and built-in `w32tm.exe`. The toolkit uses .NET included in Windows PowerShell, built-in jobs, JSON/CSV and file commands. No third-party PowerShell modules or gallery downloads are required, including for tests.

Read-only prerequisite inspection in Windows PowerShell:

```powershell
$PSVersionTable
[Environment]::Is64BitProcess
Get-Module -ListAvailable ActiveDirectory,GroupPolicy,DnsClient
Get-Command Get-ADDomain,Get-ADDomainController,Get-ADReplicationPartnerMetadata,Get-GPO,Resolve-DnsName
Get-Command w32tm.exe
```

Module installation, script signing and domain join are administrator-managed prerequisites, deliberately outside toolkit behavior. Follow the linked Microsoft RSAT instructions if prerequisites are absent.

## Identity and network

Use the current approved Windows identity, ideally a dedicated read-only assessment identity with rights matched to the agreed scope. Normal directory reads often work without elevated privileges, but custom ACLs, replication metadata, GPO reads, remote W32Time and share access can require additional delegated rights. Do not grant broad administrative membership merely to make every check green.

Expected dependencies include domain DNS (TCP/UDP 53), AD Web Services on targeted DCs (TCP 9389), domain authentication (including Kerberos) and directory/RPC connectivity required by the installed management modules, SMB 445 for shares, and remote W32Time query permissions/RPC connectivity. The tool does not probe every required port or reconfigure firewalls. `w32tm /query` is remote status collection, **not** an NTP offset probe. Review the official Windows Time documentation for remote query requirements. Multi-domain forest-root group reads require corresponding connectivity and rights.

A deadline error means incomplete evidence, not necessarily an unhealthy DC. If one DC does not host DNS, its DNS check will remain inconclusive; v0.1 does not accept a separate resolver map. Tune thresholds and limits after reviewing site schedules and environment size.

Output parent folders should be local, access controlled, have sufficient space, and not be web-served or synchronized publicly. The tool inherits ACLs and never hardens or modifies them for you.
