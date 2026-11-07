# RELAY AD Health Toolkit - MIT License
# No remote state-changing commands. Files are written only by Export-RelayReport.
Set-StrictMode -Version 2.0
$script:Checks = @('DCInventory','FSMO','Replication','DNS','SYSVOL','TimeSync','PrivilegedGroups','InactiveAccounts','PasswordPolicy','GPOInventory')

function New-RelayRow {
    param([string]$Check,[string]$Target,[ValidateSet('Pass','Warning','Error','Info','Skipped')][string]$Status,
          [string]$Summary,[string]$Evidence = '',[string]$Recommendation = '')
    [pscustomobject][ordered]@{ Check=$Check; Target=$Target; Status=$Status; Summary=$Summary; Evidence=$Evidence; Recommendation=$Recommendation; CollectedAtUtc=[DateTime]::UtcNow.ToString('o') }
}
function Read-RelayConfig {
    param([string]$Path)
    $c = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $required = @('SchemaVersion','Domain','Server','Checks','InactiveDays','ReplicationMaxAgeHours','MaxAccountsPerType','MaxDomainControllers','CheckTimeoutSeconds','NativeTimeoutSeconds','MinimumPasswordLength')
    foreach ($k in $required) { if ($k -notin $c.PSObject.Properties.Name) { throw "Missing configuration key: $k" } }
    foreach ($k in $c.PSObject.Properties.Name) { if ($k -notin $required) { throw "Unknown configuration key: $k" } }
    if ($c.SchemaVersion -ne 1) { throw 'SchemaVersion must be 1.' }
    foreach ($k in @('Domain','Server')) {
        if ($c.$k -isnot [string] -or $c.$k.Length -gt 253 -or $c.$k -notmatch '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$') { throw "$k must be an explicit DNS FQDN (no IP, wildcard, URL or command arguments)." }
    }
    $ranges = @{InactiveDays=@(1,3650);ReplicationMaxAgeHours=@(1,720);MaxAccountsPerType=@(1,100000);MaxDomainControllers=@(1,200);CheckTimeoutSeconds=@(10,3600);NativeTimeoutSeconds=@(1,120);MinimumPasswordLength=@(1,128)}
    foreach ($k in $ranges.Keys) {
        if (($c.$k -isnot [int] -and $c.$k -isnot [long]) -or $c.$k -lt $ranges[$k][0] -or $c.$k -gt $ranges[$k][1]) { throw "Invalid integer range: $k" }
    }
    if ($c.NativeTimeoutSeconds -ge $c.CheckTimeoutSeconds) { throw 'NativeTimeoutSeconds must be less than CheckTimeoutSeconds.' }
    if ($c.Checks -isnot [array] -or @($c.Checks).Count -eq 0) { throw 'Checks must be a nonempty JSON array.' }
    if (@($c.Checks | Select-Object -Unique).Count -ne @($c.Checks).Count) { throw 'Duplicate check.' }
    foreach ($check in $c.Checks) { if ($check -notin $script:Checks) { throw "Unknown check: $check" } }
    $c
}
function Get-RelayCheckNames { $script:Checks }
function Get-RelayReplicationRow {
    param($Record,[string]$Target,[int]$MaxAgeHours,[datetime]$Now = [datetime]::UtcNow)
    $status='Pass'; $advice=''; $age=$null
    if ($null -ne $Record.LastReplicationSuccess) { $age=($Now.ToUniversalTime()-([datetime]$Record.LastReplicationSuccess).ToUniversalTime()).TotalHours }
    if ($null -eq $age -or $age -lt -0.1 -or $age -gt $MaxAgeHours -or $Record.LastReplicationResult -ne 0 -or $Record.ConsecutiveReplicationFailures -gt 0) {
        $status='Warning'; $advice='Review topology, site schedule, connectivity and replication errors. No synchronization was initiated.'
    }
    New-RelayRow Replication $Target $status 'Inbound replication partner observation' ($Record | Select-Object Partner,Partition,LastReplicationAttempt,LastReplicationSuccess,LastReplicationResult,ConsecutiveReplicationFailures | ConvertTo-Json -Compress) $advice
}
function Get-RelayInactiveFilter {
    param([datetime]$Cutoff)
    $ft=$Cutoff.ToUniversalTime().ToFileTimeUtc()
    $created=$Cutoff.ToUniversalTime().ToString('yyyyMMddHHmmss.0Z',[Globalization.CultureInfo]::InvariantCulture)
    # Enabled users/computers; recent never-used accounts are excluded.
    "(&(!(userAccountControl:1.2.840.113556.1.4.803:=2))(|(&(lastLogonTimestamp<=$ft)(lastLogonTimestamp>=1))(&(|(!(lastLogonTimestamp=*))(lastLogonTimestamp=0))(whenCreated<=$created))))"
}
function Invoke-RelayTimeQuery {
    param([string]$Target,[int]$TimeoutSeconds)
    if ($Target -notmatch '^[a-zA-Z0-9.-]+$') { throw 'Invalid time query target.' }
    $exe=Join-Path $env:SystemRoot 'System32/w32tm.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'w32tm.exe is unavailable.' }
    $si=New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName=$exe; $si.Arguments="/query /computer:$Target /status /verbose"; $si.UseShellExecute=$false
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true; $si.CreateNoWindow=$true
    $p=New-Object System.Diagnostics.Process; $p.StartInfo=$si
    try {
        [void]$p.Start()
        $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) { $p.Kill(); throw 'w32tm query timed out.' }
        $out=$stdout.GetAwaiter().GetResult(); $err=$stderr.GetAwaiter().GetResult()
        if ($p.ExitCode -ne 0) { throw "w32tm exit $($p.ExitCode): $out $err" }
        $out
    } finally { $p.Dispose() }
}
function Invoke-RelayCollector {
    [CmdletBinding()]
    param([string]$Check,$Config)
    $ErrorActionPreference='Stop'
    # Called only in explicit Live mode, in a bounded child job.
    Import-Module ActiveDirectory -ErrorAction Stop
    $server=$Config.Server
    $domain=Get-ADDomain -Server $server
    if ($domain.DNSRoot -ine $Config.Domain) { throw "Server returned domain '$($domain.DNSRoot)', not configured domain '$($Config.Domain)'." }
    $domainName=$domain.DNSRoot
    if ($Check -in @('DCInventory','Replication','DNS','SYSVOL','TimeSync')) {
        $dcs=@(Get-ADDomainController -Filter * -Server $server | Sort-Object HostName)
        if ($dcs.Count -eq 0) { throw 'No domain controllers returned.' }
        if ($dcs.Count -gt $Config.MaxDomainControllers) { throw 'DC count exceeds MaxDomainControllers; no partial inventory presented as complete.' }
        foreach ($dc in $dcs) {
            $target=[string]$dc.HostName
            if ($target -notmatch '^[a-zA-Z0-9.-]+$') { New-RelayRow $Check $target Error 'Invalid DC hostname'; continue }
            try {
                switch ($Check) {
                    DCInventory {
                        New-RelayRow $Check $target Info 'Domain controller inventory; availability not asserted' ($dc | Select-Object HostName,Site,IPv4Address,IPv6Address,OperatingSystem,OperatingSystemVersion,IsGlobalCatalog,IsReadOnly,Enabled | ConvertTo-Json -Compress)
                    }
                    Replication {
                        $partners=@(Get-ADReplicationPartnerMetadata -Target $target -Partition '*' -PartnerType Inbound)
                        if ($partners.Count -eq 0) { New-RelayRow $Check $target Info 'No inbound metadata returned' '' 'May be expected in a single-DC domain; verify topology. This is not proof of replication health.' }
                        foreach ($p in $partners) { Get-RelayReplicationRow $p $target $Config.ReplicationMaxAgeHours }
                    }
                    DNS {
                        # Query each DC as DNS server. Non-DNS DCs will be visibly inconclusive.
                        $query="_ldap._tcp.dc._msdcs.$domainName"
                        $records=@(Resolve-DnsName -Name $query -Type SRV -Server $target -DnsOnly -NoHostsFile -QuickTimeout | Where-Object { $_.Type -eq 'SRV' })
                        $names=@($records | ForEach-Object { $_.NameTarget.TrimEnd('.') })
                        if ($target -in $names) { $s='Pass' } else { $s='Warning' }
                        New-RelayRow $Check $target $s 'LDAP DC locator SRV query (this DC registration)' ($records | Select-Object Name,NameTarget,Port,Priority,Weight | ConvertTo-Json -Compress) 'Limited locator check; does not validate all zones, delegations or dynamic updates. Non-DNS DCs require separate resolver review.'
                        $addresses=@(Resolve-DnsName -Name $target -Type A_AAAA -Server $target -DnsOnly -NoHostsFile -QuickTimeout | Where-Object { $_.Type -in @('A','AAAA') })
                        if ($addresses.Count -eq 0) { throw 'No A/AAAA address records returned.' }
                        New-RelayRow $Check $target Pass 'DC hostname resolves through this DC' ($addresses | Select-Object Name,Type,IPAddress | ConvertTo-Json -Compress)
                    }
                    SYSVOL {
                        foreach ($share in @('SYSVOL','NETLOGON')) {
                            try {
                                $path='\\'+$target+'\'+$share
                                $item=Get-Item -LiteralPath $path -ErrorAction Stop
                                if (-not $item.PSIsContainer) { throw 'Share root is not a directory.' }
                                New-RelayRow $Check "$target/$share" Pass 'Share root readable from collector' $path 'This does not prove DFSR health or GPO file consistency.'
                            } catch { New-RelayRow $Check "$target/$share" Error 'Share check unavailable' $_.Exception.Message 'Review permissions, SMB connectivity and share state; do not infer DFSR failure from access denial.' }
                        }
                    }
                    TimeSync {
                        $out=Invoke-RelayTimeQuery $target $Config.NativeTimeoutSeconds
                        New-RelayRow $Check $target Info 'W32Time status collected; manual interpretation required' $out 'Review source, stratum, last successful sync and leap indicator. Localized output is not parsed. Clock offset and external-source correctness are not verified.'
                    }
                }
            } catch { New-RelayRow $Check $target Error 'Collection failed or access unavailable' $_.Exception.Message 'Review this target and rerun; unavailable evidence is not a healthy result.' }
        }
        return
    }
    switch ($Check) {
        FSMO {
            foreach ($role in @('PDCEmulator','RIDMaster','InfrastructureMaster')) { New-RelayRow $Check $domainName Info $role ([string]$domain.$role) 'Role ownership only; role-holder reachability is not verified.' }
            $forest=Get-ADForest -Server $server
            foreach ($role in @('SchemaMaster','DomainNamingMaster')) { New-RelayRow $Check $forest.Name Info $role ([string]$forest.$role) 'Forest role ownership only.' }
        }
        PrivilegedGroups {
            $groups=@(@{Sid="$($domain.DomainSID)-512";Server=$server},@{Sid='S-1-5-32-544';Server=$server},@{Sid='S-1-5-32-548';Server=$server},@{Sid='S-1-5-32-549';Server=$server},@{Sid='S-1-5-32-550';Server=$server},@{Sid='S-1-5-32-551';Server=$server},@{Sid="$($domain.DomainSID)-520";Server=$server})
            try {
                $forest=Get-ADForest -Server $server
                $root=Get-ADDomain -Identity $forest.RootDomain -Server $forest.RootDomain
                $groups+=@(@{Sid="$($root.DomainSID)-518";Server=$forest.RootDomain},@{Sid="$($root.DomainSID)-519";Server=$forest.RootDomain})
            } catch { New-RelayRow $Check 'Forest root' Error 'Enterprise/Schema Admins could not be enumerated' $_.Exception.Message }
            foreach ($g in $groups) {
                try {
                    $group=Get-ADGroup -Identity $g.Sid -Server $g.Server
                    # Direct membership preserves nested groups, rather than hiding them behind recursive leaf enumeration.
                    $members=@(Get-ADGroupMember -Identity $g.Sid -Server $g.Server)
                    New-RelayRow $Check $group.DistinguishedName Info 'Direct group membership count' ([string]$members.Count) 'Review every direct member and nested group. Effective privileges, primaryGroupID, delegation ACLs and trust paths are not fully enumerated.'
                    foreach ($m in $members) { New-RelayRow $Check $group.DistinguishedName Info 'Direct privileged group member' ($m | Select-Object Name,SamAccountName,objectClass,SID,DistinguishedName | ConvertTo-Json -Compress) 'Nested groups require separate review.' }
                } catch { New-RelayRow $Check $g.Sid Error 'Group enumeration unavailable' $_.Exception.Message }
            }
        }
        InactiveAccounts {
            $cutoff=[DateTime]::UtcNow.AddDays(-$Config.InactiveDays)
            $filter=Get-RelayInactiveFilter $cutoff
            foreach ($kind in @('User','Computer')) {
                try {
                    $args=@{LDAPFilter=$filter;Server=$server;SearchBase=$domain.DistinguishedName;Properties=@('lastLogonTimestamp','whenCreated','PasswordLastSet','Enabled');ResultPageSize=200;ResultSetSize=($Config.MaxAccountsPerType+1)}
                    if ($kind -eq 'User') { $accounts=@(Get-ADUser @args) } else { $accounts=@(Get-ADComputer @args) }
                    if ($accounts.Count -gt $Config.MaxAccountsPerType) { New-RelayRow $Check $kind Warning 'Result limit exceeded; inventory is incomplete' "Limit=$($Config.MaxAccountsPerType)" 'Increase limit deliberately or investigate a narrower scope separately.' }
                    if ($accounts.Count -eq 0) { New-RelayRow $Check $kind Info 'No enabled inactivity candidates returned' "CutoffUtc=$($cutoff.ToString('o'))" 'lastLogonTimestamp is replicated and approximate; absence is not proof of recent activity.' }
                    foreach ($a in ($accounts | Select-Object -First $Config.MaxAccountsPerType)) {
                        $last='Never recorded'
                        if ($a.lastLogonTimestamp -and [long]$a.lastLogonTimestamp -gt 0) { $last=[datetime]::FromFileTimeUtc([long]$a.lastLogonTimestamp).ToString('o') }
                        New-RelayRow $Check $a.DistinguishedName Warning 'Enabled inactivity candidate; not a deletion recommendation' "Type=$kind; LastLogonTimestampUtc=$last; Created=$($a.whenCreated); PasswordLastSet=$($a.PasswordLastSet)" 'Confirm business owner and actual usage. Replicated timestamps may lag roughly 9-14 days under default settings; service accounts can be legitimate.'
                    }
                } catch { New-RelayRow $Check $kind Error 'Account enumeration unavailable' $_.Exception.Message }
            }
        }
        PasswordPolicy {
            $policies=@(Get-ADDefaultDomainPasswordPolicy -Identity $domainName -Server $server)
            foreach ($p in $policies) { Write-RelayPasswordRow $p $domainName $Config.MinimumPasswordLength }
            try {
                $fine=@(Get-ADFineGrainedPasswordPolicy -Filter * -Server $server)
                if ($fine.Count -eq 0) { New-RelayRow $Check $domainName Info 'No fine-grained password policies returned' }
                foreach ($p in $fine) { Write-RelayPasswordRow $p $p.DistinguishedName $Config.MinimumPasswordLength }
            } catch { New-RelayRow $Check $domainName Error 'Fine-grained password policies unavailable' $_.Exception.Message }
        }
        GPOInventory {
            Import-Module GroupPolicy -ErrorAction Stop
            $gpos=@(Get-GPO -All -Domain $domainName -Server $server)
            New-RelayRow $Check $domainName Info 'GPO count' ([string]$gpos.Count) 'Inventory only; no links, resultant policy, permissions or AD/SYSVOL version comparison.'
            foreach ($gpo in $gpos) { New-RelayRow $Check ([string]$gpo.Id) Info $gpo.DisplayName ($gpo | Select-Object DisplayName,Id,Owner,GpoStatus,CreationTime,ModificationTime | ConvertTo-Json -Compress) }
        }
        default { throw "Unknown collector: $Check" }
    }
}
function Write-RelayPasswordRow {
    param($Policy,[string]$Target,[int]$MinimumLength)
    $status='Info'
    if ($Policy.MinPasswordLength -lt $MinimumLength -or $Policy.ReversibleEncryptionEnabled) { $status='Warning' }
    New-RelayRow PasswordPolicy $Target $status 'Password policy inventory / configured baseline' ($Policy | Select-Object MinPasswordLength,ComplexityEnabled,ReversibleEncryptionEnabled,PasswordHistoryCount,MinPasswordAge,MaxPasswordAge,LockoutThreshold,LockoutDuration,LockoutObservationWindow | ConvertTo-Json -Compress) "Configured minimum length=$MinimumLength. No universal compliance verdict. Fine-grained resultant policy per user is not evaluated."
}
function Invoke-RelayBoundedCheck {
    param([string]$Check,$Config,[string]$ModulePath)
    $job=$null
    try {
        $job=Start-Job -ScriptBlock {
            param($path,$name,$settings)
            $ErrorActionPreference='Stop'
            Import-Module $path -Force
            try { Invoke-RelayCollector -Check $name -Config $settings } catch { New-RelayRow $name $settings.Domain Error 'Collector unavailable' $_.Exception.Message 'Review module, domain connectivity and read permissions.' }
        } -ArgumentList $ModulePath,$Check,$Config
        $done=Wait-Job $job -Timeout $Config.CheckTimeoutSeconds
        if ($null -eq $done) {
            Stop-Job $job
            Receive-Job $job -ErrorAction SilentlyContinue
            New-RelayRow $Check $Config.Domain Error 'Check timed out; results incomplete' "TimeoutSeconds=$($Config.CheckTimeoutSeconds)" 'Partial observations may precede this row. Investigate unreachable services or adjust the bound.'
        } else {
            $rows=@(Receive-Job $job -ErrorAction Stop)
            $rows
            if ($job.State -ne 'Completed' -or $rows.Count -eq 0) { New-RelayRow $Check $Config.Domain Error 'Collector returned no complete result' ([string]$job.JobStateInfo.Reason) }
        }
    } catch { New-RelayRow $Check $Config.Domain Error 'Job failed' $_.Exception.Message }
    finally { if ($null -ne $job) { Remove-Job $job -Force -ErrorAction SilentlyContinue } }
}
function ConvertTo-RelaySafeCell {
    param($Value)
    $s=[string]$Value
    # Prefix formula-like content, including leading whitespace/control characters.
    if ($s -match '^[\s\x00-\x1F]*[=+@-]' -or $s -match '^[\t\r\n]') { return "'$s" }
    $s
}
function Export-RelayReport {
    param([object[]]$Rows,[string]$Directory,[ValidateSet('Demo','Live')][string]$Mode,[string]$RunId,$Config)
    if (Test-Path -LiteralPath $Directory) { throw 'Output run directory already exists; refusing to overwrite or mix reports.' }
    [void](New-Item -ItemType Directory -Path $Directory -ErrorAction Stop)
    $all=@(foreach ($r in $Rows) {
        [pscustomobject][ordered]@{RunId=$RunId;Mode=$Mode;Check=$r.Check;Target=$r.Target;Status=$r.Status;Summary=$r.Summary;Evidence=$r.Evidence;Recommendation=$r.Recommendation;CollectedAtUtc=$r.CollectedAtUtc}
    })
    $safe=@(foreach ($r in $all) {
        $h=[ordered]@{}; foreach ($p in $r.PSObject.Properties) { $h[$p.Name]=ConvertTo-RelaySafeCell $p.Value }; [pscustomobject]$h
    })
    $safe | Export-Csv -LiteralPath (Join-Path $Directory 'findings.csv') -NoTypeInformation -Encoding UTF8
    foreach ($check in $script:Checks) { $subset=@($safe | Where-Object Check -eq $check); if ($subset.Count) { $subset | Export-Csv -LiteralPath (Join-Path $Directory ($check+'.csv')) -NoTypeInformation -Encoding UTF8 } }
    $counts=[ordered]@{}; foreach ($s in @('Pass','Warning','Error','Info','Skipped')) { $counts[$s]=@($all | Where-Object Status -eq $s).Count }
    $meta=[ordered]@{Product='RELAY AD Health Toolkit';Version='0.1.0';Mode=$Mode;RunId=$RunId;GeneratedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Counts=$counts;Config=$Config;Scope='One configured domain; forest FSMO and root privileged groups also queried';Interpretation='No overall healthy verdict. Info/Skipped/Error are not Pass.'}
    $meta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'manifest.json') -Encoding UTF8
    $banner=if ($Mode -eq 'Demo') { 'SYNTHETIC DEMO - NO REAL DIRECTORY DATA' } else { 'LIVE DIRECTORY DATA - CONFIDENTIAL - DO NOT PUBLISH' }
    $enc={param($v) [System.Net.WebUtility]::HtmlEncode([string]$v)}
    $body=New-Object System.Text.StringBuilder
    [void]$body.Append('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>RELAY AD Health Toolkit</title><style>body{background:#10181a;color:#e4eeee;font:15px system-ui,sans-serif;margin:0}main{max-width:1400px;margin:auto;padding:2rem}h1,h2{color:#85e6b0}a{color:#85e6b0}.banner{border:2px solid #e9bb69;padding:1rem;font-weight:bold}.table{overflow:auto}table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{border:1px solid #415455;text-align:left;padding:.7rem;vertical-align:top}th{background:#203436}td{white-space:pre-wrap;overflow-wrap:anywhere}p{line-height:1.6}.Warning,.Error{color:#ffd68b}footer{margin:2rem 0;color:#b8c7c7}</style></head><body><main>')
    [void]$body.Append("<p>RELAY / n0hup &middot; COMMUNITY EDITION &middot; v0.1.0</p><h1>AD Health Toolkit</h1><p class='banner'>$banner</p><p>Run: $(& $enc $RunId) &middot; $(& $enc $meta.GeneratedUtc)</p><p>Observations, not a security certification. Pass covers only the named check; inaccessible and untested areas remain unknown. Time sync and inventories require review.</p>")
    [void]$body.Append('<p>'+(& $enc (($counts.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ' | '))+'</p>')
    foreach ($check in $script:Checks) {
        $subset=@($all | Where-Object Check -eq $check)
        if (-not $subset.Count) { continue }
        [void]$body.Append("<h2>$check</h2><div class='table'><table><thead><tr><th scope='col'>Status / target</th><th scope='col'>Observation</th><th scope='col'>Evidence</th><th scope='col'>Next step</th></tr></thead><tbody>")
        foreach ($r in $subset) { [void]$body.Append("<tr><td>$(& $enc $r.Status)<br>$(& $enc $r.Target)</td><td>$(& $enc $r.Summary)</td><td>$(& $enc $r.Evidence)</td><td>$(& $enc $r.Recommendation)</td></tr>") }
        [void]$body.Append('</tbody></table></div>')
    }
    [void]$body.Append('<footer>Need environment-specific checks or help interpreting findings? <a href="https://n0hup.codeberg.page/tailored.html?service=Tailored%20solution#request">Discuss a tailored solution</a>. Share a non-confidential brief, not this live report. No data is sent by opening this report.</footer></main></body></html>')
    $body.ToString() | Set-Content -LiteralPath (Join-Path $Directory 'report.html') -Encoding UTF8
    $reportFiles=@(Get-ChildItem -LiteralPath $Directory -File)
    $reportFiles | Get-FileHash -Algorithm SHA256 | Select-Object @{n='File';e={Split-Path $_.Path -Leaf}},Hash | Export-Csv -LiteralPath (Join-Path $Directory 'checksums.csv') -NoTypeInformation -Encoding UTF8
}
Export-ModuleMember -Function Get-RelayCheckNames,Read-RelayConfig,New-RelayRow,Get-RelayReplicationRow,Get-RelayInactiveFilter,Invoke-RelayCollector,Invoke-RelayBoundedCheck,ConvertTo-RelaySafeCell,Export-RelayReport
