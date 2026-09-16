# Architecture and invariants

## Ownership

`LensAppDelegate` coordinates application startup, permission handoff, and capture restart/stop. `LensMenuController` owns menus/status items, `LensExportCoordinator` owns export actions and directory selection, and `LensObservationBag` removes notification tokens from their issuing centers.

`LensAuxiliaryWindows` owns help, reader, and language-guide windows. Reader/help content is reused; a closed language guide releases its content and subscriptions. Creating a window does not present it. Explicit presentation restores minimized windows. The reader takes a snapshot only when newly opened, not on ordinary focus return. Onboarding and permission windows remain in the delegate's security flow.

`LensToolbarState` supplies the shared menu/toolbar capture and recording eligibility. A running recording can always be stopped, even without a current capture frame. Success feedback never disables another screenshot.

## Context, validity, and reading

ScreenCaptureKit updates the original surface independently of OCR/translation. OCR retains physical source lines and coordinates, groups wrapped prose, and classifies its language independently of the selected source. Explicit-source mode translates only confidently matching paragraphs; ambiguous/mixed text remains original. Auto mode skips the target language.

One paragraph maps to one translation request and conservative display rectangle. Apple Translation request identifiers preserve correspondence but do not provide screen coordinates, word alignment, or a separate context-only channel. Grid boundaries must not split paragraph context; batch neighbors are not assumed to share semantic context.

Completed references and the live visibility mask are separate. Pixel invalidation hides the entire affected translation and cover immediately, not arbitrary parts of glyphs. Exact source, language, geometry, scene epoch, and pixel revisions govern reuse and late-response rejection; numeric/negation changes are never fuzzy-matched. Unrelated valid paragraphs stay visible.

The reader keeps a separate manually applied snapshot, including previous-screen/pending labels. Popovers keep the clicked truncated result fixed and require click-through off. Invalidation, movement, hiding, deactivation, permission handoff, and enabling click-through dismiss them. Neither reading history nor screen text is written to disk by this pipeline.

## Scheduling and rendering budgets

- Live capture: up to 30 fps. OCR: at most four starts per second, one active operation, one latest pending frame. Translation: one batch, up to four same-language paragraphs, oldest waiting first. Cache: 1,000 entries.
- Regional observation: 128 × 80 RGBA sample, 8 × 5 scheduling grid. Each due group shares a full-frame Vision observation; this does not claim reduced Vision pixel area.
- Responsiveness intervals: Calm 500/1,000/2,000/3,000 ms; Balanced (default) 250/500/1,000/2,000 ms; Fast 250/375/500/750 ms. Escalation is paced at 250 ms for Calm/Balanced and 500 ms for Fast. A 120 ms quiet period permits early reinspection while the global 4 Hz limit remains.
- One cancellable wake replaces deadline polling. New observations may advance it; reset invalidates stale callbacks. No catch-up bursts or accumulated historical requests.
- Valid new live translations reveal over 140 ms; unchanged blocks retain layouts and do not animate again. Invalid blocks hide immediately. Reduce Motion and frequent-change suppression apply. PNG/MP4 use valid completed composition, not intermediate live fade states.

These are resource/scheduling limits, not latency or total-process-memory guarantees. Reduced sampling can miss tiny/low-contrast changes; continuous paragraph changes may keep that paragraph hidden. Broad scene changes reset prior correspondence.

## Window and security boundaries

The header, body, and narrow resize strips are separate AppKit input regions. Only the body uses `ignoresMouseEvents`; header controls and exterior resize edges remain interactive. No event tap, event reinjection, or accessibility permission is required. Window flags alone do not prove physical input forwarding.

Capture uses the body rectangle and excludes the Lens application. Export composition excludes toolbar, resize markers, popovers, feedback, and the red recording outline. Recording locks geometry. Close/minimize/sleep and actual capture invalidation retain their stop/finalization policies.

Ordinary System Settings visits do not trigger permission handoff. Only Lens's explicit screen-access action stops work and hides all overlay panels. Returning shows the appropriate guide without automatically restarting capture or recording.

## Recording

`RecordingWorker` owns a serial background compositor independent of live rendering. It retains original capture timestamps and reuses existing OCR/translation results; it creates no extra OCR or translation workers. Two-dimensional movement candidates require source-pixel evidence before a translation and its cover can relocate. Uncertain movement or changed content falls back to the original.

Silent H.264 output is capped at 15 fps. The delayed compositor keeps at most 12 source-frame slots/96 MiB and waits at most 0.8 seconds. Source evidence/pending references share 32 entries/16 MiB; glyphs have a separate 32-entry/16 MiB cache. Encoder backpressure drops work rather than accumulating an unbounded queue. No raw-video disk cache is used.

Plain-background documents are the initial target. Clipped text, complex backgrounds, fast movement, and translations arriving too late can expose source text. Complete translation coverage during arbitrary motion is not guaranteed.
