# Contributing to Benri

Thanks for helping improve Benri. Focused bug reports, accessibility improvements, tests, documentation fixes, and small pull requests are especially welcome.

## Before opening an issue

- Search existing issues first.
- Use the bug report form for reproducible problems.
- Use the feature request form for new behavior.
- Do not post secrets, vault contents, keys, or private system logs.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Development setup

Requirements:

- macOS 13 or later
- Swift 6 through Xcode or the macOS Command Line Tools

```bash
git clone https://github.com/crimsonteps/benri.git
cd benri
make test
make app
open dist/Benri.app
```

Benri has no external Swift package dependencies. The automated checks are implemented as the `QuickVaultChecks` executable so they also work on minimal Command Line Tools installations.

## Pull requests

1. Keep each pull request limited to one clear problem.
2. Match the existing Swift and UI style.
3. Add or update checks when behavior changes.
4. Run `make test` and `make app` before submitting.
5. Update the README or changelog when user-visible behavior changes.
6. Never include real vault files, keys, credentials, or personal records.

Maintainers may ask to split broad refactors from behavior changes so each change remains reviewable.

## Commit messages

Use short, imperative commit subjects, for example:

```text
Fix focus restoration after paste
Add validation for future vault formats
Document first-launch Gatekeeper flow
```

## Release process

Maintainer release instructions are in [RELEASING.md](RELEASING.md).
