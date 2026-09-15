# Development

**Current source and GitHub preview:** beta.5/build 11. The notarized DMG and its verification are described in [the installer guide](dmg-installer.md). Version-specific beta.2 paths and checks below are historical, not the current output. Packaging derives names from `Config/Version.xcconfig`. DMG creation additionally requires the pinned packaging-only tools in that guide; ordinary builds are not automatically notarized.

## Requirements and build identity

Use an Apple Silicon Mac with macOS 26.4 or later and Xcode 26.4 or later. The Swift package uses Swift tools 6.2 and Swift 6 language mode, with no external package dependencies.

The canonical DerivedData directory is `build-design`, and the Release app is `build-design/Build/Products/Release/Lens.app`. Preserve this location and the existing installed app identity to avoid unnecessary Screen Recording reauthorization. The current project bundle identifier is `dev.local.lens`; the source prerelease is 0.1.0-beta.2 (build 6). A stable signer is also needed: the same path alone does not make an ad-hoc identity stable across builds. See [distribution](distribution.md) for planned store work, separate from owner-authorized local signing.

## Commands

Run these from the repository root. The Makefile wraps `scripts/lens.sh` and forwards options through `ARGS`.

```sh
make check
make test
make build
open build-design/Build/Products/Release/Lens.app
```

`check` validates shell syntax, Git diff whitespace, and staged/index artifact hygiene through `scripts/repository-hygiene.sh`, with NUL-safe path handling including provisioning profiles and xcresult bundles. It runs the synthetic index checks in `scripts/tests/repository-hygiene.sh` and the existing packaging/process/signature regressions in `scripts/tests/regression.sh`. These checks do not establish runtime or signing success. `test` uses SwiftPM scratch output under `build-design/SwiftPM`. `build` produces the Release app with `dev.local.lens` and the configured local signer (ad-hoc by default); it does not notarize or submit to the App Store.

Build, test, and clean refuse to proceed when a process is running from the selected output tree. Packaging refuses when its selected app is running; packaging another app through `--app` does not stop or mutate a running canonical app. Quit the relevant app yourself when required. The wrapper never launches or quits Lens. For isolated work while the canonical app is running, `--derived-data` accepts a dedicated existing, user-owned physical temporary directory as described by `bash scripts/lens.sh --help`; do not switch the canonical installed app to a temporary identity/path.

After building and quitting Lens, create an explicitly nonnotarized development package:

```sh
make package ARGS='--development'
```

This consumes an existing app; it does not build or sign it. With current version metadata it writes `dist/Lens-0.1.0-beta.2-6-DEVELOPMENT-NOT-NOTARIZED.zip` and a `.zip.sha256` sidecar, refusing to overwrite existing outputs. The ZIP contains `Lens.app` and the repository `LICENSE` at its root. Both packaging modes require the license and validate bundle version/build/channel, arm64 support, minimum macOS version, and the bundled privacy manifest. This is a development artifact, not a notarized distribution; publication still requires separate authorization. See [releasing](releasing.md) for packaging contracts and manual acceptance. The retained Developer ID publication workflow is inactive and is not a Mac App Store build path.

`make clean` irreversibly removes only known generated children of the selected DerivedData, including its built app and SwiftPM scratch output. It preserves `dist`, legacy build directories, and the separate root `.build`. It refuses unsafe/symlinked targets and a running app. Use it only when those generated outputs are disposable; it is not a prerequisite for routine builds.

Local housekeeping on September 15 retained only the latest signed app in that canonical output tree, plus DerivedData metadata. Obsolete distribution archives and intermediate caches were removed; the next build/test will regenerate its scratch files. Do not run `make clean` to preserve an installed app. ZIP, DMG, and PKG outputs belong outside Git: ignore rules and the staged-artifact check reject them even outside `dist/`. The current local package is `dist/Lens-0.1.0-beta.2-6-DEVELOPMENT-NOT-NOTARIZED.dmg` with a SHA-256 sidecar; its app is Developer ID signed, but the package is not notarized.

Version/build/channel come from `Config/Version.xcconfig`. The native About panel reads the built bundle and should display `0.1.0-beta.2 (6)` for this candidate; verify the actual artifact. The public identifier in `Config/Distribution.xcconfig` remains blank after the earlier notarization withdrawal. The store direction does not activate this external distribution configuration.

## Stable local signing

`Application.xcconfig` optionally includes `Config/LocalSigning.xcconfig`. Copy the example beside it and replace the placeholders with one installed code-signing certificate's SHA-1 identity and its team identifier. Keep private keys in Keychain; never export or commit them. This machine-local configuration is gitignored and rejected by the repository index check. A fresh clone and CI retain the default ad-hoc build.

The normal `make build` and Xcode project both honor this setting. A configured certificate that cannot sign causes a build failure; the wrapper does not silently replace it with ad-hoc signing. Keep the signer and bundle identifier consistent. See Apple's [code identity explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Inspect the actual app with `codesign --display -r- --verbose=2` and `codesign --verify --deep --strict`. Its designated requirement should identify the signer and `dev.local.lens`, not one build's `cdhash`. The initial change from ad-hoc signing can require a new Screen Recording grant and relaunch. This does not bypass macOS consent or guarantee that the OS will never request confirmation again. Local Developer ID signing does not establish notarization, Gatekeeper acceptance, or App Store readiness.

## Source map

- `Sources/Lens/App`: windows, settings, menus, lifecycle, and export actions.
- `Sources/Lens/Capture`: ScreenCaptureKit region capture and permission checks.
- `Sources/Lens/OCR` and `Core`: Vision OCR, geometry, frame analysis, and stale-result gating.
- `Sources/Lens/Translation`: runtime language catalog, pair routing, installed-model sessions, cache, and synthetic benchmark.
- `Sources/Lens/Rendering`: captured background, translation overlay, PNG composition, and MP4 writing.
- `Sources/Lens/Core/L10n.swift` and `Sources/Lens/Resources/*.lproj`: shared UI locale resolution and translations; see [localization](localization.md).
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

The dated checks below preserve earlier observations and their limits; they are not a fresh acceptance run for every later source change. See [beta.2 readiness](releases/beta.2-readiness.md) for candidate evidence and [localization validation](localization.md#validation-2026-09-15) for the later UI-language checks.

### Liquid Glass development check — 2026-09-15

Native inspection verified the paused lens and independent translation settings window, readable language labels after disabling titlebar accessory auto-sizing, and Korean/Japanese swapping in both directions. The original language selection was restored. The paused background uses the system glass material; translation activation removes it rather than drawing captured pixels over the desktop. Tests cover these presentation states, one invalidation per swap, unsupported/automatic-source swap guards, reduced-transparency fallback, and controls remaining outside the capture region at 800×500 and 320×240 content sizes.

Live activation stopped at the current development build's Screen Recording permission check. Transparent live translation, light appearance, and a full accessibility/contrast audit remain unverified. Offscreen view renders are layout aids, not evidence of compositor-rendered glass. No notarization or release publication was performed for this UI candidate.

### Automatic export folder check — 2026-09-15

`LensExportTests` exercise same-timestamp image accumulation, bookmark persistence, missing/read-only folders, damaged bookmarks, exclusive publication after a filename collision, and folder changes during a real synthetic MP4 recording. The video decode test also verifies that an existing destination survives finalization and the new MP4 is written under a different name. Temporary image writes and video finalization share an exclusive, same-directory rename; collisions receive numeric suffixes. Export preferences do not invalidate translation or stop an ongoing recording.

The settings folder selector uses `NSOpenPanel`; capture/record entrypoints contain no save dialog. Native UI automation timed out while the previous app remained running, so folder-panel interaction and real desktop capture-to-folder remain unverified for this change. The test fixtures use isolated preferences and temporary directories, not user captures.

### System permission handoff check — 2026-09-15

`LensSystemHandoffTests` exercise the production panel initializer, loss of visibility/key eligibility during handoff, idempotent suspension, and explicit-only restoration without restarting capture. Only System Settings activation triggers this policy; ordinary applications retain the translation overlay. The permission request path waits for the capture-stop task before calling the OS request, and keeps the lens hidden afterward. Existing once-per-launch permission-request tests still apply.

The user's real administrator-password stall has not been reproduced in an authentication dialog. Native inspection failed with ScreenCaptureKit error -3811, so no password was requested, read, or entered. The canonical app's workspace icon lookup was refreshed with a narrowly scoped registration update; a same-size 64-pixel comparison changed from zero blue-dominant pixels to 1,175. This establishes an icon-service lookup change, not that System Settings has repainted its existing row.
