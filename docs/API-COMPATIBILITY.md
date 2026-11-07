# API and compatibility review

Documentation reviewed: **2026-11-07**. These are Windows management cmdlets and a native query utility, not REST endpoints. No legacy AzureAD/MSOnline or cloud API is involved. Source review verifies interface choices; it cannot substitute for a Windows/AD execution test.

| Interface | Implementation choice | Primary reference |
|---|---|---|
| RSAT prerequisites | Existing AD DS/LDS + GPMC tools; no auto-install | [Microsoft RSAT installation and management](https://learn.microsoft.com/en-us/windows-server/administration/install-remote-server-administration-tools) |
| PowerShell 7 compatibility | AD listed native on supported Windows module versions; GroupPolicy listed untested with compatibility layer; live entry restricted to PS 5.1 Desktop | [Microsoft compatibility matrix](https://learn.microsoft.com/en-us/powershell/windows/module-compatibility?view=windowsserver2025-ps) |
| AD inventory and policies | Microsoft ActiveDirectory read cmdlets, explicit server/domain | [AD module reference](https://learn.microsoft.com/en-us/powershell/module/activedirectory/?view=windowsserver2025-ps) |
| Replication | `-Target <DC> -Partition '*' -PartnerType Inbound`; avoids default naming-context-only collection | [Get-ADReplicationPartnerMetadata](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationpartnermetadata?view=windowsserver2025-ps) |
| DNS | `Resolve-DnsName`, explicit resolver, `SRV` and `A_AAAA`, `-DnsOnly -QuickTimeout`; no updates | [Resolve-DnsName](https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname?view=windowsserver2025-ps) |
| Time | `w32tm /query /computer:<DC> /status /verbose`; bounded process, no `/resync` or `/config` | [Windows Time tools](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings) |
| Privileged groups | `Get-ADGroupMember -Identity <SID> -Server <server>`; direct membership intentionally retains nested groups | [Get-ADGroupMember](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroupmember?view=windowsserver2025-ps) |
| Inactivity | `Get-ADUser` / `Get-ADComputer` LDAP filter with explicit search base, page size, result cap + 1 | [Get-ADUser](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser?view=windowsserver2025-ps) |
| Fine-grained password policy | Inventory all returned PSOs; no resultant-user claim | [Get-ADFineGrainedPasswordPolicy](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adfinegrainedpasswordpolicy?view=windowsserver2025-ps) |
| GPO | `Get-GPO -All -Domain <domain> -Server <DC>` | [Get-GPO](https://learn.microsoft.com/en-us/powershell/module/grouppolicy/get-gpo?view=windowsserver2025-ps) |

The implementation avoids PowerShell 7-only syntax (`??`, ternary expressions, parallel pipelines). PowerShell 5.1 parser and real module binding still require the documented Windows lab acceptance. Group name localisation is handled with well-known SIDs/RIDs instead of English group-name lookup. Native time output is not parsed because labels vary by OS language.
