# Security Policy

## Supported versions

Security fixes are provided for the latest released version of Benri.

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| Earlier development builds | No |

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use [GitHub's private security advisory form](https://github.com/crimsonteps/benri/security/advisories/new) and include:

- The affected Benri version and macOS version
- Clear reproduction steps
- The expected and observed behavior
- The security impact you believe is possible
- Any proof-of-concept files with secrets removed

Reports are handled on a best-effort basis. Confirmed issues will be assessed, fixed privately where practical, and disclosed with an appropriate release.

## Security model

Benri is a local convenience utility. Its encrypted vault and local key are stored under the same macOS user account with restrictive file permissions. This protects against casual disclosure of the vault file, but it is not designed to protect data from software or people that already control the logged-in account. Clipboard contents are also subject to normal macOS clipboard access.
