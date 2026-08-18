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

Pushing the tag triggers `.github/workflows/release.yml`. The workflow verifies that the tag and `Info.plist` version match, runs the checks, creates an ad-hoc signed Universal 2 build, and creates the GitHub Release using the matching file under `docs/releases/`.

## Signing

`make release` uses the stable local Benri identity when available and otherwise falls back to ad-hoc signing. These builds are for local testing. To build with a Developer ID identity already installed in the Keychain:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make release
```

The GitHub workflow uses ad-hoc signing and does not notarize the archive. These builds may require Control-clicking the app and choosing **Open** on first launch.
