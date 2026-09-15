# UI localization

The current beta.3 release includes English, Korean, and Japanese UI. UI localization is separate from downloadable translation packs and the source/target selection. The UI follows the app bundle's preferred localization, including macOS per-app language settings, with English as the development fallback. Restart after changing the macOS app-language setting.

See [development](development.md) for build/test commands and [beta.2 readiness](releases/beta.2-readiness.md) for overall candidate evidence. The [planned Mac App Store distribution](distribution.md) does not imply localized store listings or completed store implementation.

## Implementation

- `Sources/Lens/Resources/{en,ko,ja}.lproj/Localizable.strings` contains the same UI message keys for each language, checked by tests. English source phrases are keys; translators can reorder positional `%1$@` arguments without changing code.
- `L10n` resolves one bundle locale for both AppKit and SwiftUI, including menus, accessibility, tooltips, status/errors, onboarding, settings, and displayed language names. SwiftPM uses `Bundle.module`; the packaged app uses `Bundle.main`.
- Localize fixed app copy with `L10n.text`. Pass user text, filenames, and framework error details as arguments, never as localization keys or format strings. Screen text and translation output are not UI copy.
- UI changes do not download packs. App-specific language overrides used for QA are launch arguments only; no global or persistent language preferences are changed.
- The onboarding body scrolls to accommodate longer copy without moving its footer actions. Settings forms already scroll. Compact translation-switch labels stay on one line.
- macOS owns standard dialog strings and underlying framework errors; Lens does not replace those translations. Third-party linguistic review and a complete VoiceOver journey are not claimed.

## Validation (2026-09-15)

These are recorded localization-stage results, not a new run during documentation housekeeping or whole-runtime acceptance. Earlier candidate-stage test counts are retained in the readiness record; final checks must identify the source revision tested. The DMG observation below predates the current housekeeping changes; no fresh candidate DMG is claimed.

- Four localization tests cover complete key sets, nonempty translations, positional format parity, regional preference resolution and English fallback, real bundle lookups, safe interpolation of multilingual filenames containing percent characters, missing resource calls, and hard-coded Korean outside the synthetic benchmark corpus.
- Full ordinary suite: 60 Swift Testing cases, including two opt-in installed-model tests skipped; 3 XCTest cases passed. Total: 61 passed, 2 skipped.
- Release build includes all three `.lproj` resources.
- Actual English and Japanese launches verified native menu/onboarding/settings copy and source/target language names. Onboarding screenshots showed readable wrapping and reachable footer actions. The source/target values remained English → Korean while their display names changed with the UI locale.
- Final normal launch (without test arguments) followed the existing ko-KR macOS preference: Korean onboarding/menus and source/target names 영어 → 한국어 were observed. No persistent app-language override was written. The local DMG was regenerated and its checksum verified; no GitHub publication or notarization occurred.
- Screen-recording authorization and real screen translation remain the independent outstanding runtime boundary; localization verification did not request or reset permission.

## Adding another language

Add a complete `.lproj/Localizable.strings`, include the code in `L10n.supportedLanguages` and Xcode `knownRegions`, then extend locale/resource tests and inspect actual UI at the supported window sizes. Do not infer UI support merely from macOS translation availability. New resource keys must appear in every supported UI table.
