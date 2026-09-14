# Lens

<img src="Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="96" height="96" alt="Lens: A becomes 가 through a glass lens">

Translate text where you see it on your Mac. Place a resizable lens over a document, website, or app to display translations near the original text, using Vision OCR and Apple Translation on-device.

**Development preview: [v0.1.0-beta.1](https://github.com/kuil09/lens/releases/tag/v0.1.0-beta.1), app 0.1.0 (build 2).** The Release-configuration ZIP is ad-hoc signed, **not Developer ID signed or notarized**. It is intended for developers and testers; Gatekeeper may prevent opening a downloaded copy. Building from source is an alternative. Do not disable macOS security protections. Formal whole-runtime acceptance, translation quality, and end-to-end performance remain incomplete.

## Get started

Requires Apple Silicon, macOS 26.4 or later, and Xcode 26.4 or later to build from source. Lens has no third-party package dependencies or model server requirement. Follow the [development guide](docs/development.md) for the local build.

1. Open **Lens → 설정…** (Command-comma). Settings have translation (**번역**), appearance (**표시**), and capture (**캡처**) panes.
2. Allow Lens in **System Settings → Privacy & Security → Screen & System Audio Recording**. Quit and reopen Lens if macOS requests it.
3. Choose a source and target language, then use **언어 팩 관리…** to prepare the selected pair. Initial language downloads need internet access.
4. Place the lens over text and select **번역 시작**. Choose an explicit source language when short text is detected incorrectly.
5. Use **화면 재현** to reproduce the captured background, or **투명** to see the desktop beneath. Enable **클릭과 스크롤 통과** to interact with the app underneath; the menu-bar item remains available to turn it off.

The interface is currently Korean. Translation choices come from Apple's runtime language availability; source choices also require Vision OCR support. This does **not** mean every macOS interface language is supported. **macOS 언어 사용** selects a supported target from your preferred languages, independently of UI localization.

Images and silent videos are saved only when requested, and include the captured background even in transparent mode. Read the [privacy guide](docs/privacy.md) before exporting or sharing.

## Guides and community

- [Using Lens](docs/usage.md): display modes, language packs, shortcuts, image and video export.
- [Troubleshooting](docs/troubleshooting.md): permissions, missing languages, capture and export problems.
- [Development](docs/development.md) and [contributing](CONTRIBUTING.md).
- [Release checklist and manual acceptance](docs/releasing.md).
- [Changelog](CHANGELOG.md) and [security reporting](SECURITY.md).

Horizontal text is the current focus; vertical writing and game-specific optimization are out of scope. Offline use, language-download recovery, multiple displays, and sustained operation still need formal runtime acceptance.

Source repository: [kuil09/lens](https://github.com/kuil09/lens). Licensed under the [MIT License](LICENSE), copyright **2026 kuil09**. Public distribution still requires the release checklist.
