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

## Distribution gate (pending)

At implementation time GitHub release-signing still lacked LENS_APPLE_ID and LENS_APPLE_APP_PASSWORD. Existing local Lens-notary authentication worked. The owner permits local fallback.

Final secure-timestamp build, app/DMG notarization, exact-package installation, GitHub replacement/download, and post-download launch are pending. This document does not claim CI notarization success or a completed replacement.

## Limits

Actual permission revocation/denial, a clean account with missing language packs, administrator password entry, external displays, sustained use, and full VoiceOver testing were not performed. Existing grants and installed packs were not reset or removed. Automatic tests are not evidence for those environments.
