# Lens

A local macOS translation lens for Korean, Japanese, and English.

**Status: development preview.** The app builds and automated tests pass, but end-to-end screen translation is not yet verified. Language pack downloads and authorization of the current ad-hoc build remain unresolved. See [validation status](VALIDATION.md) before relying on the app.

## Requirements and build

- Apple Silicon, macOS 26.4+, Xcode 26.4+ (tested toolchain: Xcode 26.6).
- No third-party packages or model servers.

```sh
xcodebuild -project Lens.xcodeproj -scheme Lens -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Lens.app
swift test
```

The app is locally ad-hoc signed, not notarized for distribution. Development rebuilds may require reauthorizing Screen Recording; grant it to the final build and relaunch.

Permission checks at launch and capture restarts are non-prompting. Only the explicit start/permission button (or Start menu action) may request access, at most once per app launch. A permission toggle enabled for an older ad-hoc build does not establish access for a rebuilt executable. Paused or denied capture does not restart just because the lens moves. A stable signing identity is still needed for reliable permission continuity across app updates.

## Use

1. Grant Lens Screen Recording in System Settings → Privacy & Security → Screen & System Audio Recording. Relaunch if requested.
2. Choose **언어 준비**, then **언어 팩 준비** and accept Apple's download sheet. After all six directions are ready choose **시작**.
3. Place and resize the lens over text. Source defaults to automatic and target to Korean. Use an explicit source for ambiguous short labels.
4. **화면 재현** displays the captured scene inside the lens; **투명** shows the actual desktop underneath. **원문 가림** adjusts the text mask, not the translation's opacity.
   A thin dark-and-light border remains visible in either mode, including while paused or moving. It does not intercept mouse events.
5. **잠금** passes mouse/scroll events through the lens. The separate controls and menu-bar item remain accessible. **전문 보기** shows untruncated translations.

App menu shortcuts (when Lens is active): Command-L show, Command-R start/pause, Command-K lock, Command-comma prepare languages, Command-T full text. These are not global hotkeys.

## Architecture

ScreenCaptureKit excludes the Lens process, crops to the content rectangle, and retains read-only pixel buffers. Core Image/MetalKit present independently of OCR. A small fingerprint detects changes; the newest pending image replaces older work. Vision accurate OCR is serialized at at most 4 Hz with a 120ms stability delay. Paragraphs preserve columns. Apple Translation uses installed low-latency models, bounded batches and a 1,000-entry in-memory LRU. Region/content epochs reject obsolete results.

Language models are OS-managed. No claim is made about fixed model residency or exact model version. Translation text remains on-device; the app does not save screen images, translation history, or send content to a model server. Only settings persist. Explicit benchmark mode, if used, writes only synthetic test text.

## Validation

`swift test` exercises geometry, language detection/grouping, cache separation/eviction, batch order and cancellation. These tests do not prove real screen capture, translation quality, or GPU presentation timing. `Tools/fixture.html` supplies synthetic multilingual text, long translations and a click counter for visual and click-through checks. `TranslationBenchmark` supplies 30 authored reference triples and all 180 directional translations; outputs require review, not exact string comparison.

The full-text panel shows bounded internal latency samples. “Render submit” is capture-timestamp to GPU command submission, not actual display presentation. Translation latency includes OCR, debounce and earlier blocks. Warm/cold and cached/uncached results must be separated for performance acceptance.

See `VALIDATION.md` for the actual run evidence and remaining limits.
