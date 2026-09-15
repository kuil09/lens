# Lens

<img src="Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="96" height="96" alt="Lens: A becomes 가 through a glass lens">

Translate text where you see it on your Mac. Place a resizable lens over a document, website, or app to display translations near the original text, using Vision OCR and Apple Translation on-device.

**Development preview: [v0.1.0-beta.3](https://github.com/kuil09/lens/releases/tag/v0.1.0-beta.3), app 0.1.0 (build 9).** Download the DMG and its SHA-256 sidecar from the release. The app is **Developer ID signed but not notarized**. It is intended for developers and testers; Gatekeeper may prevent opening a downloaded copy. Building from source is an alternative. Do not disable macOS security protections. Formal whole-runtime acceptance, translation quality, and end-to-end performance remain incomplete.

**Current source and local package: 0.1.0-beta.4 (build 10), not published as a GitHub release.** Capture confirmation, a toolbar save-folder shortcut, and window-return/minimization refinements are described in the [capture and window UX review](docs/ux-capture-and-windows.md). See [beta.4 package notes](docs/releases/v0.1.0-beta.4.md) for artifact verification. These changes are **not** in the published beta.3/build 9 DMG.

The published beta.3 release retains the development identifier `dev.local.lens` and includes [region-adaptive backoff](docs/adaptive-backoff.md) and [context/visibility separation with an interactive click-through header](docs/context-and-input.md). Native click-through input delivery still requires manual acceptance. Optional [machine-local signing](docs/development.md#stable-local-signing) preserves code identity across rebuilds; fresh checkouts default to ad-hoc signing. The planned commercial distribution is a **paid Mac App Store one-time purchase, with no subscriptions**. Store implementation, signing, and submission are deferred; see [distribution direction and status](docs/distribution.md).

## Get started

Requires Apple Silicon, macOS 26.4 or later, and Xcode 26.4 or later to build from source. Lens has no third-party package dependencies or model server requirement. Follow the [development guide](docs/development.md) for the local build.

Open the DMG and drag Lens to Applications. Control labels below use Korean; equivalent English and Japanese labels are available. A downloaded app may still be blocked by Gatekeeper because this preview is not notarized.

1. Follow **Lens 시작하기** on first launch: check screen access, choose installed translation languages, and confirm the save folder. Reopen it from **도움말 → 시작 안내…**.
2. Allow Lens in **System Settings → Privacy & Security → Screen & System Audio Recording**. Quit and reopen Lens if macOS requests it. The lens hides while you use System Settings.
3. Source/target menus show installed translation models only. To add a language, open **언어 팩 관리…**. Downloads require internet access and explicit confirmation.
4. Place the lens over text and enable the **번역** switch. Off shows frosted Liquid Glass; on reveals the desktop with translations over the original text.
5. Enable **클릭과 스크롤 통과** to interact with the app underneath; the header cursor button and menu-bar item remain available to turn it off. **Lens → 설정…** (Command-comma) opens independent translation, appearance, and capture settings.

The current source UI supports English, Korean, and Japanese, following macOS app-language preferences with English as the fallback. Restart Lens after changing its language in System Settings → General → Language & Region → Applications. UI language is independent of installed translation packs and source/target selection. Translation choices require Apple's installed-pair status and source OCR support; this does **not** mean every macOS language is supported. **Use macOS Language** selects an installed translation target from your preferences.

Images and silent videos are saved only when requested to the selected shared folder, without a filename prompt. Exports include the captured background while the live lens is transparent. Read the [privacy guide](docs/privacy.md) before exporting or sharing.

## Guides and community

- [Using Lens](docs/usage.md): display modes, language packs, shortcuts, image and video export.
- [Troubleshooting](docs/troubleshooting.md): permissions, missing languages, capture and export problems.
- [Development](docs/development.md) and [contributing](CONTRIBUTING.md).
- [UI localization](docs/localization.md): supported interface languages, contributor workflow, and recorded checks.
- [Distribution](docs/distribution.md): planned purchase model, current artifact status, and withdrawn notarization history.
- [Release checklist and manual acceptance](docs/releasing.md), with [current evidence and remaining limitations](docs/context-and-input.md).
- [Beta.3 release notes](docs/releases/v0.1.0-beta.3.md). Earlier release notes remain in `docs/releases/` as historical evidence; their download assets and tags have been retired.
- [Changelog](CHANGELOG.md) and [security reporting](SECURITY.md).

Horizontal text is the current focus; vertical writing and game-specific optimization are out of scope. Offline use, language-download recovery, multiple displays, and sustained operation still need formal runtime acceptance.

Source repository: [kuil09/lens](https://github.com/kuil09/lens). Licensed under the [MIT License](LICENSE), copyright **2026 kuil09**. Public distribution still requires the release checklist.
