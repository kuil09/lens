# UI localization

The source includes English, Korean, and Japanese UI. UI localization is separate from downloadable translation packs and the source/target selection. The UI follows the app bundle's preferred localization, including macOS per-app language settings, with English as the development fallback. Restart after changing the macOS app-language setting.

See [Development](development.md) for build/test commands and [historical verification boundaries](validation-history.md) for earlier observations.

## Implementation

- `Sources/Lens/Resources/{en,ko,ja}.lproj/Localizable.strings` contains the same UI message keys for each language, checked by tests. English source phrases are keys; translators can reorder positional `%1$@` arguments without changing code.
- `L10n` resolves one bundle locale for both AppKit and SwiftUI, including menus, accessibility, tooltips, status/errors, onboarding, settings, and displayed language names. SwiftPM uses `Bundle.module`; the packaged app uses `Bundle.main`.
- Localize fixed app copy with `L10n.text`. Pass user text, filenames, and framework error details as arguments, never as localization keys or format strings. Screen text and translation output are not UI copy.
- UI changes do not download packs. App-specific language overrides used for QA are launch arguments only; no global or persistent language preferences are changed.
- The onboarding body scrolls to accommodate longer copy without moving its footer actions. Settings forms already scroll. Compact translation-switch labels stay on one line.
- macOS owns standard dialog strings and underlying framework errors; Lens does not replace those translations. Third-party linguistic review and a complete VoiceOver journey are not claimed.

## Validation

Resource tests cover matching key sets, nonempty translations, positional format parity, locale resolution, safe interpolation, and missing lookups. A passing resource test does not establish live layout, linguistic quality, or VoiceOver usability. Inspect actual supported window sizes when changing copy.

## Adding another language

Add a complete `.lproj/Localizable.strings`, include the code in `L10n.supportedLanguages` and Xcode `knownRegions`, then extend locale/resource tests and inspect actual UI at the supported window sizes. Do not infer UI support merely from macOS translation availability. New resource keys must appear in every supported UI table.
