# Development

## Requirements and build identity

Use an Apple Silicon Mac with macOS 26.4 or later and Xcode 26.4 or later. The Swift package uses Swift tools 6.2 and Swift 6 language mode, with no external package dependencies.

The canonical DerivedData directory is `build-design`, and the Release app is `build-design/Build/Products/Release/Lens.app`. Preserve this location and the existing installed app identity to avoid unnecessary Screen Recording reauthorization. The current project bundle identifier is `dev.local.lens`; the public bundle identifier is awaiting an owner decision.

## Commands

Run these from the repository root. The Makefile wraps `scripts/lens.sh` and forwards options through `ARGS`.

```sh
make check
make test
make build
open build-design/Build/Products/Release/Lens.app
```

`check` validates shell syntax, Git diff whitespace, tracked-artifact hygiene, and script regressions. `test` uses SwiftPM scratch output under `build-design/SwiftPM`. `build` produces the Release app with the existing `dev.local.lens` identity and ad-hoc signing; it does not sign for public distribution or notarize.

Build, test, and clean refuse to proceed when a process is running from the selected output tree. Packaging refuses when its selected app is running; packaging another app through `--app` does not stop or mutate a running canonical app. Quit the relevant app yourself when required. The wrapper never launches or quits Lens. For isolated work while the canonical app is running, `--derived-data` accepts a dedicated existing, user-owned physical temporary directory as described by `bash scripts/lens.sh --help`; do not switch the canonical installed app to a temporary identity/path.

After building and quitting Lens, create an explicitly nonnotarized development package:

```sh
make package ARGS='--development'
```

This consumes an existing app; it does not build or sign it. With current version metadata it writes `dist/Lens-0.1.0-beta.1-2-DEVELOPMENT-NOT-NOTARIZED.zip` and a `.zip.sha256` sidecar, refusing to overwrite existing outputs. The ZIP contains `Lens.app` and the repository `LICENSE` at its root. Both packaging modes require the license and validate bundle version/build/channel, arm64 support, minimum macOS version, and the bundled privacy manifest. This is a development artifact, not a notarized distribution; publication still requires separate authorization. See [releasing](releasing.md) for public packaging gates and the separate manual Developer ID workflow.

`make clean` irreversibly removes only known generated children of the selected DerivedData, including its built app and SwiftPM scratch output. It preserves `dist`, legacy build directories, and the separate root `.build`. It refuses unsafe/symlinked targets and a running app. Use it only when those generated outputs are disposable; it is not a prerequisite for routine builds.

Version/build/channel come from `Config/Version.xcconfig`. The native About panel reads the built bundle and should display `0.1.0-beta.1 (2)` for this candidate; verify the actual artifact. The public identifier in `Config/Distribution.xcconfig` remains blank pending approval.

## Source map

- `Sources/Lens/App`: windows, settings, menus, lifecycle, and export actions.
- `Sources/Lens/Capture`: ScreenCaptureKit region capture and permission checks.
- `Sources/Lens/OCR` and `Core`: Vision OCR, geometry, frame analysis, and stale-result gating.
- `Sources/Lens/Translation`: runtime language catalog, pair routing, installed-model sessions, cache, and synthetic benchmark.
- `Sources/Lens/Rendering`: captured background, translation overlay, PNG composition, and MP4 writing.
- `Tests/LensTests`: automated checks; `Tools/fixture.html`: synthetic manual fixture.

Rendering and OCR run at separate cadences. OCR is throttled to at most four starts per second, and changes currently reprocess the whole lens region. Work versions reject obsolete results; the text cache is bounded to 1,000 entries and keyed by text, languages, and model strategy. These are code-level controls, not measured user-visible latency or stability guarantees.

## Verification boundaries

Automated tests cover geometry, OCR, language matching/preferences, pair routing, cache/cancellation, permissions, native controls, and synthetic exports. Some native view tests produce temporary synthetic renders; do not add generated screenshots or personal logs to the repository.

Installed-model tests are opt-in:

```sh
make test ARGS='--installed-languages'
```

The wrapper sets `LENS_TEST_INSTALLED_LANGUAGES=1` only for this option and disables inherited opt-in otherwise. These tests exercise synthetic French/German/Chinese-to-Korean and Korean-to-French samples, require the relevant models already installed, and do not request downloads. A missing model is not evidence that the screen-translation pipeline is broken.

The translation benchmark contains 30 Korean/Japanese/English reference triples across six directions. Inspect meaning rather than demanding exact output matches. It is not exhaustive coverage of the dynamic language catalog. Internal render timing measures submission, not actual display latency.

A passing test suite or CI build does not establish a Screen Recording grant, installed-model success, whole-runtime acceptance, translation quality, performance, or notarized distribution. Use the [manual acceptance checklist](releasing.md) for those boundaries.
