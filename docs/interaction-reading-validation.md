# Language filtering and deliberate reading updates

## Artifact boundary

Base: `5b2aea6` (published beta.5 / build 12 at the start of implementation).
The observations below were collected on local builds 13 and 14, not the
installed `/Applications/Lens.app` or the original published DMG. At that point
the installed app was build 12, bundle ID `dev.local.lens`,
Developer ID team `GS344U4ZSG`. No release, tag, asset, signing identity, or
user preference has been permanently changed. Source selection was temporarily
changed for runtime checks and restored to Korean; the target remains Japanese.

The owner subsequently authorized committing, pushing, and replacing the DMG.
Build 15 identifies that release candidate. Its distribution evidence is tracked
separately in [build-15 validation](releases/build-15-validation.md); local preview
evidence is not silently reclassified as installed-release verification.

## Changes under validation

- Recognize supported scripts, classify paragraph context independently of the
  selected source, and filter both accepted observations and outgoing requests.
  Unknown text stays original. The existing 0.85 language hypothesis threshold
  is retained; conflicting native scripts and isolated native characters in
  foreign prose are rejected.
- The reader retains one explicit snapshot. Incoming changes enable Apply New
  Translations without replacing text. Native text views retain stable reading
  IDs, selection in untouched rows, and the scroll anchor. Spatial correspondence
  (unique mutual overlap >= 70%) affects reading identity only, not translation reuse.
- The live overlay still masks stale blocks immediately. Reader snapshots from
  earlier scenes remain explicitly labeled until manual application. No disk history.
- Truncated blocks open one click-triggered, fixed-text popover only with
  click-through off. Source invalidation, movement, hiding, deactivation, and
  enabling click-through close it. Shift-Command-T focuses the first overflow
  control; native accessibility actions expose the same control.
- Four exterior 8-point input strips preserve resize input with click-through
  on; 20-point end segments select diagonal resizing. Corner marks and overflow
  affordances are separate from PNG/MP4 composition. No global event hooks.

## Evidence so far

- PASS: `git diff --check`.
- PASS: all three Localizable.strings files parse with `plutil -lint`.
- PASS: `bash scripts/lens.sh check`: 49 repository assertions, 49 shell
  assertions, four DMG settings tests, eight notarization-script tests. These are
  static/mocked packaging checks, not application compilation or notarization.
- PASS: after user acceptance of the Xcode license, Xcode 27.0 (27A266a)
  compiled the source. All 121 Swift Testing tests passed (three opt-in tests
  remain skipped). The XCTest suite also passed. This includes real Vision on
  generated multilingual images, rendering/PNG re-recognition, and silent MP4 encoding.
- PASS: Release build 13 / `local-interaction`, retaining `dev.local.lens` and
  Developer ID team `GS344U4ZSG`; strict code-signature verification passed.
  Local app: `/private/tmp/lens-derived-data.JzSiqo/Build/Products/Release/Lens.app`.
  This new local build is not notarized or published.
- PASS (actual local build 13): launch with existing screen-recording access,
  capture connection and Apple translation. The installed build 12 was not used
  as evidence for these changes.
- PASS (actual synthetic screen): English source produced English paragraphs
  while excluding the Korean/Japanese paragraphs. A Korean-source run produced
  the Korean paragraph and excluded the fixture's English text.
- PASS (actual reader): changing the fixture from a negated 12-file instruction
  to a positive 13-file instruction left the open reading text unchanged and
  enabled Apply New Translations. Clicking Apply replaced the affected row;
  the two unaffected text entries and their accessibility identities remained.
- PASS (actual controls): click-through mode retained its toolbar control, and
  clicking Unlock returned to normal mode. Minimize paused translation;
  Show Lens returned with translation off. This does not prove physical input
  delivery through the body, nor full auxiliary-window visibility correctness.
- UNRESOLVED: physical body passthrough and resize drags. Native automation
  window-coordinate targeting returned `windowNotFoundAtPosition`; a fixture
  click counter also incremented in the OFF control case. The test did not
  establish overlap/targeting sufficiently to attribute that observation to
  Lens or declare input routing correct.
- NOT_RUN: live truncated-popover opening/dismissal, complete corner dragging,
  actual PNG/video recording, complete light/dark and accessibility acceptance.
  Screen export was rejected by tool auto-review because the captured region
  had not been proven free of other/private windows. No retry or capture
  workaround was used. Local export verification needs specific approval for
  that visible region or a demonstrably isolated synthetic screen.

The added tests cover fixed snapshots, manual replacement, pending/old scenes,
selection/scroll retention, pipeline masking, unconfirmed deletion, source
filtering, overflow layout, popover dismissal, and resize geometry/lifecycle.
The first run exposed scroll-anchor drift caused by NSTextView autoresizing;
disabling competing native autoresizing fixed it without relaxing the assertion.
A synthetic short English sentence had an NL score of 0.82015, below 0.85. It is
intentionally left original, not forced into the selected source. The numeric/
negation pixel-regression fixture now uses confidently identifiable full prose;
the threshold was not lowered. Xcode 27's test macro required an explicit closure
in one assertion and unnested `#require` calls in another.

Native light/dark reader renders were inspected, but this is not live-window
acceptance: the checkbox label in the dark detached render has poor contrast
and needs confirmation/correction in the actual app before visual sign-off.

The user approved launch; the new local app and fixture were actually executed.
The first fixture launch was delayed and returning to Codex contaminated the
initial capture. The fixture now stays above ordinary apps and below Lens to
reduce that interference. Initial personal-screen translations were not saved
as test artifacts or treated as synthetic-screen proof. Some fixture text was
clipped at the capture boundary, so this run does not establish complete OCR
fidelity or translation quality. The reader's manual update behavior was still
directly observable through its text values before and after the fixture change.
Source `ko`, target `ja`, and completed onboarding `1` were rechecked after
restoration. The local app is left paused. `/Applications/Lens.app` remains
build 12; no release assets or installed app were replaced.

## Resume verification

Commands recorded for that local preview (the temporary directory is historical, not a reusable development path). For a new checkout, use [the development guide](development.md#commands):

```sh
bash scripts/lens.sh test --derived-data /private/tmp/lens-derived-data.JzSiqo
bash scripts/lens.sh check
```

The separately identified local build 13 is ready for runtime verification.
Do not overwrite the installed/released build. Use
`Tools/InputFixture.swift` for a foreground input/capture reproduction, not a
personal document. Verify actual clicks, drags, and scroll counters, rather than
inferring delivery from window flags. Verify the reader and overflow with a
static paragraph beside a changing clock and numeric/negation text. Decode saved
PNG/MP4 and inspect the exclusion of popovers/resize marks. Keep all artifacts
local. Permission revocation, language-pack deletion, external monitors, and
administrator authentication remain untested unless safely exercised explicitly.

## Rounded resize-corner follow-up

The local app is now build 14 / `local-rounded-corners`, replacing only the
previous temporary build 13 at the same local path. The installed build 12 and
published assets remain untouched. Build 14 was signed with the same Developer
ID, strictly verified, and launched paused with Korean/Japanese preserved.

The four independently capped brackets are replaced by one shared contour:
12-point corner radius, 34-point reach, rounded ends, and a white 2.5-point stroke
with a dark 4.5-point outline. The 5.5-point outset keeps the entire contour
inside the existing exterior 8-point strips. Input geometry, cursor directions,
capture/export composition, and security hiding are unchanged.

The new native drawing test compares one uninterrupted contour against the
actual four handle views at 1x and 2x scale, allowing at most one byte of raster
rounding difference per channel. Both passed. Light/dark synthetic renders were
visually inspected; they are not screenshots of the user's display. The full
test run reported 122 Swift Testing tests passed, with the same three opt-in
tests skipped, plus three XCTest checks passed. The new app's actual launch was
confirmed, but prior physical drag/input limitations are not reclassified as
passed by these rendering tests.
