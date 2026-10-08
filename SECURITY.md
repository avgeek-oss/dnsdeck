# Security

Report a suspected vulnerability privately to support@dnsdeck.dev. Include
the affected version, reproduction steps, and expected impact. Do not include
working credentials or private zone contents in a public issue.

DNSDeck stores provider credentials in Apple Keychain and connects directly
to provider APIs. It does not require an Avgeek account or hosted backend.
The local MCP companion can access the environments and credentials available
to the app; connect it only to clients you trust.

Use narrowly scoped API credentials and revoke them at the provider if a
device or token is compromised. Exported DNS records and local diagnostics
can contain sensitive domain information even without API tokens.
