#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Demo','Live')][string]$Mode='Demo',
    [string]$ConfigPath=(Join-Path $PSScriptRoot 'config/community.json'),
    [string]$OutputRoot=(Join-Path $PSScriptRoot 'reports')
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    $modulePath=Join-Path $PSScriptRoot 'src/Relay.ADHealth.psm1'
    Import-Module $modulePath -Force
    $config=Read-RelayConfig $ConfigPath
    $runId=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $rows=@()
    if ($Mode -eq 'Demo') {
        # No live collectors, RSAT imports, AD discovery or network calls on this branch.
        $fixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'demo/synthetic.json') -Raw | ConvertFrom-Json
        if ($fixture.Mode -ne 'Synthetic' -or $fixture.SchemaVersion -ne 1) { throw 'Invalid synthetic fixture.' }
        foreach ($check in Get-RelayCheckNames) {
            if ($check -notin $config.Checks) { $rows+=New-RelayRow $check 'demo.example.test' Skipped 'Disabled in configuration'; continue }
            foreach ($r in @($fixture.Rows | Where-Object Check -eq $check)) { $rows+=New-RelayRow $r.Check $r.Target $r.Status $r.Summary $r.Evidence $r.Recommendation }
        }
        # Never include user-configured live domain/server identifiers in a demo manifest.
        $config.Domain='demo.example.test'; $config.Server='dc01.demo.example.test'
    } else {
        $preflight=''
        if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
            $preflight='Live v0.1 requires 64-bit Windows PowerShell 5.1 (Desktop). PowerShell 7 is supported for demo/tests only.'
        } elseif (-not (Get-Module -ListAvailable ActiveDirectory)) { $preflight='ActiveDirectory RSAT module not installed. Toolkit never installs dependencies.' }
        foreach ($check in Get-RelayCheckNames) {
            Write-Host "RELAY: $check"
            if ($check -notin $config.Checks) { $rows+=New-RelayRow $check $config.Domain Skipped 'Disabled in configuration' }
            elseif ($preflight) { $rows+=New-RelayRow $check $config.Domain Error 'Preflight failed; no live query attempted' $preflight }
            else { $rows+=@(Invoke-RelayBoundedCheck $check $config $modulePath) }
        }
    }
    if ($rows.Count -eq 0) { throw 'No report rows produced.' }
    $destination=Join-Path (Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $Mode.ToLowerInvariant()) $runId
    Export-RelayReport $rows $destination $Mode $runId $config
    Write-Host "Report: $(Join-Path $destination 'report.html')"
    if (@($rows | Where-Object Status -eq 'Error').Count) { exit 2 }
    if (@($rows | Where-Object Status -eq 'Warning').Count) { exit 1 }
    exit 0
} catch {
    Write-Error -Message ("RELAY could not complete: "+$_.Exception.Message) -ErrorAction Continue
    exit 3
}
