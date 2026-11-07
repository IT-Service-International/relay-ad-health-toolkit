# Security and data handling

No secrets are needed by the program. Do not add passwords, access tokens, credential files or customer exports to issues, commits, support requests or demo fixtures.

The entry point defaults to offline Demo. Live requires an explicit flag and uses the current Windows identity. All directory operations are reads. No remediation, downloads, execution policy changes, remote script execution or scheduled task creation is implemented. Local child jobs isolate deadlines; the script writes reports only to the specified output tree. It does not secure that tree's inherited permissions.

Live reports are confidential inventories, including privileged identities and internal error messages. Publishing even a read-only report may expose useful infrastructure details. Share only with authorised reviewers and apply your organisation's retention/deletion policy. Do not send a live report via the public commercial CTA. Synthetic files use example.test and documentation IP ranges and have no derivation from customer data.

HTML text is encoded and contains no JavaScript. CSV cells beginning with spreadsheet formula triggers are prefixed with an apostrophe. Re-importing, transforming or re-exporting CSV with another application can remove this protection; treat it as evidence text, not executable spreadsheet content.

Report a reproducible security issue privately to the contact shown on [RELAY Tailored Solutions](https://n0hup.codeberg.page/tailored.html). Begin with a non-sensitive description; agree a secure evidence exchange separately. Do not publish exploit details containing customer data in a public issue. No response-time SLA is implied for Community Edition.
