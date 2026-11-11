# Publish a separate repository on Codeberg

Repository: **[n0hup/relay-ad-health-toolkit](https://codeberg.org/n0hup/relay-ad-health-toolkit)**. The maintainer requested publication for subsequent manual code review. The existing `n0hup/pages` repository is not part of this change.

## Before upload

The maintainer must review and understand the code, decide whether to maintain it, run the Windows/AD lab acceptance and accurately retain the preview/validation limitations. Do not claim human review or live validation that has not happened.

**Hosting-policy notice (2026-11-07):** Codeberg's [Terms of Use §2(1)7](https://codeberg.org/Codeberg/org/src/branch/main/TermsOfUse.md#user-content-2-allowed-content-usage) restrict projects mostly consisting of generative-AI-written code. After being informed of this rule, the account owner explicitly requested publication under `n0hup` for their subsequent manual review and edits. That request is not an exemption from Codeberg's rules or an endorsement from Codeberg. Human review alone should not be assumed to change provenance or waive the rule. The maintainer is responsible for resolving hosting eligibility.

The instructions below describe the initial creation workflow and future release preparation. Do not reinitialize or overwrite the published repository. No credentials or new terms acceptance were requested in this chat. 
## Create the empty repository

Follow [Codeberg's first-repository guide](https://docs.codeberg.org/getting-started/first-repository/):

1. Sign in yourself and create a repository owned by `n0hup`, named `relay-ad-health-toolkit`.
2. Description: `Read-only on-prem Active Directory diagnostics with PowerShell, local HTML/CSV reports and an isolated synthetic demo. Community preview.`
3. Choose public visibility only for reviewed source and synthetic data. Leave repository initialization, README and licence templates off because they are supplied here. Main branch: `main`.
4. Do not upload any customer config, live report, credential file or local run folder.

## Push the prepared source

Run from the extracted `relay-ad-health-toolkit` directory, **not** from the site repository or your general Documents folder. Commands assume a newly created, empty remote and your already configured Git identity/authentication.

```sh
git init -b main
git add .gitignore .gitattributes LICENSE README.md SECURITY.md CHANGELOG.md Invoke-RelayADHealth.ps1 src config/community.json demo docs tests
git diff --cached --stat
git diff --cached
# Inspect the staged content; only fictional demo data should be included.
git commit -m "Release RELAY AD Health Toolkit v0.1.0 community preview"
git remote add origin https://codeberg.org/n0hup/relay-ad-health-toolkit.git
git push -u origin main
git tag -a v0.1.0 -m "v0.1.0 Community Edition preview"
git push origin v0.1.0
```

Do not paste a token into a command or remote URL. Use your existing credential manager or an already-configured SSH identity. If the remote is not empty, inspect it and reconcile the histories; do **not** force-push.

After pushing, verify the public README, source tree and synthetic HTML/CSV files, then create a release for `v0.1.0`. Title: `RELAY AD Health Toolkit v0.1.0 — Community Edition preview`. Use `docs/RELEASE-NOTES.md`, and attach the reviewed source ZIP and its SHA-256 file if desired. Do not mark a Windows/AD integration test as passed until you have executed it.

## Site integration after the repository exists

The current website is `https://n0hup.codeberg.page/` and its source is `https://codeberg.org/n0hup/pages`. Add a small product card in a separate site change after confirming the destination URL:

- **RELAY AD Health Toolkit — Community Edition**
- `Read-only Active Directory observations. Local HTML/CSV reports. Windows PowerShell 5.1 + RSAT. Community preview; review the documented limitations.`
- Primary link: `https://codeberg.org/n0hup/relay-ad-health-toolkit`
- Secondary link: a deployed copy of **only** `demo/sample/report.html`, labelled `View synthetic demo`.
- Commercial link: `https://n0hup.codeberg.page/tailored.html?service=Tailored%20solution#request` with label `Request tailored checks`.

No links in the existing site were changed by this delivery. The standalone report already offers the commercial link without sending any report data. Publishing the HTML demo to the site is optional; a repository HTML view may show source rather than render it.
