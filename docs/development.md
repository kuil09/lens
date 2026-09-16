# Development

This guide covers building and testing source, not the status of an installed app or published DMG. Use [release records](https://github.com/kuil09/lens/releases) for version-specific evidence and [Releasing](releasing.md) for packaging/publication.

## Requirements and build identity

Use an Apple Silicon Mac, macOS 26.4 or later, and Xcode 26.4 or later. The package declares Swift tools 6.2 and Swift 6 language mode, without external package dependencies. CI's exact Xcode/runner selection lives in [Lens CI](../.github/workflows/ci.yml) and [Lens Notarized DMG](../.github/workflows/notarized-dmg.yml); recheck those files when reproducing CI.

The default DerivedData is `build-design`; its Release app is `build-design/Build/Products/Release/Lens.app`. Keep a stable build location and signing identity when testing permission continuity. The bundle identifier is defined in [Application.xcconfig](../Config/Application.xcconfig), currently `dev.local.lens`. Do not change it casually: preferences and OS consent belong to the app identity.

Version, build, and prerelease channel have one source of truth: [Version.xcconfig](../Config/Version.xcconfig). Check the built Info.plist and About panel rather than copying a historical build number into commands.

## Commands

Run from the repository root; the Makefile wraps `scripts/lens.sh` and forwards options through `ARGS`.

```sh
make check
make test
make build
open build-design/Build/Products/Release/Lens.app
```

- `check`: shell syntax, Git whitespace/index hygiene, synthetic artifact/process regressions, installer settings, and notarization metadata/preflight tests with fake credentials. It does not import keys or contact Apple.
- `test`: SwiftPM tests under `build-design/SwiftPM`, explicitly serialized with `--no-parallel` in both local and CI execution. This is not an Xcode scheme test action. Serial scheduling does not filter tests or disable assertions; see the [hosted-runner comparison](validation-history.md) for the mitigation evidence and its limits.
- `build`: Release app using the configured local signer (ad-hoc by default). No notarization, publication, installation, or automatic launch.
- `open`: explicitly launches the app you just built; only run it when ready to test that copy.

Build/test/clean refuse a process running from the selected output tree. Quit that app before modifying its output. For isolated work, `--derived-data` accepts an existing, user-owned physical temporary directory matching the constraints printed by `bash scripts/lens.sh --help`. Do not replace the canonical installed app with a temporary identity/path merely to run tests.

`make clean` irreversibly removes known generated children of the selected DerivedData, including its app and test scratch output. It preserves `dist`, legacy build trees, and the separate root `.build`; it is not required before routine builds. Inspect disposable targets first. Generated archives, recordings, private logs, provisioning profiles, and signing files must remain outside Git; index hygiene rejects such artifacts even outside ignored build directories.

## Stable local signing

[Application.xcconfig](../Config/Application.xcconfig) optionally includes the ignored `Config/LocalSigning.xcconfig`. Use [LocalSigning.xcconfig.example](../Config/LocalSigning.xcconfig.example) as a template and supply one installed certificate's SHA-1 identity and team identifier. Keep private keys in Keychain; never commit/export them as part of ordinary local setup. Fresh clones and unprivileged CI use ad-hoc signing; protected notarization CI supplies its own identity separately.

Both `make build` and Xcode honor this local configuration. An unusable configured signer fails the build rather than silently falling back to ad-hoc. Inspect the actual app:

```sh
codesign --display -r- --verbose=2 build-design/Build/Products/Release/Lens.app
codesign --verify --deep --strict build-design/Build/Products/Release/Lens.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build-design/Build/Products/Release/Lens.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build-design/Build/Products/Release/Lens.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :LensReleaseChannel' build-design/Build/Products/Release/Lens.app/Contents/Info.plist
```

The designated requirement should bind the existing signer and app ID rather than one build's code hash. Transitioning from ad-hoc signing can require another Screen Recording grant/relaunch; stable signing does not guarantee permanent consent. See Apple's [code identity guidance](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). Signature validity alone is not notarization or Gatekeeper acceptance.

## Source map

- `Sources/Lens/App`: lifecycle, windows, toolbar/resize input, settings, reading snapshots, export actions/storage.
  `LensAppDelegate` coordinates startup, return and permission handoff; `LensMenuController` owns menu construction/status item, `LensExportCoordinator` owns export actions and directory selection, `LensAuxiliaryWindows` owns help/reader/language-guide lifetimes, and `LensObservationBag` removes tokens from their issuing notification centers.
- `Sources/Lens/Capture`: ScreenCaptureKit region capture and permission checks.
- `Sources/Lens/OCR` and `Core`: OCR, paragraph/language decisions, geometry, regional scheduling and stale-result gating.
- `Sources/Lens/Translation`: language availability, system download guide, installed-model sessions, cache and synthetic benchmark.
- `Sources/Lens/Rendering`: live display, block masks, overflow popovers, PNG composition and MP4 writing.
- `Sources/Lens/Core/L10n.swift` and `Sources/Lens/Resources/*.lproj`: interface localization; see [Localization](localization.md).
- `Tests/LensTests` and [Tools/fixture.html](../Tools/fixture.html): automated checks and synthetic manual input.

See [Architecture](architecture.md) for context, scheduling, input, and recording invariants. OCR permits at most four starts per second with one running OCR job, one translation batch, and one latest pending frame. Whole-frame OCR does not imply global display invalidation. The translation cache is bounded to 1,000 entries. These are implementation budgets, not measured latency guarantees.

The OCR worker schedules one cancellable deadline instead of polling while waiting. New frame observations can advance that wake; reset invalidates stale callbacks. Display publication and TextKit layout reuse require exact matching data, not approximate text similarity. Frame/epoch validity still determines whether a translation can be shown.

## Verification boundaries

Installed-model tests are opt-in:

```sh
make test ARGS='--installed-languages'
```

This uses already-installed models; it does not authorize downloads. Read the current fixtures in `Tests/LensTests` for required pairs. The separate foreground-WindowServer opt-in and native test renders are not substitutes for real input routing or a screen-permission grant. Keep test preferences and synthetic output separate from user data.

The translation benchmark includes 30 Korean/Japanese/English reference triples across six directions; assess meaning rather than exact output equality. It is not exhaustive catalog coverage. Render-submission timing is not actual display latency.

A passing suite does not establish whole-runtime acceptance, offline recovery, clean-machine installation, or notarization. Follow the [manual acceptance matrix](releasing.md#manual-acceptance-matrix); record exact candidates and skipped checks. Earlier local UI/signing/export observations are preserved in [historical verification boundaries](validation-history.md), not presented here as current acceptance.
