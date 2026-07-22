<p align="center">
  <img src="Resources/benri-icon-readme.png" width="128" height="128" alt="Benri app icon">
</p>

<h1 align="center">Benri</h1>

<p align="center">
  A fast, local-first macOS panel for reusable text.<br>
  Find a note, copy it, and paste it back into your current app without breaking your flow.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a>
  ·
  <a href="https://github.com/crimsonteps/benri/releases/latest">Download</a>
  ·
  <a href="https://github.com/crimsonteps/benri/issues">Report a bug</a>
</p>

<p align="center">
  <a href="https://github.com/crimsonteps/benri/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/crimsonteps/benri/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

Benri is a lightweight menu bar utility for text you use repeatedly: server commands, account details, addresses, URLs, templates, snippets, and notes. Press a global shortcut, search by title, and press `Return` to copy the selected content and paste it into the app you were using.

Everything stays on your Mac. Benri has no account system, analytics, network requests, cloud service, or third-party runtime dependencies.

## Highlights

- Global launcher, configurable as `⌥Space`, `⌃Space`, `⌥⌘Space`, or `⌃⌥Space`
- Keyboard-first navigation across categories, records, and content
- Free-form multi-line content with automatic saving
- Custom categories plus four built-in categories
- Search by record title
- Copy-only fallback when Accessibility permission is unavailable
- Light, dark, reduced-transparency, and macOS 26 Liquid Glass support
- Local AES-256-GCM encrypted storage
- No Dock icon, network access, telemetry, or cloud synchronization

## Requirements

- macOS 13 Ventura or later
- Accessibility permission only if you want Benri to paste automatically into another app

## Install

1. Download the latest `Benri-vX.Y.Z-macOS-universal.zip` from [Releases](https://github.com/crimsonteps/benri/releases/latest).
2. Unzip it and move `Benri.app` to `/Applications`.
3. Open Benri and optionally grant Accessibility permission when macOS asks.

Community builds are ad-hoc signed unless a release explicitly says it is notarized. On first launch, macOS may require you to Control-click the app, choose **Open**, and confirm once. You can also allow it from **System Settings → Privacy & Security**.

## Keyboard workflow

| Shortcut | Action |
| --- | --- |
| Configurable global shortcut | Show or hide Benri |
| `↑` / `↓` | Move through categories or records |
| `Return` | Copy the selected record and paste into the previous app |
| `⌘←` / `⌘→` | Move between columns |
| `⌘N` | Create a record |
| `⌘S` or `⌘Return` | Save in the record editor |
| `⌘,` | Open Settings |
| `Esc` | Close the editor or hide the panel |

If automatic paste is not permitted or cannot complete, the content remains on the system clipboard so you can paste it manually.

## Privacy and security

Benri stores its data in its own Application Support directory:

```text
~/Library/Application Support/Benri/vault.qv
~/Library/Application Support/Benri/vault.key
```

On the first launch after upgrading, Benri safely copies and verifies an existing `QuickVault` data directory, loads the migrated vault, and only then removes the old directory.

- The vault is encrypted as one AES-256-GCM payload.
- The randomly generated 32-byte key and vault file are both restricted to the current user with `0600` permissions; the containing directory uses `0700`.
- Benri does not send data over the network.
- Benri never silently replaces a vault that it cannot decrypt.
- Resetting the vault permanently deletes the encrypted data and its local key.

The key is stored under the same macOS user account to avoid a password or Keychain prompt on every launch. This protects data at rest from casual disclosure, but it does **not** protect against software or a person that already has access to your logged-in account. Content copied from Benri also enters the macOS clipboard and follows normal system clipboard behavior. Benri is a convenience utility, not a replacement for a dedicated password manager.

Please report security issues through [GitHub's private security advisory form](https://github.com/crimsonteps/benri/security/advisories/new), not a public issue. See [SECURITY.md](SECURITY.md).

## Build from source

Benri is a Swift Package Manager app with no external package dependencies. Xcode or the macOS Command Line Tools with Swift 6 are sufficient.

```bash
git clone https://github.com/crimsonteps/benri.git
cd benri
make test
make app
open dist/Benri.app
```

Useful commands:

```bash
make build       # Debug build
make test        # Run the zero-dependency checks
make app         # Build an app for the current architecture
make release     # Build a Universal 2 zip and SHA-256 checksum
make clean
```

When built with an older SDK, Benri automatically uses the system Material appearance. Builds made with the macOS 26 SDK use native Liquid Glass on macOS 26 while keeping the same macOS 13 deployment target.

## Project structure

```text
Sources/QuickVault/        AppKit and SwiftUI application
Sources/QuickVaultCore/    Models, encryption, key, and file storage
Sources/QuickVaultChecks/  Zero-dependency automated checks
Resources/                 Info.plist and app icon source
Scripts/                   App and release packaging
```

## Scope

Version 1 focuses on a reliable local workflow. Cloud sync, browser autofill, import/export, password generation, launch at login, and cross-platform support are not currently included.

## Contributing

Bug reports and focused pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change. Maintainers can find the release checklist in [RELEASING.md](RELEASING.md).

## License

Benri is available under the [MIT License](LICENSE).
