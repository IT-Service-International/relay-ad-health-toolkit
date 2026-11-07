#requires -Version 5.1
# Offline tests, no Pester dependency and no directory access.
[CmdletBinding()]param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$modulePath=Join-Path $root 'src/Relay.ADHealth.psm1'
Import-Module $modulePath -Force
$script:passed=0
function Assert($Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:passed++; Write-Host "PASS: $Name" }
function Assert-Throws([scriptblock]$Action,[string]$Name) { $threw=$false; try { & $Action | Out-Null } catch { $threw=$true }; Assert $threw $Name }
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('relay-tests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tmp)
try {
    foreach ($f in Get-ChildItem $root -Recurse -File | Where-Object Extension -in @('.ps1','.psm1')) {
        $tokens=$null; $errors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) "PowerShell parser: $($f.Name)"
        if ($f.DirectoryName -eq (Join-Path $root 'src') -or $f.Name -eq 'Invoke-RelayADHealth.ps1') {
            $commands=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() })
            Assert (@($commands | Where-Object { $_ -match '^(Set|Add|Remove|New|Enable|Disable|Move|Reset|Unlock|Sync|Restore|Install|Uninstall)-(AD|GPO|GPLink|GPRegistry|Dns|WindowsFeature)' -or $_ -in @('Invoke-Expression','Invoke-WebRequest','Invoke-RestMethod','Invoke-Command') }).Count -eq 0) "No remote mutation/download commands: $($f.Name)"
        }
    }
    $c=Read-RelayConfig (Join-Path $root 'config/community.json')
    Assert (@($c.Checks).Count -eq 10) 'Ten configured checks'
    $configPath=Join-Path $tmp 'invalid.json'
    foreach ($case in @('Unknown','Range','Host','Duplicate','Missing','Type')) {
        $bad=$c | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        switch ($case) {
            Unknown { $bad | Add-Member NoteProperty SurprisingKey 1 }
            Range { $bad.InactiveDays=0 }
            Host { $bad.Server='dc.example.test /resync' }
            Duplicate { $bad.Checks=@('DNS','DNS') }
            Missing { $bad.PSObject.Properties.Remove('Server') }
            Type { $bad.InactiveDays='90' }
        }
        $bad | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
        Assert-Throws { Read-RelayConfig $configPath } "Reject configuration: $case"
    }
    foreach ($v in @('=SUM(A1)','+cmd','-cmd','@SUM(A1)',"`t=1",'  =1')) { Assert ((ConvertTo-RelaySafeCell $v).StartsWith("'")) "CSV formula defense: $($v.Trim())" }
    Assert ((ConvertTo-RelaySafeCell 'normal') -eq 'normal') 'Ordinary CSV text preserved'
    $now=[datetime]'2026-11-07T10:00:00Z'
    $p=[pscustomobject]@{Partner='dc02';Partition='DC=example';LastReplicationAttempt=$now;LastReplicationSuccess=$now.AddHours(-1);LastReplicationResult=0;ConsecutiveReplicationFailures=0}
    Assert ((Get-RelayReplicationRow $p dc01 24 $now).Status -eq 'Pass') 'Recent replication passes'
    $p.LastReplicationSuccess=$now.AddHours(-25)
    Assert ((Get-RelayReplicationRow $p dc01 24 $now).Status -eq 'Warning') 'Stale replication warns'
    $p.LastReplicationSuccess=$null
    Assert ((Get-RelayReplicationRow $p dc01 24 $now).Status -eq 'Warning') 'Missing replication success warns'
    $p.LastReplicationSuccess=$now; $p.LastReplicationResult=1722
    Assert ((Get-RelayReplicationRow $p dc01 24 $now).Status -eq 'Warning') 'Replication error warns'
    $filter=Get-RelayInactiveFilter $now
    Assert ($filter.Contains('whenCreated<=20261107100000.0Z') -and $filter.Contains('1.2.840.113556.1.4.803:=2')) 'Inactivity filter excludes disabled and newly created unused accounts'
    $rows=@(New-RelayRow DNS '<script>alert(1)</script>' Error 'A & B' '=HYPERLINK("x")' 'Review <b>manually</b>')
    $out=Join-Path $tmp 'report'
    Export-RelayReport $rows $out Demo 'test-run' $c
    $html=Get-Content (Join-Path $out 'report.html') -Raw
    Assert (-not $html.Contains('<script>') -and $html.Contains('&lt;script&gt;')) 'HTML encoding prevents injected markup'
    $csv=Import-Csv (Join-Path $out 'findings.csv')
    Assert ($csv.Evidence.StartsWith("'=")) 'CSV export neutralizes formulas'
    Assert ($html.Contains('SYNTHETIC DEMO') -and $csv.Mode -eq 'Demo') 'Demo report is clearly labeled'
    Assert-Throws { Export-RelayReport $rows $out Live 'other' $c } 'Existing output cannot be overwritten or mixed'
    $liveOut=Join-Path $tmp 'live-report'
    Export-RelayReport $rows $liveOut Live 'test-live' $c
    Assert ((Get-Content (Join-Path $liveOut 'report.html') -Raw).Contains('CONFIDENTIAL - DO NOT PUBLISH')) 'Live confidentiality banner'
    foreach ($h in Import-Csv (Join-Path $out 'checksums.csv')) { Assert ((Get-FileHash (Join-Path $out $h.File) -Algorithm SHA256).Hash -eq $h.Hash) "Checksum: $($h.File)" }

    # Module-scoped fakes intercept all collection dependencies, even on Windows.
    $m=Get-Module 'Relay.ADHealth'
    & $m {
        function script:Import-Module { param($Name,$ErrorAction) }
        function script:Get-ADDomain { param($Server,$Identity)
            [pscustomobject]@{DNSRoot='demo.example.test';DistinguishedName='DC=demo,DC=example,DC=test';DomainSID='S-1-5-21-1-2-3';PDCEmulator='dc01.demo.example.test';RIDMaster='dc01.demo.example.test';InfrastructureMaster='dc01.demo.example.test'}
        }
        function script:Get-ADForest { param($Server) [pscustomobject]@{Name='demo.example.test';RootDomain='demo.example.test';SchemaMaster='dc01.demo.example.test';DomainNamingMaster='dc01.demo.example.test'} }
        function script:Get-ADDomainController { param($Filter,$Server) [pscustomobject]@{HostName='dc01.demo.example.test';Site='Test';IPv4Address='192.0.2.10';IPv6Address=$null;OperatingSystem='Synthetic';OperatingSystemVersion='0';IsGlobalCatalog=$true;IsReadOnly=$false;Enabled=$true} }
        function script:Get-ADReplicationPartnerMetadata { param($Target,$Partition,$PartnerType) if ($Partition -ne '*' -or $PartnerType -ne 'Inbound') { throw 'Incorrect replication scope' }; [pscustomobject]@{Partner='dc02.demo.example.test';Partition='DC=demo';LastReplicationAttempt=[datetime]::UtcNow;LastReplicationSuccess=[datetime]::UtcNow;LastReplicationResult=0;ConsecutiveReplicationFailures=0} }
        function script:Resolve-DnsName { param($Name,$Type,$Server,[switch]$DnsOnly,[switch]$NoHostsFile,[switch]$QuickTimeout)
            if ($Type -eq 'SRV') { [pscustomobject]@{Type='SRV';Name=$Name;NameTarget='dc01.demo.example.test.';Port=389;Priority=0;Weight=100} } else { [pscustomobject]@{Type='A';Name=$Name;IPAddress='192.0.2.10'} }
        }
        function script:Get-Item { param($LiteralPath,$ErrorAction) [pscustomobject]@{PSIsContainer=$true} }
        function script:Invoke-RelayTimeQuery { param($Target,$TimeoutSeconds) 'SYNTHETIC raw localized status' }
        function script:Get-ADGroup { param($Identity,$Server) [pscustomobject]@{DistinguishedName="CN=$Identity,DC=demo"} }
        function script:Get-ADGroupMember { param($Identity,$Server) [pscustomobject]@{Name='demo';SamAccountName='demo';objectClass='group';SID='S-1-5-21-1-2-3-999';DistinguishedName='CN=demo,DC=demo'} }
        function script:Get-ADUser { param($LDAPFilter,$Server,$SearchBase,$Properties,$ResultPageSize,$ResultSetSize)
            [pscustomobject]@{DistinguishedName='CN=old,DC=demo';lastLogonTimestamp=[datetime]::UtcNow.AddDays(-180).ToFileTimeUtc();whenCreated=[datetime]::UtcNow.AddDays(-200);PasswordLastSet=[datetime]::UtcNow.AddDays(-190);Enabled=$true}
        }
        function script:Get-ADComputer { param($LDAPFilter,$Server,$SearchBase,$Properties,$ResultPageSize,$ResultSetSize) }
        function script:Get-ADDefaultDomainPasswordPolicy { param($Identity,$Server) [pscustomobject]@{MinPasswordLength=8;ReversibleEncryptionEnabled=$false} }
        function script:Get-ADFineGrainedPasswordPolicy { param($Filter,$Server) }
        function script:Get-GPO { param([switch]$All,$Domain,$Server) [pscustomobject]@{Id='00000000-0000-4000-8000-000000000001';DisplayName='Demo GPO';Owner='DEMO';GpoStatus='AllSettingsEnabled';CreationTime=[datetime]::UtcNow;ModificationTime=[datetime]::UtcNow} }
    }
    foreach ($check in Get-RelayCheckNames) {
        $result=@(Invoke-RelayCollector $check $c)
        Assert ($result.Count -gt 0 -and @($result | Where-Object Status -eq 'Error').Count -eq 0) "Mocked collector: $check"
    }
    & $m { function script:Get-ADReplicationPartnerMetadata { param($Target,$Partition,$PartnerType) throw 'Simulated denied' } }
    Assert (@(Invoke-RelayCollector Replication $c)[0].Status -eq 'Error') 'Access denial is Error, never Pass'
    & $m { function script:Get-ADReplicationPartnerMetadata { param($Target,$Partition,$PartnerType) } }
    Assert (@(Invoke-RelayCollector Replication $c)[0].Status -eq 'Info') 'Empty replication is inconclusive'
    $wrong=$c | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $wrong.Domain='wrong.example.test'
    Assert-Throws { Invoke-RelayCollector FSMO $wrong } 'Reject wrong-domain server'
    & $m { function script:Get-ADUser { param($LDAPFilter,$Server,$SearchBase,$Properties,$ResultPageSize,$ResultSetSize)
        1..2 | ForEach-Object { [pscustomobject]@{DistinguishedName="CN=old$_,DC=demo";lastLogonTimestamp=$null;whenCreated=[datetime]::UtcNow.AddDays(-200);PasswordLastSet=$null;Enabled=$true} }
    } }
    $limited=$c | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $limited.MaxAccountsPerType=1
    $result=@(Invoke-RelayCollector InactiveAccounts $limited)
    Assert (@($result | Where-Object Summary -like 'Result limit*').Count -eq 1) 'Truncation is explicit'
    Assert (@($result | Where-Object Target -like 'CN=old*').Count -eq 1) 'Account cap is honored'
    Remove-Module Relay.ADHealth
    Import-Module $modulePath -Force
    # Exercise actual job timeout with a harmless offline fake module.
    $fake=Join-Path $tmp 'Slow.psm1'
    @'
function Invoke-RelayCollector { param($Check,$Config) Start-Sleep -Seconds 15 }
function New-RelayRow { param($Check,$Target,$Status,$Summary,$Evidence,$Recommendation) [pscustomobject]@{Check=$Check;Target=$Target;Status=$Status;Summary=$Summary;Evidence=$Evidence;Recommendation=$Recommendation;CollectedAtUtc='test'} }
Export-ModuleMember -Function Invoke-RelayCollector,New-RelayRow
'@ | Set-Content $fake -Encoding UTF8
    $fast=$c | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $fast.CheckTimeoutSeconds=1
    $result=@(Invoke-RelayBoundedCheck DNS $fast $fake)
    Assert (@($result | Where-Object { $_.Status -eq 'Error' -and $_.Summary -like '*timed out*' }).Count -eq 1) 'Bounded job timeout is reported'
    Assert (@(Get-Job).Count -eq 0) 'Jobs cleaned up'
    $engine=(Get-Process -Id $PID).Path
    & $engine -NoProfile -File (Join-Path $root 'Invoke-RelayADHealth.ps1') -Mode Demo -OutputRoot (Join-Path $tmp 'demo')
    Assert ($LASTEXITCODE -eq 2) 'Demo returns 2 for deliberately simulated collection error'
    $custom=$c | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $custom.Domain='private.example.test'; $custom.Server='private-dc.example.test'; $custom.Checks=@('DCInventory')
    $customPath=Join-Path $tmp 'custom.json'; $custom | ConvertTo-Json -Depth 5 | Set-Content $customPath -Encoding UTF8
    & $engine -NoProfile -File (Join-Path $root 'Invoke-RelayADHealth.ps1') -Mode Demo -ConfigPath $customPath -OutputRoot (Join-Path $tmp 'limited-demo')
    Assert ($LASTEXITCODE -eq 0) 'Info-only demo exit 0 does not imply complete health'
    $limitedRows=@(Get-ChildItem (Join-Path $tmp 'limited-demo') -Recurse -Filter findings.csv | ForEach-Object { Import-Csv $_.FullName })
    Assert (@($limitedRows | Where-Object Status -eq 'Skipped').Count -eq 9) 'Disabled checks visibly skipped'
    $limitedMeta=Get-ChildItem (Join-Path $tmp 'limited-demo') -Recurse -Filter manifest.json | Get-Content -Raw
    Assert (-not $limitedMeta.Contains('private.example.test') -and -not $limitedMeta.Contains('private-dc')) 'Live configuration identifiers do not leak into demo'
    try {
        $ErrorActionPreference='Continue' # Windows PowerShell may surface native stderr as an error record.
        & $engine -NoProfile -File (Join-Path $root 'Invoke-RelayADHealth.ps1') -ConfigPath $configPath -OutputRoot (Join-Path $tmp 'invalid-run')
        $fatalCode=$LASTEXITCODE
    } finally { $ErrorActionPreference='Stop' }
    Assert ($fatalCode -eq 3) 'Malformed config exit 3'
    Assert (-not (Test-Path (Join-Path $tmp 'invalid-run'))) 'Malformed config writes no report'
    $manifest=Get-ChildItem (Join-Path $tmp 'demo') -Recurse -Filter manifest.json | Get-Content -Raw | ConvertFrom-Json
    Assert ($manifest.Mode -eq 'Demo' -and $manifest.Config.Domain -eq 'demo.example.test') 'Demo manifest provenance'
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
        & $engine -NoProfile -File (Join-Path $root 'Invoke-RelayADHealth.ps1') -Mode Live -OutputRoot (Join-Path $tmp 'preflight')
        Assert ($LASTEXITCODE -eq 2) 'Unsupported live runtime blocked with report'
        $findings=Get-ChildItem (Join-Path $tmp 'preflight') -Recurse -Filter findings.csv | ForEach-Object { Import-Csv $_.FullName }
        Assert (@($findings | Where-Object Status -eq 'Error').Count -eq 10) 'Every live check marked untested after preflight failure'
    }
    Write-Host "SUCCESS: $script:passed assertions. Offline tests only; Windows/AD acceptance remains required."
} finally {
    Remove-Module Relay.ADHealth -ErrorAction SilentlyContinue
    # Only remove this test's generated GUID directory, never user reports.
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
