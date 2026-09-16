# Releasing and manual acceptance

## Candidate status

**Current release, September 16, 2026:** beta.5/build 15 retains `dev.local.lens` and the existing Developer ID. The owner authorized replacing the beta.5 download with source filtering, stable reading and rounded resize controls. App and DMG notarization passed through the existing local Keychain fallback; CI notarization remains unverified because two Apple authentication secrets are missing. The public download's checksum and contained app were rechecked. See [release notes](releases/v0.1.0-beta.5.md) and [build-15 evidence and limits](releases/build-15-validation.md). The historical sections below do not describe the current release.

### Historical beta.3 checkpoint

The current source candidate is **0.1.0-beta.3 (build 9)**, a nonnotarized development prerelease, retaining `dev.local.lens`. Owner-authorized local Developer ID signing is enabled through a gitignored configuration; fresh checkouts remain ad-hoc by default. See the [release notes](releases/v0.1.0-beta.3.md) and [context/input evidence](context-and-input.md) for recorded checks and NOT_RUN boundaries. [Distribution direction and history](distribution.md) distinguishes local signing from the deferred paid Mac App Store one-time purchase and withdrawn external notarization workflow.

- **Prior Developer ID notarization work was withdrawn on September 15, 2026.** Store planning is now allowed, but implementation, signing, submission, and publication remain deferred. No App Store submission was performed. Do not resume signing, status polling, stapling, or publication of the withdrawn candidate as part of that planning.
- The signed beta.2 build 3 candidate was uploaded to Apple before withdrawal, but was not published on GitHub or installed. Its Apple-side processing is not canceled by removing local files; `notarytool` provides no cancel command. Do not reuse build 3 for a different future candidate.
- At the build 3 withdrawal, its local outputs were removed and version configuration returned to the beta.1 baseline. That is historical: current source metadata is beta.3/build 9. Existing signing certificates and the owner-created Keychain credentials were retained, not revoked or deleted. The generic DMG packaging feature and regression fixes remain available.
- Development preview: **0.1.0**, build **9**, tag **v0.1.0-beta.3**.
- The owner authorized replacement of earlier preview downloads. The DMG is explicitly labeled **DEVELOPMENT-NOT-NOTARIZED**; this does not waive the gates for a notarized public distribution below.
- Some translation has been observed by a user; formal whole-runtime acceptance remains incomplete.
- The approved [MIT License](../LICENSE), copyright **2026 kuil09**, is included at the development archive root.
- The active development bundle identifier remains `dev.local.lens`. The previously approved public identifier `io.github.kuil09.lens` is no longer enabled in distribution configuration; reactivation requires a new request. No installed identity or preferences were migrated.
- The app icon is supplied through the AppIcon asset catalog, with standard/Retina dimensions and genuine-alpha tests. Notarization, formal translation quality, and end-to-end performance acceptance are not complete.

For the development preview, retain its explicit signing warning and incomplete manual-acceptance status in the [release notes](releases/v0.1.0-beta.3.md). Publishing this preview is not completion of the public-distribution checklist.

Recheck version, build, channel, and `PrivacyInfo.xcprivacy` on the exact distribution artifact after signing and packaging. Local build success is not a public-signing result, a CI result, or whole-runtime acceptance.

Building or packaging does not authorize or perform publication. Development packaging must be explicitly selected. The existing script's public packaging mode is for external Developer ID distribution and requires the license, signing, and notarization gates below; it does not implement Mac App Store distribution.

## Packaging contract

GitHub Actions supports a separate protected, manual [notarized DMG workflow](ci-notarization.md). It uploads verified CI artifacts only, never replaces Releases, and preserves the existing signer/bundle identity. Ordinary CI packages an explicitly nonnotarized development build. See the [remote change review](reviews/2026-09-15-remote-ci.md) for implementation findings and verification limits.

DMG creation now uses pinned packaging-only `dmgbuild` tools and the checked-in Finder artwork. See [setup and verification](dmg-installer.md). Application compilation and ZIP packaging do not require these tools.

This documents the existing development and external Developer ID packaging modes. It is not a store implementation or submission checklist.

`make check`, `make test`, and `make build` wrap `scripts/lens.sh`; see [development](development.md) for the canonical `build-design` workflow. Quit the selected app before packaging. `make package ARGS='--development'` explicitly produces a development ZIP and checksum from the existing Release app. It does not build, sign, notarize, launch, or publish.

Both modes require a nonempty repository license and validate bundle version/build/channel, arm64 executable support, minimum macOS metadata matching `Config/Application.xcconfig` in both the bundle and executable (currently 26.4), and a valid bundled privacy manifest. Without `--development`, packaging additionally requires an owner-confirmed public identifier passed through `--confirmed-distribution-id` that matches both `Config/Distribution.xcconfig` and the app, Developer ID Application signing with a valid team and hardened runtime, a successful notarized Gatekeeper assessment, and a valid stapled ticket. `--app` can select an existing Lens.app by absolute physical path. Signing and notarization must already be complete; the package command only validates them.

Notarized public packaging is inactive. Its safety gates remain intact; withdrawal must not silently relabel a nonnotarized build as notarized. Use explicit `--development` packaging for nonnotarized previews. Output names include version, channel, and build. Both ZIP variants contain `Lens.app` and `LICENSE` at the archive root; the privacy manifest stays inside the app's resources. Package validation is not a substitute for manual acceptance or publication approval.

Use `--format dmg` to create a compressed, verified disk image containing `Lens.app`, the license, and an `Applications` symlink for drag-and-drop installation. This runs the same app-validation gates as ZIP packaging and refuses existing output names. Temporary staging is removed on exit. A development DMG retains the `DEVELOPMENT-NOT-NOTARIZED` suffix even if its app has a Developer ID signature. A public DMG must additionally be signed, submitted for notarization, and stapled; regenerate its checksum after those mutations. Do not publish a pre-notarization candidate as a notarized release.

## Manual Developer ID build and notarization

**Inactive external-distribution reference only. The owner withdrew this workflow; it is not the planned Mac App Store path. Do not run the following commands without renewed authorization.** The public identifier is intentionally blank in configuration. The team identifier and Keychain profile name are not credentials. A valid Developer ID Application certificate/private key must already be available to Xcode, and the named notarization credentials must already be stored in Keychain. Never put passwords, API keys, or private-key material in these commands or the repository.

Use the same shell for the following steps, from the repository root. The temporary build keeps the canonical `build-design` app and its development identity intact. These commands invoke Xcode directly to use the separate external-distribution configuration rather than the canonical local signing configuration.

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
```

If this workflow is reauthorized, inspect the exact archive path printed by the packaging command and verify its matching `.sha256` sidecar. Do not reuse a historical beta.1 filename for a new candidate.

Do not distribute the submission ZIP. The final package includes the license and stapled app; any subsequent app modification requires renewed signature/notarization checks. Complete manual acceptance on that exact package before separately authorized publication. No public identifier, signing success, notarization acceptance, or publication is implied by these examples.

## Release gates

The general artifact and runtime checks below apply to candidate review. Developer ID/notarization and GitHub publication items apply only if those external distribution actions are requested again; they remain deferred and do not define Mac App Store readiness. Notarization gates must pass before any future external artifact is described as notarized. Store preparation remains planned work under [distribution](distribution.md).

- [x] Verify the approved MIT license is present in the repository with copyright holder kuil09.
- [ ] Verify the license is included in the final distribution.
- [ ] Reconfirm the public bundle identifier if signed distribution is requested again; assess permission/preferences implications.
- [ ] Confirm the intended Developer ID Application signing identity/team, hardened runtime, and necessary entitlements for the final artifact.
- [ ] Confirm a final app icon is included and displays correctly in Finder, Dock, and the About window.
- [ ] Verify the final packaged app matches the selected version configuration. Any new candidate must use a build number greater than the withdrawn build 3. Keep prerelease tags separate from the numeric app version.
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

This is the acceptance template; candidate-specific observations and exact NOT_RUN items live in [beta.2 readiness](releases/beta.2-readiness.md). A partial observation does not pass an entire scenario. Use PASS, FAIL, NOT_RUN, or BLOCKED. Record the candidate revision/version/build, macOS version, Mac model/architecture, display configuration, tested language pairs/model state, and sanitized observations. Keep personal machine identifiers, local absolute paths, private activity logs, and screenshots out of checked-in evidence.

| Scenario | Acceptance criterion |
| --- | --- |
| Clean machine / new install | On a supported Mac or clean user environment without Lens state, install and launch the exact candidate. Verify identity/icon/version, permission explanation, denial and later grant, relaunch, language preparation, and visible translation of synthetic text. For public distribution, verify Gatekeeper without bypasses. |
| Update | Replace the previous development/candidate app through the intended update procedure. Check saved source/target and display preferences, permission continuity or clear reauthorization, launch, translation, and export. Record both versions and identities. |
| Core translation | Translate horizontal synthetic Korean, Japanese, and English text in both directions where models are installed. Check meaning, source-position alignment, explicit source and automatic detection, full text/copy, movement/resize, rapid content/language changes, and absence of obsolete overlays. Record additional catalog pairs separately. |
| Language preparation / offline | Check missing/unsupported pairs and canceled or interrupted downloads. Prepare a pair online, disconnect the network, relaunch, and translate new synthetic text using the installed pair. An unavailable pair must show an actionable state. Record recovery; do not infer offline success from model installation alone. |
| 30-minute session | Run mixed static/scrolling content for at least 30 minutes, including movement/resize and repeated language changes. Check responsiveness, crashes, stale overlays, CPU/memory trend and thermal observations. Record measurements and regressions; duration alone does not establish a performance target. |
| Multiple monitors | Test different scale factors, moving between screens, crossing screen edges, and display disconnect/reconnect. Confirm alignment, selected capture region, restart/recovery, and no capture of an unintended region. |
| Lifecycle / click-through | Verify pause/resume, sleep/wake, closing/reopening the lens, closing settings/reader, and quitting. Ensure menu-bar controls remain usable while click-through is on. |
| Image / video / privacy | Export synthetic content while live translation is active and transparent; confirm the captured background and displayed translations, no window chrome or audio, readable PNG/playable MP4, and recording/saving indicators. Check shared-folder selection/cancel, persistence, immediate save/start without filename prompts, collision suffixes without overwriting, folder changes during recording, and unavailable-folder errors. Test stop, move/resize, language change, pause, sleep, quit, and failure/recovery with disposable files. |
| App UI / accessibility | Check English, Korean, and Japanese labels, macOS app-language selection and fallback, light/dark appearance, keyboard navigation, focus, readable sizing, and assistive-technology access. Verify paused glass and Reduce Transparency fallback separately from live transparent translation. See the scoped observations in [localization](localization.md); these do not establish a complete accessibility journey. |

CI evidence belongs in the automated-check record. Manual runtime evidence belongs in this matrix's candidate-specific results. Neither substitutes for the other. Notarization evidence also does not establish translation quality or performance.
