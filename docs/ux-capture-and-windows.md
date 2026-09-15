# Capture feedback and macOS window-flow review

## Scope and baseline

Review date: 2026-09-15. Baseline `70476a7`, beta.3/build 9. Local revision: beta.4-dev/build 10, not published. The existing beta.3 DMG SHA-256 is `fd2b411334d5e6b7e9f7fb4e10295340ca7b17fbed22264330dab6920a47fbec`; no packaging, push, release replacement, notarization, or permission reset belongs to this revision.

Subsequent separate authorization requested a local beta.4/build 10 DMG and a consolidated source-history push. See [package notes](releases/v0.1.0-beta.4.md). The runtime evidence below remains the build-10 UX audit, not a claim of new full-screen/input acceptance or replacement of the published beta.3 assets.

Preserve the existing `dev.local.lens` identity and local signer, Korean → Japanese selection, save-folder bookmark/default policy, installed-language policy, export accumulation, and system-authentication handoff. The audit used the installed ordinary-permission state, not a simulated first user. Automatic tests with isolated defaults cover missing grants and incomplete onboarding separately.

## Prioritized findings

| Priority | Reproduction | Observation and user impact | Change or boundary |
| --- | --- | --- | --- |
| Confusion | Save PNG from build-9 header, then open Settings | File was saved; camera and header accessibility tree did not change. Success was visible only in Settings → Translation → Current Status. | Header-only checkmark and localized Image Saved label/help for 1.5 s after real save success. No alert, flash, sound, activation, or export-layer change. |
| Confusion | In Settings, invoke Show Lens (⌘L) | Settings retained key focus; the action did not provide an obvious keyboard return to the lens. | Only explicit Show Lens/start makes the header key and activates Lens. Passive save completion does not activate it. |
| Confusion | Press ⌘M on the build-9 lens | No change; the lens had no minimize control despite a Window → Minimize command. | Miniaturizable parent, body hidden together; capture pauses and recording finalizes. Explicit return restores the pair, not capture. |
| Friction | Look for the folder beside Capture | No toolbar folder action; folder access existed only inside settings. The existing opener ignored Finder's Boolean failure. | Always-available toolbar/File/status-menu action calls the current store's safe preparation. Custom missing/unavailable paths never fall back; Finder failure offers Settings → Capture. |
| Confusion | Inspect recording control while saving or without a frame | Tooltip still described starting a recording. Translation's disabled switch also described starting without explaining language preparation. | State-specific localized tooltips, retaining the existing enabled conditions. |
| Confusion | Return from System Settings while the installed-language census refreshes | The ordinary guide displayed allowed screen access but retained Continue Setup/prepare-language copy. It observed LensModel but not its nested LanguageCatalog, so catalog completion alone did not invalidate the view. | Observe the catalog directly; display checking separately, and describe readiness only when both permissions and languages are ready. Final signed-app launch and explicit recheck showed Start Translation without starting capture. |
| Transition risk | Reopen a minimized reader/language-pack/help window | Code used makeKeyAndOrderFront without explicit deminiaturization; runtime failure was not claimed from code alone. | Explicit deminiaturization added on user reopen, consistent with existing settings/guide behavior. |
| Layout risk | Narrow header with an added folder action | Core stop/unlock actions must not be displaced by an optional folder shortcut. | Record and lock use high visibility priority, folder low priority; File/status menus provide fallback. |

## Intended window and security behavior

The lens is a floating overlay, not a standalone full-screen document. Its green button zooms the whole header/body pair within the visible desktop and toggles back. Full-screen tiling of the individual header is explicitly disallowed. Both panels retain the existing canJoinAllSpaces and fullScreenAuxiliary policy. A trial with canJoinAllApplications did not establish reliable pair behavior in the automation environment, so that eligibility expansion is not included. Behavior on every Spaces/Stage Manager/display configuration is not claimed.

System Settings activation continues to pause capture, finish recording, make the header ineligible for key input, and hide both panels. Incidental focus changes never restore a security-hidden overlay. Rechecking grants and returning to the normal guide does not capture automatically. No secure-input introspection, event tap, event forwarding, or TCC reset was introduced.

Closing the lens stops its current translation/recording work but does not quit Lens; Dock/menu actions can reopen guidance. Pausing translation leaves the frosted lens visible. Quit waits for capture shutdown and recording finalization. Hide is ordinary app hiding, not a new recording-control command. Save-folder activation is an explicit Finder transition, not an unsolicited success notification.

## Implementation and automatic verification

- A small capture-feedback object accepts an injected scheduler. A generation token invalidates even callbacks delivered after cancellation; tests cover exact expiry, repeated success, stale callback, new attempt, failure/no-frame-style early returns, and publication for toolbar observers.
- The export store reuses preparedDirectory, reads current selection on every request, and injects only the Finder open operation. Tests cover default creation, changed selection, last-file independence, valid/invalid bookmarks, deleted/replaced/read-only custom paths, rejected Finder open, and setting preservation.
- Toolbar tests cover localized semantics, unchanged enabled conditions, recording stop/finishing states, always-enabled folder access, and overflow priority. AppKit pair tests cover geometry, hide/restore, minimize, and security-hidden presentation suppression.
- PNG/video composition still takes only the body canvas and valid translations. Header feedback never enters their model or render surface.

Automatic checks and real macOS observations are recorded separately below. Property tests and synthetic input are not proof of cross-app input delivery or keyboard-focus preservation.

## Runtime review

Environment: macOS 26.6.2, Xcode 26.6, M4 Max/48 GB, one connected display, existing screen-recording grant and installed Korean/English/Japanese packs. Tests used Korean UI and Korean → Japanese without changing the stored pair or save-folder setting.

| Flow | Evidence and result | Remaining boundary |
| --- | --- | --- |
| Launch → grant/preparation guide → explicit start | Signed build 10 launched paused with access already allowed. Final guide showed Start Translation; explicit permission/catalog recheck retained the correct readiness. Earlier builds exercised actual start and screen capture. | Fresh-account onboarding, actual grant denial and download cancellation were not induced. Isolated state tests cover recovery decisions, not OS authorization dialogs. |
| PNG success and repeated capture | Actual PNG writes changed the icon to a checkmark and AX description to 이미지 저장 완료; subsequent observation returned to camera. Multiple captures remained available. | Exact 1.5-second deadline and adversarial canceled callbacks are scheduler tests, not a measured desktop timing guarantee. Actual disk-full/write-denied capture was not induced. |
| Folder access | Toolbar action while locked/recording and overflow action while paused opened Finder at /Users/gun9/Pictures/Lens. No user folder setting was changed. | Alternate selection, deleted/read-only custom directories, invalid bookmarks, default creation and Finder rejection are isolated store tests, not destructive tests against the user's directory. |
| Recording + screenshot + click-through header | Checkmark and red Stop coexisted. Header stop and unlock were exercised; a deliberate stop finalized a 6.233-second, 1600×1000 silent MP4. | Native physical mouse delivery through the body, double-input exclusion and keyboard focus in the underlying app remain unverified; prior automation negative controls were inconclusive. |
| Export-layer exclusion | Inspected saved PNG and one sampled MP4 frame: body content/border only, no header, folder button, checkmark or recording control. | This is sample inspection plus unchanged body-only composition, not a review of every video frame. |
| Settings → Lens / reader / language packs | ⌘, then ⌘L changed the focused AX window from Settings to Lens. Reader opened; minimized reader reopened via ⌘T. Language-pack manager displayed the installed-pair statuses without initiating a download. | Full VoiceOver traversal, actual download failure/retry, long reader content and physical keyboard focus across other apps were not exhaustively exercised. |
| Minimize, restore, resize and zoom | Baseline ⌘M did nothing. After correction, start → ⌘M → ⌘L restored both windows with translation off and capture/record disabled. At about 330 pt, recording/lock remained; folder/settings moved to native overflow. Parent/body geometry, zoom and hide/close are additionally tested. | The first AX minimize-button attempt was inconclusive; the final keyboard path was observed after pausing at the miniaturize method boundary. All resize edges and Spaces transitions were not exhaustively exercised. |
| System Settings → explicit Lens return | During the Settings handoff, no Lens windows were in the on-screen WindowServer sample. Explicit ⌘L returned to a normal guide reporting stopped translation/recording and allowed access. The final catalog-observation fix also passed launch/recheck. | No password prompt, actual secure-input typing, TCC change or new approval was triggered. |
| Other-app full screen / Spaces | Finder entered and exited full screen. An on-screen sample during the trial listed only the Lens body, not the header; the reported frontmost app was Universal Control rather than Finder. | Inconclusive/adverse sample, not a pass: reliable header/body cohesion in another app's full-screen Space needs an uncontested physical desktop check. The unverified eligibility expansion was removed. External monitors and Stage Manager were not tested. |
| Later, all-windows-closed return, sleep, recording quit | Existing deferred-onboarding, return-destination, handoff and finalization tests passed; normal app quit/relaunch was exercised between builds. | Fresh manual Later/close-all/Dock return, sleep/wake and quitting during active recording were not repeated in this audit. |
| Accessibility and visual variants | Korean AX labels and tooltips observed; ko/en/ja key parity, settings/reader light/dark rendering and existing reduced-transparency tests passed. | Full English/Japanese desktop layout, Reduce Motion, VoiceOver and complete keyboard-only navigation remain manual acceptance items. |

The Finder automation connection stalled for about 12 minutes during one recording. That recording was already stopped when control returned and the resulting file was decodable (654.74 seconds), but its stopping trigger was not established. This is a tooling/session limitation, not evidence of uninterrupted long-session reliability. A separate short recording verified deliberate Stop. No continuous 30-minute stability result is claimed.

Final automatic verification: **101 executed tests passed** (98 Swift Testing + 3 XCTest); three opt-in tests skipped (installed catalog, installed model translation, foreground WindowServer lookup). `make check` passed 49 repository-index and 49 shell-regression assertions. Release build and strict signature verification passed with the existing bundle ID/team; no notarization or Gatekeeper acceptance is claimed.

Local audit screenshots/logs are under `/private/tmp/lens-ux.oFdFT7`, not tracked screen history or release assets: `04-before-success-only-settings.png`, `06-after-checkmark.png`, `07-record-and-capture.png`, `11-narrow.png`, `12-finder-folder.png`, and `video-feedback-frame.png`. The six exports generated by this audit were moved to Trash after inspection; the user's pre-existing exports remain untouched. Temporary worker build caches were removed. The final local app remains available; beta.3 assets are unchanged.

Next manual acceptance priority is full-screen/Spaces pair cohesion and physical click/drag/scroll/keyboard delivery, followed by authentication, multiple displays, sleep/quit recording finalization and full accessibility/theme/locale traversal. These need controlled desktop input or hardware, not additional permissions or speculative window architecture changes in this revision.

## Apple guidance consulted

- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback): put passive status beside the action; reserve interruptions for significant actionable problems.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): familiar content actions and reliable essential controls as windows resize.
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows): window management and predictable app switching.
- [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications): floating overlays eligible to join other apps' full-screen Spaces.
- [fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary) and installed AppKit NSWindow.h: auxiliary versus primary and mutually exclusive full-screen policies.
- [parent](https://developer.apple.com/documentation/appkit/nswindow/parent): ordering out a child detaches it; restore must reattach.
