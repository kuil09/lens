# Context, visibility, and window input — build 8

Implementation and runtime evidence from local build 8, 2026-09-15, preserving the earlier build 7 work. The implementation was subsequently packaged as [beta.3/build 9](releases/v0.1.0-beta.3.md) under separate publication authorization. Runtime observations below remain attributed to build 8; repackaging does not close their outstanding acceptance items. No notarization was resumed.

## Translation representations

The representation details below describe build 8. In particular, the reader later gained an independent, manually applied snapshot; do not treat the shared reader/display list described here as the current reading behavior. See [current reader usage](usage.md#read-a-full-translation) and [the scoped implementation evidence](interaction-reading-validation.md).

1. **Live source:** ScreenCaptureKit continues feeding the Metal canvas independently of OCR and translation. Its source rectangle is the body panel, not the header.
2. **Context/reference:** A `TextBlock` retains physical `SourceLine` strings and normalized Vision coordinates. The translation input joins layout-wrapped lines (spaces for English/Korean, no inserted space for Japanese). It does not split at the observation grid, flatten the screen into one string, or guess target-line alignment. Exact source text and line geometry remain available for result validation/reuse. `referenceLayer` retains completed translations even when locally hidden.
3. **Visibility:** `TranslationDisplayMask` hides whole block IDs. Both translated glyphs and their source-cover rectangles disappear together; the same filtered display list feeds the overlay, reader, PNG, and MP4. A change anywhere in the output union, including gaps between source lines, hides that block. Unrelated valid blocks remain visible. Late replies are checked against their source revisions and current context.

The installed SDK's `TranslationSession.Request` supports source text (including an attributed variant) and `clientIdentifier`; `Response` supplies target text/attributed text and that identifier. It does not expose screen coordinates, translated word/line alignment, or a separate context-only argument. The adapter therefore keeps one paragraph-context request ID mapped to one conservative display union. Batch neighbors are **not** assumed to share semantic context. No model or external service was added. References: [Apple TranslationSession](https://developer.apple.com/documentation/translation/translationsession), [batch request initializer](https://developer.apple.com/documentation/translation/translationsession/request/init(sourcetext:clientidentifier:)).

Layout grouping precedes final contextual language assignment. Strong per-line language evidence prevents mixed-language merging, while an ambiguous short tail can inherit the complete context. Continuation uses left alignment, line spacing, prose evidence, list markers, terminal punctuation, language compatibility, and row-peer evidence. A short final line has no minimum width ratio. Aligned small-font clocks are not automatically table cells. A real Vision fixture exposed inflated first-line boxes; when height similarity fails, comparable mean character advance provides a bounded secondary check (height ratio ≥0.55 and advance ratio ≥0.8). Normal height matching remains ≥0.75. Large headings with genuinely different type sizes remain separate.

The 8 × 5 observation grid is only a scheduler. Backoff remains 250/500/1000/2000 ms, with 120 ms quiet recovery, at most one OCR operation and one four-context translation batch, one latest waiting frame, and no historical request queue. The existing epoch/revision gates and scene/geometry/language resets remain active. The 2 s cap excludes OCR/translation saturation and service time.

## AppKit input boundary

`LensPanel` owns the native toolbar, titlebar language controls, close/zoom/move/width-resize interaction, and a new click-through toggle with an explicit release label. Its rectangle does not overlap the body. The attached `LensBodyPanel` owns the live surface and is non-key/non-main. Only the body gets `ignoresMouseEvents`; header controls retain their ordinary readiness/recording/save-state conditions. There is no event tap, synthetic event forwarding, or per-view `hitTest` assumption.

The child relationship handles ordering/movement; explicit synchronization handles resizing. Body resizing updates the header; header zoom/clamping operates on the pair. `orderOut` and close hide both; explicit return reattaches the body after AppKit removes an ordered-out child. Security handoff continues to pause capture/finalize recording, disable header key eligibility, and hide both panels. Process-wide ScreenCaptureKit self-exclusion covers both windows. [Apple NSWindow](https://developer.apple.com/documentation/appkit/nswindow) documents window-level input and child ownership; [parentWindow](https://developer.apple.com/documentation/appkit/nswindow/parent) notes child detachment on `orderOut`.

## Evidence boundaries

Automated tests cover wrapped English/Korean/Japanese tails, unchanged physical source lines, one context request and whole-reference hiding, columns, list items, numeric table cells, headings, mixed-language boundaries, exact numeric/negation changes and stale replies, backoff/recovery/fairness, independent panel input flags, disjoint geometry, resize/move, body-only capture bounds, close/hide/reattach/security handoff, and toolbar readiness including recording stop while locked. Real Core Image/Vision tests use rendered synthetic text; their translator is not Apple Translation.

Final suite: **81 executed tests passed** (78 Swift Testing + 3 XCTest); three opt-in tests skipped (installed catalog, installed translation models, foreground WindowServer lookup). `make check` passed 49 repository-index assertions and 49 shell regression assertions. Release build and strict Developer ID signature verification passed.

Desktop observations with the signed build 8 and existing screen access:

- Permission was already granted; explicit start worked without resetting TCC. The header remained usable while click-through was enabled. Language swap and restore, source selection, translation toggle, image save, and recording start/stop were exercised.
- A real PNG export contained fixture content and translations, but no Lens language bar/toolbar. A real silent MP4 finalized: 11.11 seconds, 2022 × 1488, zero audio tracks. The existing save folder was not changed. The inspected PNG exposed a prose/clock grouping defect, which was then reproduced with a real-Vision test and repaired; the final grouping refinement still needs a complete desktop visual rerun.
- The standalone `Tools/InputFixture.swift` received click/drag/scroll counters (2/1/1), but the same-position negative control also incremented while click-through was off. Thus these counter observations **do not establish WindowServer routing or keyboard-focus preservation**. UI automation initially had ScreenCaptureKit errors and needed a fresh connection. A foreground-sensitive `windowServerHitRegionsExcludeLockedBodyButRetainHeader` test also could not establish its control-window baseline and is opt-in, not a passing default-suite claim. Human input verification was requested separately.
- Top-control actions did not increase the fixture counters during sampled checks; this is not a complete double-input proof. Native body click/drag/scroll delivery, keyboard-focus retention, final visual recovery timing, actual multi-display movement, and authentication-dialog input remain unverified unless separately confirmed. Full recording-content review and end-to-end latency/quality measurements were not performed.
- Original Korean → Japanese selection and click-through-off/paused state were restored before final rebuild. No user recording or capture was overwritten.
- The two generated PNG/MP4 test exports were moved to Trash after inspection and can be recovered. The temporary fixture binary and compiler/test caches were removed; fixture source remains under `Tools/` for reproduction.

## Reproduce

Run `make test` in a dedicated temporary DerivedData directory. The window-number test requires `LENS_TEST_WINDOWSERVER=1` and an uncontested desktop; it first checks its control window, and it is not a replacement for physical input delivery.

For a separate process fixture, compile `Tools/InputFixture.swift` with `xcrun swiftc -parse-as-library`, place the executable under a temporary `InputFixture.app/Contents/MacOS/InputFixture`, and copy `Tools/InputFixture-Info.plist` to its `Contents/Info.plist`. This fixture is not linked into Lens or distributed. Place Lens over it, enable click-through in the header, and check click/drag/scroll counters, the typing field, header input isolation, numeric changes, animation pause, move/resize, close, and Settings handoff. Preserve user preferences and remove only generated test artifacts afterward.

## Remaining limitations

Layout-only OCR cannot unambiguously distinguish every borderless table, aligned prose column, menu, or cross-language fragment. Very short isolated labels remain conservative. Japanese joins do not insert spaces; mixed Latin runs and soft hyphenation may still need refinement. There is no target-word alignment, so a changed part of a context hides its whole translated block. Reduced pixel sampling can miss tiny/low-contrast changes. These are limitations, not claims of universal semantic or input acceptance.
