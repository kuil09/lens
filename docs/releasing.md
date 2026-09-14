# Releasing and manual acceptance

## Candidate status

- Planned primary app version: **0.1.0**, build **1**.
- First tag candidate: **v0.1.0-beta.1 — unreleased**. No release date or published artifact is asserted.
- Some translation has been observed by a user; formal whole-runtime acceptance remains incomplete.
- The approved [MIT License](../LICENSE), copyright **2026 kuil09**, is present. Inclusion in the final distribution still needs verification.
- The current development bundle identifier is `dev.local.lens`; the public identifier is pending an owner decision.
- Signing/notarization, final icon, translation quality, and end-to-end performance are not validated.

Recheck version, build, channel, and `PrivacyInfo.xcprivacy` on the exact distribution artifact after signing and packaging. Local build success is not a public-signing result, a CI result, or whole-runtime acceptance.

Building or packaging does not authorize or perform publication. Development packaging must be explicitly selected; public packaging requires the license, signing, and notarization gates below.

## Packaging contract

`make check`, `make test`, and `make build` wrap `scripts/lens.sh`; see [development](development.md) for the canonical `build-design` workflow. Quit the selected app before packaging. `make package ARGS='--development'` explicitly produces a development ZIP and checksum from the existing Release app. It does not build, sign, notarize, launch, or publish.

Both modes require a nonempty repository license and validate bundle version/build/channel, arm64 executable support, minimum macOS metadata matching `Config/Application.xcconfig` in both the bundle and executable (currently 26.4), and a valid bundled privacy manifest. Without `--development`, packaging additionally requires an owner-confirmed public identifier passed through `--confirmed-distribution-id` that matches both `Config/Distribution.xcconfig` and the app, Developer ID Application signing with a valid team and hardened runtime, a successful notarized Gatekeeper assessment, and a valid stapled ticket. `--app` can select an existing Lens.app by absolute physical path. Signing and notarization must already be complete; the package command only validates them.

The public identifier is currently blank, so public packaging is blocked. Once the gates are met, it writes `dist/Lens-0.1.0-beta.1-1.zip` and a `.zip.sha256` sidecar without overwriting existing files. Both ZIP variants contain `Lens.app` and `LICENSE` at the archive root; the privacy manifest stays inside the app's resources. Verify these entries in the actual archive. Package validation is not a substitute for manual acceptance or publication approval.

## Manual Developer ID build and notarization

These are future maintainer steps, not commands run by documentation work or automation. Keep `Config/Distribution.xcconfig`'s public identifier blank until the owner approves it. After approval, set that configuration to the confirmed identifier and fill the empty values below. The team identifier and Keychain profile name are not credentials. A valid Developer ID Application certificate/private key must already be available to Xcode, and the named notarization credentials must already be stored in Keychain. Never put passwords, API keys, or private-key material in these commands or the repository.

Use the same shell for the following steps, from the repository root. The temporary build keeps the canonical `build-design` app and its development identity intact. These commands invoke Xcode directly because `make build` deliberately uses ad-hoc development signing.

```sh
set -eu
LENS_PUBLIC_ID=''
LENS_TEAM_ID=''
LENS_NOTARY_PROFILE=''
: "${LENS_PUBLIC_ID:?Set the owner-confirmed identifier matching Distribution.xcconfig}"
: "${LENS_TEAM_ID:?Set the Developer ID signing team identifier}"
: "${LENS_NOTARY_PROFILE:?Set an existing Keychain profile name}"
LENS_RELEASE_DD="$(mktemp -d /private/tmp/lens-derived-data.XXXXXX)"
LENS_RELEASE_APP="$LENS_RELEASE_DD/Build/Products/Release/Lens.app"

xcodebuild -project Lens.xcodeproj -scheme Lens -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$LENS_RELEASE_DD" \
  -xcconfig Config/Distribution.xcconfig \
  DEVELOPMENT_TEAM="$LENS_TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Developer ID Application' \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS='--timestamp' build

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LENS_RELEASE_APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LENS_RELEASE_APP/Contents/Info.plist")" = "$LENS_PUBLIC_ID"
codesign --verify --deep --strict "$LENS_RELEASE_APP"
codesign --display --verbose=4 "$LENS_RELEASE_APP"
```

Stop on a failed command. Before submission, compare the printed identifier with the approved configuration and inspect the signing authority/team, hardened runtime, secure timestamp, version/build/channel, and privacy manifest. Do not proceed with an ad-hoc signature or an unexpected identity. Review Apple's [distribution-signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/).

Notarization uploads the signed app to Apple; obtain authorization for that submission separately. Create a submission ZIP in the isolated build directory, not the final release location:

```sh
ditto -c -k --sequesterRsrc --keepParent "$LENS_RELEASE_APP" \
  "$LENS_RELEASE_DD/Lens-notarization.zip"
xcrun notarytool submit "$LENS_RELEASE_DD/Lens-notarization.zip" \
  --keychain-profile "$LENS_NOTARY_PROFILE" --wait
```

Proceed only when the result is **Accepted**. A timeout or successful upload is not acceptance. If rejected, inspect the submission log through `notarytool` using the returned submission ID and the same Keychain profile, correct the cause, and submit a newly signed build. Keep diagnostics outside the repository. Apple documents submission, result inspection, and ticket handling in [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Staple the ticket to the app, validate it, then create the final ZIP from that stapled app:

```sh
xcrun stapler staple "$LENS_RELEASE_APP"
xcrun stapler validate "$LENS_RELEASE_APP"
codesign --verify --deep --strict "$LENS_RELEASE_APP"
spctl --assess --type execute --verbose=2 "$LENS_RELEASE_APP"
bash scripts/lens.sh package --derived-data "$LENS_RELEASE_DD" \
  --app "$LENS_RELEASE_APP" --confirmed-distribution-id "$LENS_PUBLIC_ID"
unzip -l dist/Lens-0.1.0-beta.1-1.zip
(cd dist && shasum -a 256 -c Lens-0.1.0-beta.1-1.zip.sha256)
```

Do not distribute the submission ZIP. The final package includes the license and stapled app; any subsequent app modification requires renewed signature/notarization checks. Complete manual acceptance on that exact package before separately authorized publication. No public identifier, signing success, notarization acceptance, or publication is implied by these examples.

## Release gates

- [x] Verify the approved MIT license is present in the repository with copyright holder kuil09.
- [ ] Verify the license is included in the final distribution.
- [ ] Decide and record the public bundle identifier. Assess effects on existing preferences and Screen Recording grants; do not silently replace the installed development identity.
- [ ] Confirm the intended Developer ID Application signing identity/team, hardened runtime, and necessary entitlements for the final artifact.
- [ ] Confirm a final app icon is included and displays correctly in Finder, Dock, and the About window.
- [ ] Verify the packaged app reports version 0.1.0, build 1, and channel beta.1; check native About display 0.1.0-beta.1 (1). Keep the prerelease tag separate from the numeric app version.
- [ ] Verify the signed bundle contains the privacy manifest and its declared API reasons match the current code. A manifest is not privacy certification.
- [ ] Inspect the final build/package command contract and run its required checks against the candidate revision. Record test failures and skipped/opt-in checks explicitly.
- [ ] Check signature validity, notarization acceptance, stapling, and Gatekeeper behavior on the exact public artifact. An ad-hoc development package cannot satisfy this gate.
- [ ] Complete the manual acceptance matrix below using the exact candidate artifact; identify blockers and retest fixes.
- [ ] Review privacy behavior, the changelog, contribution/reporting links, and known limitations.
- [ ] In a separately authorized repository action, enable GitHub private vulnerability reporting, verify the read-only API returns `enabled: true`, and update SECURITY.md. It was verified disabled on September 15, 2026. No build, packaging, or documentation action enables it automatically.
- [ ] Inspect archive contents for the app, license, and expected metadata; exclude credentials, personal paths, activity logs, screenshots, and development output.
- [ ] Obtain maintainer approval for the candidate and any explicitly deferred acceptance items. Do not describe untested features as accepted.
- [ ] Only after separate publication authorization, create the candidate tag and prerelease with the approved artifact and checksum. Packaging and CI must not automatically publish.

## Manual acceptance matrix

All rows below are **pending** until a tester records a result for the candidate. Use PASS, FAIL, NOT_RUN, or BLOCKED. Record the candidate revision/version/build, macOS version, Mac model/architecture, display configuration, tested language pairs/model state, and sanitized observations. Keep personal machine identifiers, local absolute paths, private activity logs, and screenshots out of checked-in evidence.

| Scenario | Acceptance criterion |
| --- | --- |
| Clean machine / new install | On a supported Mac or clean user environment without Lens state, install and launch the exact candidate. Verify identity/icon/version, permission explanation, denial and later grant, relaunch, language preparation, and visible translation of synthetic text. For public distribution, verify Gatekeeper without bypasses. |
| Update | Replace the previous development/candidate app through the intended update procedure. Check saved source/target and display preferences, permission continuity or clear reauthorization, launch, translation, and export. Record both versions and identities. |
| Core translation | Translate horizontal synthetic Korean, Japanese, and English text in both directions where models are installed. Check meaning, source-position alignment, explicit source and automatic detection, full text/copy, movement/resize, rapid content/language changes, and absence of obsolete overlays. Record additional catalog pairs separately. |
| Language preparation / offline | Check missing/unsupported pairs and canceled or interrupted downloads. Prepare a pair online, disconnect the network, relaunch, and translate new synthetic text using the installed pair. An unavailable pair must show an actionable state. Record recovery; do not infer offline success from model installation alone. |
| 30-minute session | Run mixed static/scrolling content for at least 30 minutes, including movement/resize and repeated language changes. Check responsiveness, crashes, stale overlays, CPU/memory trend and thermal observations. Record measurements and regressions; duration alone does not establish a performance target. |
| Multiple monitors | Test different scale factors, moving between screens, crossing screen edges, and display disconnect/reconnect. Confirm alignment, selected capture region, restart/recovery, and no capture of an unintended region. |
| Lifecycle / click-through | Verify pause/resume, sleep/wake, closing/reopening the lens, closing settings/reader, and quitting. Ensure menu-bar controls remain usable while click-through is on. |
| Image / video / privacy | Export synthetic content in reproduced and transparent modes. Confirm background and displayed translations, no window chrome or audio, readable PNG/playable MP4, destination selection/cancel/overwrite, and recording/saving indicators. Test stop, move/resize, language change, pause, sleep, quit, and failure/recovery with disposable files. |
| App UI / accessibility | Separately check Korean labels, light/dark appearance, keyboard navigation, focus, readable sizing, and assistive-technology access. OS-based target selection and translated content do not establish UI localization into other languages. |

CI evidence belongs in the automated-check record. Manual runtime evidence belongs in this matrix's candidate-specific results. Neither substitutes for the other. Notarization evidence also does not establish translation quality or performance.
