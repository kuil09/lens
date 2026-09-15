# Region-adaptive backoff

Introduced in local **0.1.0-beta.3-dev (build 7)**; build 8 extends it with [context and input separation](context-and-input.md). The evidence below records build 7 unless otherwise stated. The implementation is packaged in [beta.3/build 9](releases/v0.1.0-beta.3.md) under subsequent publication authorization; no notarization was resumed.

## Scheduling and validity

- `RegionalBackoff` observes the existing 128 × 80 RGBA sample in an 8 × 5 grid. A sample pixel changes when its RGB absolute-difference sum exceeds 24. Small fades accumulate against the last significant value. Sampling rows are normalized to Vision's bottom-left coordinates.
- Dirty regions escalate at most once per 250 ms through **250 ms, 500 ms, 1 s, 2 s**. Continued changes do not slide the processing deadline indefinitely. These are scheduling intervals, not translation latency guarantees.
- A **120 ms quiet period** permits early inspection, retaining the former settling criterion. The worker checks deadlines every 30 ms, including when capture stops delivering idle frames. Global OCR starts remain at least 250 ms apart. Stable observations/results restore the base interval. Stale replies do not restart the source quiet period; service errors remain paced and do not create immediate retry loops.
- Every due cell shares one full-frame Vision `.accurate` request. A paragraph is handled as a whole only when all of its pending cells are selected. This deliberately preserves sentence context and avoids a second region-cropping OCR pass. **It reduces request frequency and selected-region processing, not the pixel area Vision examines during a shared observation.** ROI CPU savings are not claimed.
- One OCR operation and one translation batch may run concurrently. Translation batches contain at most four paragraphs of the same source language, oldest waiting first. There is one pending latest frame and one current paragraph table, not historical frame or request queues. In-flight operations also retain their submitted snapshots. Paragraph memory scales with current recognized screen complexity; there is no arbitrary truncation that starves later paragraphs.
- All due regions are observed together, so one region cannot displace another. There are no catch-up bursts. OCR saturation wait is measured beyond the region deadline and shared 4 Hz budget; translation queue wait is measured separately. Both are in-memory diagnostics, not disk telemetry.

Pixel revision checks use each paragraph's footprint with one reduced-pixel padding, not its entire scheduling tile. Only affected translations hide immediately; the original screen remains visible while waiting. Exact UTF-8 text, language, and position (normalized component tolerance 0.002) are required for reuse. Numeric and negation differences are never fuzzy-matched. Epoch and per-pixel revisions reject late results, including A → B → A changes. An unchanged paragraph can keep its translation even when another element in the same grid cell animates.

Geometry/language invalidation clears the prior epoch. Broad changes (at least 24 of 40 cells and 4% of sampled pixels) conservatively start a new scene; a 250 ms gap separates broad-change episodes so continuous full-screen motion cannot repeatedly reset its own deadline. This is a scene-change heuristic, not an animation classifier. Smaller scrolls invalidate affected footprints and are re-observed without position tracking. Local changes never cancel unrelated batches; context/scene changes still invalidate the old scene.

Capture rendering, security/permission handoff, installed-language selection, save-folder persistence, and image/video export remain on their existing paths. No settings or modes were added.

## Automated evidence — 2026-09-15

`make test ARGS='--derived-data <temporary-directory>'` exercises the injected monotonic clock, synthetic pixels, suspended OCR/translation operations, and a stub translation engine.

- Six seconds of 100 ms alternating changes: **4 total OCR requests, 3 translation batches, 1 static-body translation request, 0 global cancellations**; the body remains visible at every sampled step. This is a fixed-clock scenario, not wall-clock performance data.
- Backoff reaches 2 s, continues periodic inspections, and recovers after 120 ms quiet rather than waiting out the cap. All due cells share one observation; four-paragraph batches drain 40 simultaneous paragraphs without starvation. Repeated observations replace 300 current paragraphs rather than retaining 600 versions.
- Tests cover local in-flight invalidation within the same cell, exact reuse, changed numbers/negation, A → B → A, delayed replies, one-worker limits, latest-frame retention, global 4 Hz pacing, broad continuous motion, scene/language reset, gradual fades, and cross-grid paragraphs.
- A real Core Image sampler and real Vision OCR render synthetic English text in memory. A neighboring A/B label leaves body translation intact; changing `Do not delete 12 files.` to `Delete 13 files.` immediately hides the old translation and produces a new OCR record. Translation itself is stubbed in this test. This test exposed and guards against a vertical bitmap/Vision coordinate mismatch.
- Full suite: **77 executed tests passed** (74 Swift Testing + 3 XCTest); two opt-in installed-model tests skipped. Shell/index hygiene regressions are checked separately with `make check`.

## Live fixture and remaining boundaries

Open `Tools/regional-backoff.html` in a browser and place the lens over the article and sidebar. The fixture has a spinner, 100 ms A/B text, a clock, pause/resume, exact number/negation replacement, page replacement, and scrollable content. Keep the whole sentence inside the lens.

Live ScreenCaptureKit/Apple Translation acceptance is recorded separately below; synthetic Vision and fake-engine tests do not establish desktop behavior, installed-pack availability, translation quality, or latency percentiles. Reduced sampling may miss sufficiently tiny/low-contrast glyph changes; one-pixel padding is conservative and can temporarily hide neighboring text. Continuous changes inside a paragraph can keep its translation hidden even though inspection continues. Large full-screen animations may trigger the broad scene heuristic. Real multi-monitor movement, sustained memory/CPU behavior, and end-to-end timing still require separate acceptance.

### Observed desktop checks

- The signed local build 7 opened with screen-recording permission reported as granted; no TCC reset or new permission request was performed. Explicitly starting translation enabled capture.
- With English → Korean selected temporarily, actual Apple Translation rendered the stable fixture body and `Do not delete the remaining 12 files.` while the neighboring spinner, A/B label, and clock continued changing. Several separate UI snapshots retained the body; this is sampled visual evidence, not continuous frame-by-frame measurement. Moving/resizing the lens restarted capture and produced translations at the new location.
- The browser's native automation did not activate the fixture change buttons. Direct tab control was then denied by the browser local-file URL policy. No alternative URL, policy change, or bypass was used. Consequently **live number/negation changes, pause-to-recovery timing, cap-period inspection, page replacement, scrolling, click-through input delivery, and per-region request counts remain NOT_RUN/unverified**; their algorithmic coverage above is not substituted for desktop acceptance.
- The original Korean → Japanese selection and click-through-off state were restored, the previous window size restored, and translation stopped after inspection. Save-folder preferences and exports were not changed. The final stale-reply quiet-period refinement has automated coverage; its precise recovery timing was not measured on the desktop.
