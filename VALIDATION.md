# Validation status

Updated: 2026-09-14. This is an incomplete development build, not full acceptance.

Latest handoff: at the user's request, the border-enabled build replaced the prior Release app at `build/Build/Products/Release/Lens.app` without retaining a backup of that replaced app. Code signature verification succeeded and the copied executable matched the border build's SHA-256. The new app launched and displayed the permission-required state. No permission prompt was accepted automatically. Earlier entries below describe the sequence of checks, not a claim that the old build is still running.

## Observed environment and checks

- Border follow-up: added a topmost, non-hit-testing border view with contrasting one-point dark/light strokes. Offscreen drawing tests passed at 1x, 2x and 3x: all four edges have visible pixels, the center stays transparent, and the view does not intercept hits. Full suite: 17 Swift Testing plus 3 XCTest tests passed. A separate Release build succeeded at `build-border/Build/Products/Release/Lens.app`; the existing running build was not replaced or relaunched. Desktop visual acceptance and OS-level click-through are not established by these tests.

- macOS 26.6.2, Xcode 26.6, SDK 26.5, Apple M4 Max, 48 GB memory.
- Initial integrated automated suite: 15 tests passed for geometry, OCR grouping, language identification, batching, cache isolation/eviction and cancellation/stale-result gates.
- After the permission fix, the complete suite passed: 16 Swift Testing tests plus 3 XCTest permission tests, zero failures. The warm synthetic Vision test took 0.386 seconds in this run, not an end-to-end screen translation measurement.
- Additional live Vision test passed on synthetic Korean, Japanese and English text. Cold test duration was approximately 11.25 seconds; this is not steady-state OCR latency.
- Apple low-latency language availability returned `supported` for all six directions, not `installed`. Checks from inside the development sandbox incorrectly appeared unsupported; the OS-service checks were repeated outside it.
- Debug and Release application builds succeeded before the permission fix. The updated Release build also succeeded after the fix; it was not automatically relaunched to avoid further authorization interruptions.

## Repeated screen permission requests

The system settings screenshot showed Lens enabled. The TCC log nevertheless reported `Failed to match existing code requirement` for `dev.local.lens` and `kTCCServiceScreenCapture` on 2026-09-14. The authorized and running executable hashes differed. Development builds use ad-hoc signing, so replacing the executable changed its identity. This establishes a signing mismatch, not a user failure to enable the toggle.

The app also attempted capture at launch and after window movement without a permission preflight. The running Debug test app was stopped. The fix uses non-prompting preflight checks before capture and requests permission only from an explicit user action, at most once per launch. Window movement and display changes must not restart paused capture. Added three permission-controller tests cover non-prompting repeated checks, a bounded denied request, and detection of externally granted access. These injected checks do not prove OS authorization for a new build.

Do not repeatedly replace/relaunch builds and ask the user to reauthorize. Build the intended artifact first. Stable code signing is still required for permission continuity across updates; no TCC database edits, resets, or weakened signing requirements were used.

## Not yet verified

### Fixed-build follow-up

At the user's subsequent retry request, Lens's installation check still reported incomplete, and its preparation action returned immediately to the incomplete state. System Settings → General → Language & Region → Translation Languages showed English (US) at `0.1914814790089925`, Japanese at approximately `0.01`, and Korean at `0.5581481456756592`. English had advanced relative to the earlier app sheet; therefore the earlier observation does not establish a permanently frozen download, and stale UI reporting remains possible. After a 30-second unchanged observation, only the incomplete English download was stopped and restarted once through System Settings. It returned to the same progress value and showed no further change over roughly another 40 seconds. Installation success was not observed. The Release executable, permission settings, system services and existing installed packs were not changed. The system download management sheet was left open.

The unchanged Release executable (2026-09-14 18:10 build) was launched for validation. TCC still reported a mismatch between the previously authorized code hash and this Release build, so successful screen capture remains blocked pending authorization of this exact build. The application was not rebuilt during this check.

Apple's download sheet repeatedly reported Korean progress `0.5581481474417227` and US English `0.01`. The corresponding English translation asset task (`com.apple.sequoia.asset.pb.en`) in `nsurlsessiond` logged `_nsurlsessiondErrorDomain Code=10`, rescheduling and extractor cleanup on 2026-09-14 at 18:12:12. This is evidence of a stalled/retrying system download, not proof of a particular underlying OS defect. Direct HTTPS checks against that exact asset URL returned HTTP 200 for metadata and HTTP 206 for a 65,536-byte range in 0.253 seconds. Disk space was approximately 158 GiB available. These checks weaken general connectivity and disk-capacity explanations but do not prove the background service uses the same working network path. No system daemon restart, asset-cache removal, or global network change was performed. Dismissing the sheet returned the app to an explicit installation-incomplete state.

- Real capture behind the opaque lens, self-exclusion, transparency, click/scroll passthrough, multi-monitor movement and long translation rendering.
- End-to-end translation after language pack installation. The synthetic 180-output benchmark reported blocked because packs were not installed; no quality score is available.
- Offline translation, interrupted language downloads and sleep recovery in actual use.
- 30-minute scrolling/screen-change soak, memory stability, or performance acceptance targets.
- Actual display presentation latency: current app telemetry measures GPU submission, not presentation.

Current change detection triggers OCR on the latest entire lens image; it is not partial-region OCR. No claim is made that all original acceptance conditions are complete. Captured content and translation history are not written to disk; explicit benchmark output is synthetic text only.
