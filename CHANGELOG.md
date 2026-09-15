# Changelog

## 0.1.0-beta.4 — 2026-09-15 (build 10)

- Successful PNG saves replace the header camera with a localized checkmark for 1.5 seconds. A new attempt clears it, and stale timers cannot erase a newer success. Recording state is independent.
- Open the current shared save folder directly from the toolbar, File menu, or menu-bar item, including while paused or locked. Missing custom folders and Finder failures offer save-settings recovery without silently changing the destination.
- Explicit Show Lens now restores keyboard focus; minimize hides both panels and pauses capture/finalizes recording, while restoration does not restart capture. Reader, language-pack, and help windows explicitly deminiaturize when reopened.
- Preserve existing overlay Spaces eligibility and disallow independent header tiling. Saving/unavailable tooltips and click-through help explain the next action. The permission-return guide now observes installed-language readiness directly instead of retaining stale setup copy. See the [UX review and verification boundaries](docs/ux-capture-and-windows.md).
- Developer ID signed, nonnotarized DMG; source history consolidated into one baseline. Separately authorized publication replaces the beta.3 GitHub downloads; the beta.3 source tag is retained. See [release notes](docs/releases/v0.1.0-beta.4.md).

## 0.1.0-beta.3 — 2026-09-15 (build 9)

- Consolidated the development history into one release baseline. This Developer ID signed, nonnotarized DMG replaces the earlier preview downloads; the bundle identifier and user settings are unchanged.

- OCR source-line coordinates, contextual translation input, completed reference translations, and whole-block visibility masks are separate representations. Wrapped short tails share context; list/table/column and language boundaries remain conservative.
- A disjoint interactive header panel stays usable while only the attached body panel passes mouse input through. The header provides click-through release alongside language, translation, capture, recording, and settings controls.
- Parent/child geometry, shutdown, explicit return, and security handoff coordinate both panels. Exports and capture remain body-only with process-wide self-exclusion.
- See [context/input evidence and remaining acceptance](docs/context-and-input.md), including the live counter-test limitation.

- Region-adaptive scheduling keeps unrelated translations visible while changing areas back off from 250 ms to 500 ms, 1 s, and 2 s. Capture rendering remains independent.
- Exact paragraph reuse and per-pixel revision checks reject stale numeric, negation, and A-to-B-to-A responses without canceling unrelated translation work.
- Full-frame Vision observations preserve paragraph context across grid boundaries; one OCR operation and one small translation batch remain the shared budgets.
- Corrected reduced-bitmap orientation against Vision coordinates, verified with real OCR over synthetic text.
- Added deterministic scheduling/concurrency tests and a local mixed static/animated screen fixture. The recording-duration regression now compares against observed stop time instead of assuming a task sleep finishes within two seconds on loaded CI.
- See [adaptive backoff evidence and limitations](docs/adaptive-backoff.md). Build 9 packages the implementation tested in local builds 7 and 8; it does not claim completion of their outstanding runtime acceptance.

## 0.1.0-beta.2 — 2026-09-15 (build 6)

- English, Korean, and Japanese UI resources across menus, settings, onboarding, status/errors, accessibility, and language names; macOS app-language selection with English fallback, independent of translation packs.
- Installed-only source/target pickers, OS-preferred installed target fallback, and stale selection recovery after model removal.
- Three-step first-launch guide for screen access, translation languages, and the automatic image/video save folder; reopen from Help.
- Native Liquid Glass controls, centered source/target swap, frosted idle state, and a transparent active lens.
- Automatic timestamped PNG/MP4 exports to one persistent folder, exclusive no-overwrite publication, and in-memory recent-file access.
- System Settings handoff hides and pauses the overlay without weakening secure input or resetting permissions.
- Normal return guidance, a visible Later state, and persisted incomplete onboarding; launch/reopen/recheck never request permission or start capture. Settings handoff and quit drain capture shutdown and video finalization without background error alerts stealing authentication focus.
- Separate preparation selection prevents the add-language screen from changing the live translation target; capture-start failures clear any partial output.
- Repository hygiene checks now cover staged provisioning profiles and generated test archives, with synthetic Git-index regressions and matching ignore rules.
- Removed an unused translation-strategy chooser and its obsolete test; installed-pack policy, cancellation, and cache isolation remain covered.
- Optional gitignored local signing configuration preserves the signer and app identifier across development rebuilds; the build wrapper no longer forces ad-hoc signing over it. Store submission and external notarization are not enabled.
- Developer ID signed app in a drag-install DMG with MIT license and SHA-256 sidecar. This development prerelease is not notarized; Gatekeeper acceptance is not claimed.
- Paid Mac App Store distribution is planned as a one-time purchase, not a subscription. Store signing, sandbox migration, and submission are deferred; separate Developer ID notarization remains withdrawn.

## 0.1.0-beta.1 — 2026-09-15

App version: **0.1.0 (build 2)**. Development preview; the downloadable Release build is ad-hoc signed and not notarized.

### Added

- Resizable screen-translation lens with reproduced-background and transparent modes, source masking, click-through, and a full-text reader.
- Runtime Apple Translation language catalog, Vision-compatible source selection, installed-pair preparation, and a target preference that can follow supported macOS preferred languages.
- Korean native settings and menus, a lens toolbar, explicit PNG export, and silent MP4 recording.
- Development, usage, privacy, troubleshooting, release/manual acceptance, contribution, and security documentation; issue and pull request templates.
- A blue glass app icon with an A-to-가 translation motif, macOS standard and Retina sizes, and asset validation tests.
- Native About panel reads version, build, and release channel from bundle metadata; the candidate display is 0.1.0-beta.1 (2).
- Privacy manifest declares no tracking or collected data types, with reasons for same-app preferences and elapsed-time APIs. This declaration is not a privacy certification.

### Release readiness

- [MIT License](LICENSE), copyright **2026 kuil09**, is included in the development ZIP alongside the app.
- Public bundle identifier and Developer ID signing/notarization remain pending. This preview retains the development identifier `dev.local.lens`.
- Some translation has been observed during use. Formal whole-runtime acceptance, broad translation-quality review, end-to-end performance, offline/download recovery, multiple monitors, and sustained-operation checks remain incomplete.
- Translation-language selection is dynamic; the app UI remains Korean. Neither every OS language nor full UI localization is claimed.
