# DMG installer

For exact published versions, checksums and notarization results, use [GitHub release notes](https://github.com/kuil09/lens/releases).

## Layout and constraints

The image presents two native 96-point targets: Lens on the left and Applications on the right, with an arrow and English/Korean/Japanese installation instructions. The license stays at the image root but is hidden from the install view. No custom installer app or runtime dependency is added.

Artwork is a 144-DPI, 720-by-440-point background in a 720-by-472-point Finder window. Fixed light artwork does not follow dark mode. Background text is raster, not VoiceOver text; native file names remain accessible and [README](../README.md#get-started) has equivalent instructions. Full assistive-technology and multi-scale acceptance must be recorded per candidate.

Do not set `hide_extensions` on the signed app: Finder attributes previously invalidated its strict signature even after notarization acceptance. Always check the app *inside* the finished image.

## Packaging-only setup

App compilation and ZIP packaging do not require these Python packages. For DMGs, use the ignored environment and pinned requirements:

```sh
python3 -m venv .packaging-tools
.packaging-tools/bin/pip install -r Packaging/requirements.txt
PATH="$PWD/.packaging-tools/bin:$PATH" make package ARGS='--development --format dmg'
```

The command consumes an existing app and emits a nonnotarized development filename. It does not sign, notarize, launch or publish; see [Releasing](releasing.md#development-packaging) for its validation contract. Use the path and checksum printed by the command rather than a previous release's filename.

To intentionally regenerate the checked-in background on macOS:

```sh
xcrun swift Tools/DMGBackground.swift Packaging/background.tiff
```

Inspect the generated artwork and actual Finder layout before committing that visual change. This is not required for documentation checks or ordinary packaging.

## Artifact verification

The [protected CI workflow](ci-notarization.md) signs/notarizes the app and DMG separately. After ticket attachment, verify the image checksum/integrity and read-only mount. Compare the contained app to the signed build; check its strict signature, ticket and Gatekeeper result, license bytes, Applications link, icon and metadata. Recompute SHA-256 after signing/stapling, never before the final mutation.

These artifact checks do not prove installation, real capture/translation, or accessibility. Follow [release gates and recovery](releasing.md#release-gates-and-recovery), including checks on the public redownload. Do not disable Gatekeeper or strip quarantine to make an installer pass.
