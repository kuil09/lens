# Build 12: launch and language readiness

## Baseline and changes

The installed Developer ID-signed, stapled build 11 retained onboardingCompleted=true, yet reopening displayed the normal permission/recovery guide. The launch branch unconditionally chose that guide for completed users. Build 12 selects a paused lens when onboarding is complete and permission is available. Setup and system-settings recovery retain their distinct safety paths.

The reported Finder-return language-pack popup was not reproduced in the initial build-11 UI attempt. Code inspection found that every activation restarted the catalog and that toggle treated checking as missing. Controlled asynchronous tests exercise that failure boundary. Build 12 avoids ordinary activation refreshes and separates readiness from installation, preserving a single cancelable explicit start request.

## Automated evidence

- Repository checks: 49 index assertions, 49 shell assertions, 4 DMG settings tests, 8 notarization/preflight tests.
- Swift Testing: 107 tests listed, 3 opt-in skips; XCTest: 3 tests passed. No failures.
- A separate opt-in test actually translated synthetic English/Korean/Japanese samples in all six directions using installed models. This is API execution evidence, not a translation-quality study.
- Tests cover persisted onboarding, launch/reopen/permission routing, checking versus missing/failed, one-shot intent consumption, delayed catalog completion, selection preservation, failure recovery, and cancellation. Existing stale catalog/target responses, recording, export, and permission tests remain enabled.
- Release build passed with the unchanged Developer ID identity.

## Actual macOS evidence before packaging

- Completed-user launch/relaunch three times: paused lens, no setup/recovery guide, translation off.
- Save-folder opening followed by translation start: no automatic language guide; screen connected and actual translation entries appeared in the reader. A separate explicit Finder selection followed immediately by start also succeeded.
- Click-through header capture and recording controls worked. PNG: 1600x1000. MP4: H.264, 1600x1000, 4.09 seconds, no audio stream.
- After actual focus moved to System Settings, the lens controls disappeared; explicit Show Lens returned to a normal guide stating that translation/recording were stopped. Only explicit Start Translation resumed.
- Saved Korean source/Japanese target and save directory were preserved.

Computer-use capture intermittently failed with SCStreamError -3811. A TextEdit fixture launch timed out; an in-app browser fixture was opened instead. The runtime capture did not reliably align with that fixture, so controlled visual translation quality is NOT_RUN. No screen captures, personal screen text, or private paths are checked into the repository.

## Distribution verification

At implementation time GitHub release-signing still lacked LENS_APPLE_ID and LENS_APPLE_APP_PASSWORD. Existing local Lens-notary authentication worked. The owner permits local fallback.

- Application source commit: f29451b3477716e91f2fcc366d2c4255c3ac1a45. Subsequent release-documentation changes do not change the app source.
- [GitHub CI](https://github.com/kuil09/lens/actions/runs/35018183144) passed checks, tests, Release build, DMG generation and upload. This is development packaging CI, not CI notarization.
- Local fallback: secure-timestamp Developer ID build; app submission c4f19211-68b3-4ef4-bcc8-e3112b324ab8 and DMG submission 72162e79-bb34-4723-af0c-e98c22baca13 were Accepted.
- App and DMG tickets validate; Gatekeeper reports Notarized Developer ID. The read-only mounted app matches the signed build, license matches, and Applications resolves correctly.
- Exact DMG installed into Applications before release replacement: build 12 opens a paused lens without a setup guide; folder-return translation and PNG/MP4 saving succeeded. Existing source/target selections persisted.
- Final DMG SHA-256: c3276a6d82164d73f1cdc0b3af1906a1d0467ba5d702ac2ee9359fc733962af9.
- The above installation uses the local final DMG. GitHub download and post-download installation are a separate publication gate; they are not implied by CI or notarization.

## Limits

Actual permission revocation/denial, a clean account with missing language packs, administrator password entry, external displays, sustained use, and full VoiceOver testing were not performed. Existing grants and installed packs were not reset or removed. Automatic tests are not evidence for those environments.
