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
   shasum -a 256 -c dist/Benri-vX.Y.Z-macOS-universal.zip.sha256
   ```

6. Commit the release, create the tag, and push:

   ```bash
   git tag -a vX.Y.Z -m "Benri vX.Y.Z"
   git push origin main vX.Y.Z
   ```

Pushing the tag triggers `.github/workflows/release.yml`, which runs the checks, rebuilds the Universal 2 archive, and creates the GitHub Release using the matching file under `docs/releases/`.

## Signing and notarization

`make release` uses ad-hoc signing by default. To use a Developer ID identity already installed in the Keychain:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" make release
```

A Developer ID release should also be submitted with `notarytool` and stapled before public distribution. Do not describe an artifact as notarized unless both notarization and `stapler validate` succeed on that exact artifact.
