# beta.2 local candidate review

The original review below covers app 0.1.0, channel beta.2, build 4 with ad-hoc signing. Current source is build 6 with owner-authorized local Developer ID signing, described separately below; it retains `dev.local.lens`. These historical local checks support the separately authorized beta.2 development prerelease; see [release notes](v0.1.0-beta.2.md). Prior external notarization remains withdrawn. Paid Mac App Store one-time purchase is planned, but store implementation/signing/submission are deferred. See [distribution direction and history](../distribution.md). This is not final release approval; published beta.1 remains unchanged.

## Executed plan

1. Separate downloaded language packs from general translation support; reconcile removed selections and test stale asynchronous results.
2. Add explicit first-launch guidance for permission, installed languages, and the automatic save directory. Keep it reopenable, without automatic permission requests or downloads.
3. Review capture lifecycle, cancellation, recording finalization, file publication, and release-facing documentation; fix relevant regressions.
4. Run tests, real model probes, a local Release build, UI checks, and read-only DMG inspection. Separate these from untested runtime acceptance and external publication.

## Findings and fixes

| Finding | Action / evidence boundary |
| --- | --- |
| Apple Intelligence reports a shared multilingual model as installed, not the user's downloaded packs. | Production availability, preparation, and translation now all use lowLatency. Direct comparison found fr/de/zh supported-but-not-installed under low latency, but installed under high fidelity. Final pack census: en, ja, ko only. The earlier count of 31 was rejected as a pack-installation claim. |
| Menus included uninstalled languages and stale saved choices. | Only installed targets with an OCR-readable incoming route and installed sources for the selected target are selectable. Missing selections reset to installed defaults. No installed pair disables translation. No English-hub assumption. |
| Add-language UI changed the live target and shared its mutable catalog. | Independent preparation target/catalog. Download checks do not mutate the lens selection. |
| Late queries could replace newer results; clearing same-target routes could temporarily erase sources. | Generation guards discard obsolete loads/queries. Same-target refresh preserves its snapshot until replacement. OCR identification is independent of transient route refresh; installation is checked before translation. |
| Reselecting the same language invalidated frames and could stop recording. | Equality guards preserve the current region; no-invalidation regression test added. |
| Capture-start failure could leave partial output. | Suspend/invalidate and stop capture on failure. |
| No coherent first-launch flow. | Three steps, completion gated on permission and a usable installed route. Closing/later does not mark completion. Help reopens it. |
| Docs described obsolete display controls. | README, usage, privacy, troubleshooting, changelog updated; published beta.1 and local candidate distinguished. |

Apple documents the model distinction in [highFidelity](https://developer.apple.com/documentation/translation/translationsession/strategy/highfidelity) and [preferredStrategy](https://developer.apple.com/documentation/translation/languageavailability/preferredstrategy).

## Verification

This section preserves recorded checks from the candidate review stage. Later [localization validation](../localization.md#validation-2026-09-15) records its own test counts and UI observations. Documentation housekeeping does not rerun or extend either record. The DMG inspection below predates the current changes and does not establish that a DMG contains the latest source; final checks/build must be recorded against the source revision tested.

- Host: M4 Max, macOS 26.6.2, Xcode 26.6; minimum deployment remains 26.4.
- Swift Testing: 56 passed with installed-model opt-in; XCTest: 3 passed. Catalog removal/races, no-op reselection, onboarding completion/layout, coordinates/OCR grouping, cache/cancellation, PNG composition, playable silent MP4, no-overwrite publication, and recording finalization are covered.
- Actual low-latency census: en, ja, ko, approximately 1.72 seconds on this host. Selectable pairs were checked independently with raw low-latency availability, not the production resolver.
- Actual text-only translation: six ko/ja/en directions, one synthetic sample each. Observed outputs preserved the tested negation, file count, and time. This is not the separate 180-sample formal quality target or OCR/display latency verification.
- Shell regressions: 49 assertions with mocked process/signature metadata; no notarization or publication is exercised.
- Native first-launch window, missing-permission gate, and normal picker interaction observed. Input automation intermittently timed out; that alone is not an app defect. Offscreen layout tests do not prove live glass compositing or system-permission behavior.
- Final running app's target menu showed only English, Japanese, Korean, plus the system-default selector. Existing English-to-Korean choice was preserved. The guide's Later action opened the paused lens without recording completion.
- Final nonnotarized DMG: verified image checksum, SHA-256 sidecar, Applications symlink, exact license bytes, valid app signature, privacy plist, beta.2/build 4 metadata, and executable equality with the canonical Release app. Read-only mount detached afterward. Earlier local ZIP and superseded intermediate DMG removed; published GitHub assets unchanged.
- Source review retained explicit screen permission, local processing, bounded cache, one OCR worker/latest pending frame, and video backpressure. No app-operated networking or secret material was added.

## Housekeeping verification — 2026-09-15

These checks cover the local working tree after removing the unused strategy chooser and consolidating repository hygiene checks. They are not a new package, store submission, or runtime acceptance run.

- `make check`: 37 synthetic Git-index assertions and 49 existing process/packaging assertions passed, plus shell syntax and Git whitespace checks. Staged provisioning profiles and generated test archives are rejected without reading their contents; untracked local artifacts are not treated as publication.
- `make test` in isolated temporary DerivedData: 57 Swift Testing cases and 3 XCTest cases passed; 2 installed-model opt-in cases were skipped. The obsolete chooser-only test was removed; downloaded-pack policy, cancellation, and strategy-specific cache tests remain.
- `make build` in the same temporary tree: Release build succeeded. Strict signature verification and bundle/privacy plist validation passed; all three UI localization folders were present. Xcode emitted only the no-AppIntents metadata extraction warning.
- Generated files in that temporary tree were removed after verification. The canonical app and existing DMG were not replaced, launched, or repackaged; no permission reset, signing-identity migration, commit, or publication was performed.

## Stable local signing — 2026-09-15

- The normal build wrapper now honors an optional gitignored local signing configuration instead of overriding it with `CODE_SIGN_IDENTITY=-`. The bundle ID and canonical app path are unchanged; the configured key remains in the existing Keychain.
- Two successive Developer ID builds (4 then 5) passed strict signature verification using the system Keychain. Their code hashes differed while their designated requirements were identical, binding the same app ID and developer team rather than a specific code hash. The build 5 signature also satisfied build 4's requirement explicitly. This is code-identity continuity evidence, not proof of a retained TCC grant.
- The rebuilt source passed 60 ordinary tests; 2 installed-language tests were skipped. The handoff tests still prove explicit restoration without automatically restarting capture. Repository checks now include 40 synthetic index assertions and the existing 49 shell assertions.
- Native UI inspection initially failed with the automation service's ScreenCaptureKit error -3811, then recovered. The running signed build 5 showed onboarding step 1, screen access required, and Continue disabled. Owner consent and relaunch are still needed for this initial signature transition; permission retention after that grant and administrator-password entry remain unverified.
- No private keys were exported, trust settings changed, TCC grants reset, notarization requested, or store/GitHub submission performed. The old build 4 DMG was not regenerated and is not the signed build 5 app.

## Permission recovery revision — 2026-09-15, local build 6

- Rechecked the running build 5 before editing: valid Developer ID signature, expected canonical path, team and bundle identifier. Build 6 uses the same identity and designated requirement; strict verification passed. Signing is complete, but existing TCC consent continuity is not established.
- Intentional security behavior retained: hiding and de-keying the floating overlay during System Settings/authentication handoff. Defects repaired: no reopen routing, discarded onboarding progress, Later leaving no visible destination during handoff, and a settings recheck sharing the start-translation action.
- Added a normal return guide, visible deferred state, fresh OS permission checks, persisted incomplete step, and independent recheck/start actions. Missing permission temporarily gates the saved step rather than resetting it. No stored boolean is treated as OS consent.
- Stop operations now await prior in-flight capture work and video finalization before Lens opens Settings or terminates. Handoff/inactive video failures use a deferred notice instead of a modal alert. No automatic restart is attempted; only macOS can establish whether its permission change requires relaunch.
- Automatic checks: 63 ordinary tests passed (60 Swift Testing + 3 XCTest); 2 installed-language opt-ins skipped. Tests cover denied/granted/revoked fake preflight, progress across new state instances, preference preservation, no request during refresh, return routing, actual panel visibility/key eligibility, guide layouts, and existing synthetic video finalization. These do not simulate real OS consent or password entry.
- Repository checks: 40 synthetic Git-index and 49 shell regression assertions passed.
- Final rebuild/retest after separating Settings recheck also passed. The final app explicitly satisfied build 5's designated requirement and was launched again. Native Settings showed the preserved English-to-Korean selection, `~/Pictures/Lens` destination, and disabled capture/record actions; clicking recheck left capture stopped and did not open an OS prompt. The app was left running at its permission guide.

| Scenario | Actual macOS result | Automated boundary |
| --- | --- | --- |
| Missing/denied access | Build 6 showed access required, disabled Continue, no launch prompt. Existing Settings toggle remained on; no grant was reset. | Fake denial, once-per-launch requests, repeated read-only checks. |
| Settings abandonment and return | Explicit Settings button opened the correct pane; reopening the running app via Launch Services restored the normal permission guide, with capture still paused. Direct Dock automation timed out, so an actual Dock click is not claimed. | Reopen/handoff routing and no restoration while request is pending. |
| Allow then return | NOT_RUN: current build still reports no grant; owner authorization is required. | Fake grant updates readiness without issuing a request or starting capture. |
| Later | Native paused guide remained visible with resume and quit; verified before and after Settings handoff. | Deferred/permission layout states and no model start. |
| Quit then relaunch | Quit button exited the process; reopening restored incomplete step 1 with Continue disabled, no automatic permission request or capture. | Later-step persistence and missing-grant gating across state instances. |

Actual administrator-password input, recording-in-progress handoff, and grant retention across an authorized rebuild remain NOT_RUN. No password was entered or inspected. Native before/after guide screenshots were inspected locally; no desktop imagery was added to the repository. Source, language selections, saved export folder, app ID, and canonical path were preserved. No permission reset, notarization, store submission, packaging, commit, or external publication was performed.

## Local artifact housekeeping — 2026-09-15

- Removed 773,504 KiB of allocated generated output: obsolete root SwiftPM build, current SwiftPM/test and Xcode intermediate caches, generated module output, old build 4 DMG/sidecar, earlier downloaded build 2 ZIP/extraction, temporary UI/icon renders, and Finder metadata. No backup of obsolete binaries was retained; caches and synthetic renders can be regenerated.
- Preserved the running Developer ID build 6 at its canonical path. Aggregate file hashes for the entire app bundle and for source/tests/configuration/project/fixtures were identical before and after removal. Strict signature verification passed; no app restart, signing operation, permission change, or preference mutation was needed.
- Preserved certificates, Keychain entries, local signing configuration, user exports, Git history, uncommitted work, and synced project references. No remote assets were changed. Historical checks above remain records, not claims that deleted artifacts are still available.
- Added ZIP/DMG/PKG index rejection and ignore rules, and corrected current-candidate documentation to build 6. Local distribution archives are absent until explicitly repackaged. Full app tests were not rerun solely to recreate deleted caches; repository checks and artifact-preservation checks cover this cleanup.
- `make check` passed: 49 synthetic index assertions, 49 shell regression assertions, syntax checks, and Git whitespace checks. The checkout contains one app bundle and no local ZIP/DMG/PKG files; its total allocated size is approximately 8.5 MiB including Git metadata.

## Remaining release boundaries

### Current local DMG — 2026-09-15

- Created `dist/Lens-0.1.0-beta.2-6-DEVELOPMENT-NOT-NOTARIZED.dmg` (3,208,691 bytes) and its `.sha256` sidecar using the existing build 6; no rebuild or signing mutation was performed.
- Image verification and SHA-256 verification passed. Read-only mount inspection confirmed the `/Applications` symlink, exact MIT license bytes, byte-identical app bundle, strict signature validity, version/channel/build, minimum macOS 26.4, and valid bundled privacy manifest.
- Packaging staging and verification mount were removed after use. The canonical app was normally stopped for packaging and reopened afterward. No notarization, external publication, or clean-machine installation claim is implied by these checks.

- The rebuilt app reported screen access missing after normal relaunch although the user's Settings toggle appeared enabled. No TCC reset was performed; capture/permission continuity is not verified. The exact candidate needs owner authorization and runtime testing.
- Screen OCR/translation end-to-end, administrator-password entry, clean-user install/update, disconnected-network operation, download cancellation, multiple monitors, and 30-minute resource behavior are NOT_RUN for this candidate.
- Follow-up: [UI localization](../localization.md) now covers English, Korean, and Japanese through bundled resources. This remains distinct from an OS-preferred translation target; broader UI languages are not claimed. Complete VoiceOver, light/dark accessibility/contrast, and independent linguistic review remain unverified.
- A local build 6 DMG is now available with its Developer ID signed app and SHA-256 sidecar. It is not notarized, and package integrity does not establish clean-Mac Gatekeeper acceptance. Historical build 4 evidence remains separate. No security bypass is recommended.
- Commit/tag/GitHub publication and approval of deferred acceptance are separate actions. No publication was performed by this review.

Use the [manual acceptance matrix](../releasing.md#manual-acceptance-matrix) for candidate-specific runtime results. Store readiness is planned work, not an outcome of these development checks.
