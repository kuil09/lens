# DMG installer and notarization

Current download: **beta.5/build 15**. See [build-15 verification](releases/build-15-validation.md) and [release notes](releases/v0.1.0-beta.5.md). The build-11 artifact, installed-app state, and checks below are historical installer-design evidence, not claims about the current download.

## Artifact boundary — September 15, 2026

The owner explicitly resumed Apple notarization after observing Gatekeeper block the downloaded beta.4 app. This is automated Apple security checking for external distribution, not App Store submission. Beta.5/build 11 retains `dev.local.lens`, the existing Developer ID signer, and the unchanged application implementation. Only version metadata, signing timestamp, installer tooling/artwork, and documentation changed.

- Release artifact: `Lens-0.1.0-beta.5-11.dmg` and its SHA-256 sidecar, retained locally under `dist/`.
- SHA-256 after stapling: `10a83adc9e712a85c2ce82892f7482933bf8de7cdc7cfca69958c16ad3264ba0`.
- After local acceptance the owner separately authorized history cleanup and GitHub publication. The beta.5 release distributes this exact notarized file; earlier tags and release records remain unchanged. See [release notes](releases/v0.1.0-beta.5.md).
- The installed `/Applications/Lens.app` remains build 10. This work did not change permissions, installed language packs, preferences, or export folders, and did not launch or install build 11.
- The withdrawn build 3 was not reused. Existing Keychain authentication was sufficient; no password was copied into source, logs, or chat.

## Installer review

| Reproduction | Observed problem and impact | Change and verification |
| --- | --- | --- |
| Open the beta.4 DMG in Finder | Small unstructured icons, visible license as a third target, and no installation direction obscure the next step. | Two native 96-point targets, source on the left and Applications on the right, a directional arrow, and concise English/Korean/Japanese copy. License remains at the root but is hidden from the install view. |
| Open the first artwork prototype | Bitmap scaling and Finder titlebar space caused clipped text. | A 144-DPI, 720-by-440-point background and 720-by-472-point window; the final Finder screenshot includes the footer without clipping. |
| Strictly verify the app inside the first styled image | `hide_extensions` added `com.apple.FinderInfo` to the signed bundle; strict signature checking failed despite Apple accepting the submission. | Do not modify app Finder attributes. Regression assertions prohibit this setting; the corrected mounted app passes strict signature, ticket, and Gatekeeper checks and matches the source app's files. |

The artwork uses native typography and an SF Symbol. The actual Lens app and Finder Applications alias remain the draggable items. No custom installer app, extra permissions, or app runtime dependency was added. Fixed light artwork does not follow dark mode. Background text is raster, not VoiceOver text; native file names remain accessible, and equivalent installation instructions are in README. A full assistive-technology journey and additional display scales were not tested.

## Packaging-only setup

App compilation and ZIP packaging do not require Python packages. For DMGs, use a project-local, ignored environment:

```sh
python3 -m venv .packaging-tools
.packaging-tools/bin/pip install -r Packaging/requirements.txt
PATH="$PWD/.packaging-tools/bin:$PATH" make package ARGS='--development --format dmg'
```

This wrapper still produces an explicitly nonnotarized development filename and does not sign, notarize, launch, or publish. Its public-identifier gate is unchanged and remains inactive; the existing `dev.local.lens` identity has not been silently reclassified as the configured public identifier.

To regenerate the checked-in background on macOS:

```sh
xcrun swift Tools/DMGBackground.swift Packaging/background.tiff
```

The separately authorized build 11 candidate was built with the existing local Developer ID configuration, `OTHER_CODE_SIGN_FLAGS=--timestamp`, and unchanged bundle identity. Its signed app was zipped using `ditto`, submitted to Apple, and stapled after acceptance. A new DMG was then made from that exact app with the same layout settings used by the wrapper:

```sh
# Use a new output path; never overwrite a published artifact.
.packaging-tools/bin/dmgbuild -s scripts/dmg-settings.py \
  -D root="$PWD" -D app="$PWD/build-design/Build/Products/Release/Lens.app" \
  -D background="$PWD/Packaging/background.tiff" Lens /path/to/new-candidate.dmg
```

Inspect the mounted app with `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=2` before signing/submitting the DMG. After the DMG's own acceptance, staple and validate it, assess it using `spctl --assess --type open --context context:primary-signature --verbose=2`, remount it, and repeat the contained-app checks. Compare the contained app files with the source build, the license with the repository license, and the Applications link with `/Applications`. Compute the published checksum only after all signing/stapling mutations.

Authentication uses an existing Keychain profile. New Apple submissions and GitHub publication require the owner's corresponding authorization. Never disable Gatekeeper or strip quarantine to make a check pass. See Apple's [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Exact verification

- Release build 11 succeeded with secure timestamp and hardened runtime.
- App submission `d6de3b00-e554-4202-afcd-b020155fe88b`: **Accepted**; app ticket stapled and validated.
- Final corrected DMG submission `2abbb522-2ceb-4f0c-a5db-8ef3ec297c9d`: **Accepted**; DMG ticket stapled and validated. The earlier styled image was rejected locally for its Finder attribute problem and is not the deliverable.
- Both final DMG and its contained app: **accepted**, `source=Notarized Developer ID`; strict app signature and source-file comparison passed. No security bypass was used.
- Final checksum check, compressed-image verification, license comparison, and Applications symlink check passed.
- `make check`: 49 repository-index assertions, 49 shell regressions, and 4 installer-settings tests passed. These do not replace signing or UI checks.
- Actual Finder inspection: large aligned native targets, direction, all three guidance languages, and unclipped footer. The normal DMG opening flow was exercised, not only an artwork preview.
- Application logic tests were not rerun for this packaging-only change. The prior build 10 record remains separate. New build 11 installation/launch, clean-Mac or quarantined browser-download execution, offline execution, full VoiceOver use, and translation runtime acceptance remain unverified.

Notarization acceptance is not a whole-product quality or performance certification. The previously installed/downloaded beta.4 remains unnotarized; only this exact new candidate receives the above result. A normal first-download confirmation may still appear on macOS even for accepted apps.
