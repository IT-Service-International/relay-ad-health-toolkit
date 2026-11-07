# RELAY AD Health Toolkit

**v0.1.0 Community Edition · read-only on-premises Active Directory diagnostics**

A small PowerShell toolkit for collecting bounded AD observations into local HTML and CSV reports. No remediation, cloud calls, telemetry, credential prompts or dependency installation. MIT licensed.

**Release status:** community preview. Offline tests and synthetic reporting have been exercised on PowerShell 7.6.9/macOS. Live Windows PowerShell 5.1/RSAT integration has **not** been run in an AD lab. Do not describe this release as production-certified or fully Windows-tested. See [validation](docs/VALIDATION.md).

[RELAY Engineering](https://n0hup.codeberg.page/) · [Engineering services](https://n0hup.codeberg.page/services.html) · [Tailored solutions](https://n0hup.codeberg.page/tailored.html)

## Start with the synthetic demo

```powershell
# Windows PowerShell 5.1, or PowerShell 7 on Windows/macOS/Linux
./Invoke-RelayADHealth.ps1 -Mode Demo
```

Demo is also the default when `-Mode` is omitted. It loads **only** the bundled fictional observations in `demo/synthetic.json`; it does not query AD or import RSAT. Reports are placed in `reports/demo/<unique-run>/`. Open the printed `report.html` path. A ready-made report is in [demo/sample/report.html](demo/sample/report.html).

The demo deliberately includes warnings and a simulated DNS collection error: **exit code 2 is expected**. It demonstrates report presentation, not a live collector integration test. Real identifiers in a supplied configuration are replaced with reserved demo identifiers in the demo manifest.

## Run against one approved domain

Read [requirements and compatibility](docs/REQUIREMENTS.md), review the source, and complete [lab acceptance](docs/VALIDATION.md) first.

1. Use a domain-joined management workstation with **64-bit Windows PowerShell 5.1**, RSAT AD PowerShell and Group Policy Management tools already installed.
2. Copy `config/community.json` to `config/customer.local.json` and set `Domain` and `Server` to the approved domain and a DC FQDN in that domain. The server's returned domain is checked before collection.
3. Run under your existing Windows identity with the approved read permissions. No passwords or tokens are requested. Domain Admin membership is not a prerequisite; inaccessible checks are reported as errors.
4. Store output in an existing access-controlled local parent folder outside public repositories or shared sync folders. The tool inherits folder ACLs; it does not change them.

```powershell
# In 64-bit Windows PowerShell 5.1, from the toolkit folder:
.\Invoke-RelayADHealth.ps1 -Mode Live `
  -ConfigPath .\config\customer.local.json `
  -OutputRoot C:\RELAY-Private\Reports
```

Live mode is intentionally blocked on PowerShell 7 and non-Windows hosts for v0.1. Microsoft lists the AD module as natively compatible with PowerShell 7 on appropriate Windows versions, but GroupPolicy as untested with its compatibility layer. We use one conservative live runtime rather than silently changing engines. See [verified Microsoft references](docs/API-COMPATIBILITY.md).

No execution policy is changed or bypassed. If organisational policy requires signed scripts, arrange internal review/signing through the normal process.

## Coverage and limits

| Check | What is collected / assessed | Important limit |
|---|---|---|
| DCInventory | Hostname, site, addresses, OS, GC/RODC/enabled flags | Inventory does not establish service availability |
| FSMO | Three domain roles and two forest roles | Ownership only, no transfer or role-holder liveness test |
| Replication | Inbound partner metadata across all partitions on each DC; last result, failure count, stale success | No forced synchronization; threshold must fit site schedules; no partners is inconclusive |
| DNS | LDAP DC locator SRV and DC A/AAAA lookup using each DC as resolver | Assumes DC also serves DNS; non-DNS DC is inconclusive; not a complete DNS audit |
| SYSVOL | Readable SYSVOL and NETLOGON share roots on each DC | Not DFSR backlog, convergence or file/version consistency |
| TimeSync | Read-only remote `w32tm /query /status /verbose` | Raw localized output; manual source/sync review, no drift measurement or automatic healthy verdict |
| PrivilegedGroups | SID-based direct members of Domain Admins, Administrators, four operator groups, Group Policy Creator Owners, forest-root Schema/Enterprise Admins | Nested groups preserved; not an effective privilege graph, primary-group or ACL/delegation audit |
| InactiveAccounts | Enabled user/computer candidates based on replicated logon timestamp and creation age | Approximate; disabled accounts omitted; never-used recent accounts excluded; no deletion recommendation |
| PasswordPolicy | Default policy and fine-grained policy inventory; configurable minimum length and reversible-encryption flag | No per-user resultant policy or compliance certification |
| GPOInventory | ID, name, status, owner and timestamps | No links, effective settings, permissions or AD/SYSVOL consistency analysis |

The main scope is **one configured domain**. Forest-wide FSMO ownership and two forest-root privileged groups are also read; other domains are not automatically inventoried. LDAP account queries are limited per object type. Each category runs sequentially in its own local child job with a deadline. Within a category, target errors are isolated where possible; any partial results remain alongside an explicit error. With all defaults, ten category deadlines can total about 30 minutes plus job startup/cleanup. Large environments may need different bounds.

## Configuration

JSON is data only, never executed. Unknown keys, missing keys, invalid FQDNs, duplicated/unknown checks, noninteger values and out-of-range limits are rejected.

| Key | Default | Meaning |
|---|---:|---|
| `SchemaVersion` | 1 | Fixed schema |
| `Domain`, `Server` | fictional FQDNs | Explicit approved live scope; edit before live use |
| `Checks` | all ten | Selected check names; others get `Skipped` rows |
| `InactiveDays` | 90 | Candidate age (1–3650 days) |
| `ReplicationMaxAgeHours` | 24 | Stale-success threshold (1–720 hours) |
| `MaxAccountsPerType` | 5000 | Output cap per user/computer query (1–100000); fetches one extra to detect truncation |
| `MaxDomainControllers` | 25 | Safety ceiling (1–200); excess produces an error, not silent truncation |
| `CheckTimeoutSeconds` | 180 | Entire category deadline including module import (10–3600 seconds) |
| `NativeTimeoutSeconds` | 10 | Each W32Time process deadline (1–120; less than category deadline) |
| `MinimumPasswordLength` | 14 | Local review baseline (1–128), not a universal policy mandate |

## Reports and exit codes

Each run creates a fresh directory under **either** `demo/` **or** `live/`; existing run directories are refused. Outputs:

- `report.html`: self-contained, no scripts, embedded remote assets or automatic network requests; an optional external CTA is a plain link.
- `findings.csv` and one CSV per check: fixed columns, UTF-8, quoted cells, formula-like text prefixed with an apostrophe.
- `manifest.json`: version, runtime, mode, scope, configuration, timestamps, status counts.
- `checksums.csv`: SHA-256 of report artifacts (excluding itself); integrity inventory, not a signature or tamper-proof audit log.

CSV fields: `RunId, Mode, Check, Target, Status, Summary, Evidence, Recommendation, CollectedAtUtc`. Evidence may contain compact JSON or multiline native output. CSV safety prefixes deliberately change formula-like text; the HTML preserves its encoded display text.

`Pass` = only the named assertion succeeded. `Warning` = review candidate/threshold/limit. `Error` = missing or failed evidence, including timeout/access denial. `Info` = collected evidence without an automated health verdict. `Skipped` = disabled check. There is **no overall green health score**. Counts describe observations, not risk severity.

| Exit | Meaning |
|---:|---|
| 0 | Report written; no Warning/Error rows (may still contain Info/Skipped) |
| 1 | Report written; warnings, no collection errors |
| 2 | Report written; at least one error, possibly incomplete coverage |
| 3 | Fatal configuration/reporting failure; no complete report guaranteed |

## Safety and privacy

Read-only refers to infrastructure configuration. Queries generate normal network traffic, authentication events, service logs and load. The tool writes local reports and manages its own local jobs. It never changes AD objects, DNS records, group membership, GPOs, services, time configuration or execution policy; it does not run `dcdiag /fix`, replication sync, repair, install or resync commands.

Live reports contain sensitive directory names, memberships and operational details. They are **not anonymized**. Never publish live output or customer configuration. Errors may also contain internal identifiers. `.gitignore` is a convenience, not a data-loss-prevention control. See [SECURITY.md](SECURITY.md).

## Test, publish, extend

```powershell
./tests/Run-Tests.ps1
```

Tests are offline and dependency-free: parser/static guard checks, mock collectors, status logic, error paths, timeout cleanup, HTML/CSV defenses, output isolation and entry-point smoke tests. They do not connect to a directory. [Validation evidence and Windows lab steps](docs/VALIDATION.md) distinguish what has been executed from what remains unverified.

[Codeberg publishing instructions](docs/PUBLISH-CODEBERG.md) target a **new** `n0hup/relay-ad-health-toolkit` repository. The existing `n0hup/pages` site is not modified. This AI-assisted community preview is being published at the maintainer's request for manual review. Human review and live validation remain pending. See the publishing guide for the current Codeberg hosting-policy notice; publication does not imply an exemption or endorsement.

Community Edition provides these checks under MIT without a support SLA. Tailored work can add agreed organisation-specific checks, evidence interpretation, reporting and integrations. Commercial scope, delivery rights and support are agreed separately; existing Community Edition rights remain MIT. Send only a non-confidential brief through [Tailored Solutions](https://n0hup.codeberg.page/tailored.html?service=Tailored%20solution#request).
