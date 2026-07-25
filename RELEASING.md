# Releasing Benri

Benri uses semantic versions and tags releases as `vMAJOR.MINOR.PATCH`.

## Checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Move completed entries from `Unreleased` into a dated section in `CHANGELOG.md`.
3. Add `docs/releases/vX.Y.Z.md` with public release notes.
4. Run the checks and create a Universal 2 archive:

   ```bash
   make test
   make release
   ```

5. Verify the bundle and archive:

   ```bash
   codesign --verify --deep --strict --verbose=2 dist/Benri.app
   lipo -archs dist/Benri.app/Contents/MacOS/Benri
   shasum -a 256 dist/Benri-vX.Y.Z-macOS-universal.zip
   ```

6. Commit the release, create the tag, and push:

   ```bash
   git tag -a vX.Y.Z -m "Benri vX.Y.Z"
   git push origin main vX.Y.Z
   ```

Pushing the tag triggers `.github/workflows/release.yml`. The workflow verifies that the tag and `Info.plist` version match, runs the checks, creates a Developer ID signed Universal 2 build, notarizes and staples it, verifies Gatekeeper acceptance, and creates the GitHub Release using the matching file under `docs/releases/`.

## Signing and notarization

`make release` uses the stable local Benri identity when available and otherwise falls back to ad-hoc signing. These builds are for local testing. To build with a Developer ID identity already installed in the Keychain:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make release
```

The official GitHub workflow refuses to publish unless all of these repository secrets are configured:

- `APPLE_DEVELOPER_ID_APPLICATION_P12`: Base64-encoded Developer ID Application certificate and private key.
- `APPLE_DEVELOPER_ID_APPLICATION_PASSWORD`: Password for the exported `.p12`.
- `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY`: Full identity, such as `Developer ID Application: Name (TEAMID)`.
- `APPLE_ID`: Apple ID used by `notarytool`.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.

The workflow submits the exact archive with `notarytool`, staples the resulting ticket to `Benri.app`, rebuilds the archive, and requires both `stapler validate` and `spctl --assess` to pass. Do not describe any other artifact as notarized.
