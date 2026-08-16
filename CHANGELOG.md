# Changelog

All notable changes to Benri are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Local text and image clipboard history with search, pinning, source metadata, retention controls, excluded applications, and direct paste.
- A second optional global shortcut that opens clipboard history directly.

### Changed

- Reworked the main panel as a dark keyboard-first command palette with Common Text and Clipboard modes.
- The main panel now uses a fixed dark appearance while Settings follows the system appearance.
- Removed category controls from the reusable-text workflow; existing vault data remains compatible.
- Replaced the system Actions menus with a keyboard-navigable in-palette `⌘K` panel and a shared Paste/Actions footer control.

### Security

- Clipboard monitoring requires an explicit first-use confirmation, skips common sensitive pasteboard markers, and can be disabled or cleared independently.
- Clipboard history is a plaintext cache and is intentionally excluded from encrypted `.benribackup` packages.

## [1.1.0] - 2026-07-25

### Added

- Validated `.benribackup` packages containing the encrypted vault, matching key, and a metadata-only manifest.
- Manual backup and restore commands in the app and menu bar menus.
- Automatic recovery backup before replacing a healthy vault during restore.
- User-initiated diagnostic reports that exclude record names and content.
- A manual “Check for Updates” command that opens the official Releases page without adding background network activity.

### Changed

- Completed the public Benri bundle identifier and storage naming transition.
- Tightened keyboard navigation, automatic paste reliability, panel behavior, and glass styling.
- Updated GitHub Actions to `actions/checkout@v7`.
- Public tag builds now require Developer ID signing and Apple notarization before a GitHub Release is created.
- Release automation uploads only the Universal 2 archive; SHA-256 remains visible in GitHub's asset metadata.

### Fixed

- Prevented public releases whose tag does not match the app version.
- Prevented ad-hoc-signed builds from being uploaded as official GitHub releases.
- Added validation and rollback behavior so a damaged or mismatched backup cannot silently replace the active vault.

## [1.0.0] - 2026-07-22

### Added

- Global keyboard launcher with four configurable shortcuts.
- Category-based record browsing and title search.
- Free-form multi-line records with inline editing and automatic saving.
- Keyboard-first copy-and-paste workflow back to the previously active app.
- Custom category creation, rename, deletion, and safe record migration.
- Appearance, menu bar icon, panel position, and panel size preferences.
- AES-256-GCM local vault encryption and strict file permissions.
- Migration from legacy record fields and legacy Keychain-backed keys.
- Explicit recovery UI when a vault cannot be decrypted.
- Zero-dependency checks for model migration, encryption, and file storage.
- Universal 2 release packaging and automated GitHub release workflow.

[Unreleased]: https://github.com/crimsonteps/benri/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/crimsonteps/benri/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/crimsonteps/benri/releases/tag/v1.0.0
