# Validation evidence and lab acceptance

## Executed locally, 2026-11-07

Environment: macOS, PowerShell **7.6.9**. Command: `pwsh -NoProfile -File tests/Run-Tests.ps1`.

**59 assertions passed.** No real directory, customer data, privileged credentials, infrastructure mutation or remote installation was used. `TEST-RESULTS.txt` contains the captured result with temporary local paths reduced to placeholders.

Covered behavior:

- PowerShell parser checks for shipped scripts and module; static guard against selected remote mutation/download commands. This is a regression guard, not a proof of arbitrary-code safety or PS 5.1 certification.
- Configuration: required/unknown keys, integer types/ranges, invalid hostname input, duplicate checks.
- Replication: recent, stale, missing-success and failure-status cases; all-partition/inbound arguments asserted by mock.
- Inactivity filter: disabled-account exclusion and old-creation requirement for never-used candidates; output cap and explicit truncation warning.
- All ten collectors exercised with module-scoped synthetic fakes; no live APIs used.
- Access denial is an error; empty replication is inconclusive; unexpected domain rejected.
- Real local background-job timeout and job cleanup, using a harmless sleeping fake collector.
- HTML injection encoding, CSV formula-prefix handling and normal text preservation.
- Separate mode labels, refusing existing output directories, report SHA-256 consistency.
- Entry-point Demo execution; expected exit 2 for synthetic DNS error; Info-only selection exit 0 with nine explicit Skipped rows; live config identifiers removed from demo manifest.
- Invalid configuration exit 3 without output; unsupported Live runtime exit 2 with all ten checks marked untested.

Sample artifact hashes and local Markdown links were also verified. Browser visual preview was not performed: local HTTP binding was unavailable in this environment and the browser policy rejected file:// navigation. HTML structure and escaping were checked programmatically.

A complete synthetic sample is included under `demo/sample`. It demonstrates rendering and data provenance; it is not evidence that Windows, RSAT or a real AD installation was tested.

## Not executed / not claimed

- Windows PowerShell 5.1 parsing/execution and native RSAT command binding.
- Live AD Web Services, replication rights, GPO access, SMB share access or remote W32Time.
- Real forest-root group discovery, localized Windows output and multi-domain/trust behavior.
- Large directory performance and actual firewall/timeout behavior.
- Cryptographic signing, independent security review or production acceptance.

## Windows lab acceptance (operator-run, read-only toolkit)

Use an already-provisioned, authorised lab. The toolkit must not create test accounts, change policies or simulate outages in production. Select existing conditions or use isolated test doubles for failure injection.

1. On Windows PowerShell 5.1 x64 with RSAT, run `tests/Run-Tests.ps1`. Save engine/module versions and results privately. Expected: all applicable offline assertions pass; the two unsupported-runtime assertions are skipped on the intended Windows Desktop runtime.
2. Run Demo and confirm it succeeds in generating the report without access to a directory. Check its labels, CSV quoting and HTML in a local browser. Exit 2 is expected for the sample.
3. Prepare a private config for one lab domain and a DC; choose bounds appropriate to lab size. Run Live with an approved read identity. Confirm every selected category has evidence or an explicit Error, never an unexplained missing section.
4. Compare DC inventory and five FSMO role owners with the authorised administration consoles. Test a multi-DC and, if available, single-DC domain; no inbound partner metadata must remain Info rather than Pass.
5. Cross-check replication partner partitions, timestamps and last result with the read-only AD management output. Verify the stale threshold fits actual schedules; no replication sync is initiated.
6. Compare locator SRV and A/AAAA answers using the named DC resolver. A DC without DNS must remain an unavailable/inconclusive check. Verify SYSVOL/NETLOGON root access separately; do not infer DFSR consistency.
7. Compare the raw `w32tm /query` output with a manual read-only query, including a localized Windows host. Confirm no resync/configuration command runs. Test unavailable access in an isolated lab and confirm bounded error reporting.
8. Compare direct privileged group members by SID, including a nested group and forest-root groups. Explicitly record that effective/nested privileges and primary-group membership are outside scope.
9. Compare inactivity candidates with known enabled old user/computer objects, a recent never-used object, a disabled object, and the configured cap. Validate the replicated-timestamp caveat before making personnel/account decisions.
10. Compare default and fine-grained password policies and GPO inventory. Test GroupPolicy missing/unreadable cases without altering production; the category must report Error, other categories must remain available.
11. Exercise timeout and partial-output reporting using the offline fake in the tests. Check cancellation leaves no toolkit background job behind. Record any native process left by a forced outer-job termination for investigation.
12. Review reports for correct mode, data exposure, hashes, UTF-8 text and output ACL inheritance. Inspect process/service logs in the lab for unexpected remote writes. Any suspected mutation blocks release until explained.

Record: OS/build, `$PSVersionTable`, AD/GroupPolicy module versions, domain topology, delegated permissions, config thresholds, start/end UTC, per-check result, observed defects, reviewer and explicit release decision. Keep raw live evidence out of the public repository; publish only a sanitised validation summary if authorised.
