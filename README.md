# Lens

A local macOS translation lens for Korean, Japanese, and English.

**Development preview.** End-to-end screen translation has not yet been verified. Translation quality and performance are not validated.

## Requirements and build

- Apple Silicon, macOS 26.4+, Xcode 26.4+.
- No third-party packages or model servers.

```sh
xcodebuild -project Lens.xcodeproj -scheme Lens -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Lens.app
swift test
```

Local builds are ad-hoc signed, not notarized. Rebuilding may require reauthorizing Screen Recording. Permission requests are triggered only by an explicit start/permission action, at most once per launch.

## Use

1. Grant Lens Screen Recording in System Settings → Privacy & Security → Screen & System Audio Recording. Relaunch if requested.
2. Choose **언어 준비**, then **언어 팩 준비** and accept Apple's download sheet. After all six directions are ready choose **시작**.
3. Place and resize the lens over text. Source defaults to automatic and target to Korean. Use an explicit source for ambiguous short labels.
4. **화면 재현** displays the captured scene inside the lens; **투명** shows the actual desktop underneath. **원문 가림** adjusts the text mask, not the translation's opacity.
   A thin dark-and-light border remains visible in either mode, including while paused or moving. It does not intercept mouse events.
5. **잠금** passes mouse/scroll events through the lens. The separate controls and menu-bar item remain accessible. **전문 보기** shows untruncated translations.

App menu shortcuts (when Lens is active): Command-L show, Command-R start/pause, Command-K lock, Command-comma prepare languages, Command-T full text. These are not global hotkeys.

## How it works

ScreenCaptureKit captures the lens region while excluding Lens itself. Core Image/MetalKit render the scene independently of Vision OCR. Apple Translation uses installed on-device language models. Recognition is limited to 4 Hz; bounded work queues, version checks and a 1,000-entry memory cache prevent obsolete results and unbounded backlog.

The app stores settings, not screen images or translation history. Language packs are managed by macOS and require an internet connection to download. Explicit benchmark mode writes synthetic test text only.

## Development

`swift test` covers geometry, OCR, text grouping, caching, cancellation, permission handling and border rendering. Open `Tools/fixture.html` for manual multilingual and click-through checks. `TranslationBenchmark` provides 30 reference triples for evaluating all six translation directions; outputs require review rather than exact string comparison.

## Known limitations

- Targets horizontal text in documents, websites and apps; vertical writing and game-specific optimization are out of scope.
- Changes currently trigger OCR of the entire lens region, not just changed subregions.
- Language pack download recovery, multi-monitor behavior, offline operation and long-running stability need further runtime validation.
- Internal render timing measures GPU submission, not actual display latency.
