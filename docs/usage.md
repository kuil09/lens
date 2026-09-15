# Using Lens

## Interface language

The current source UI includes English, Korean, and Japanese. It follows macOS preferred/app-specific language settings; unsupported preferences fall back to English. To override Lens only, use **System Settings → General → Language & Region → Applications**, then restart Lens. Menus, settings, onboarding, tooltips, accessibility labels, app-generated status/errors, and language names use the same resolved UI locale. System-generated dialogs and underlying framework error details remain controlled by macOS.

UI localization is separate from downloaded translation packs. Choosing a translation target does not change the interface language, and changing interface language does not download a model. Examples below use the original Korean control labels; equivalent localized controls are present in English and Japanese.

## First launch

The current source candidate opens **Lens 시작하기** with three steps: screen access, installed translation languages, and the shared image/video save folder. No permission request or model download runs automatically. **나중에** or closing the guide leaves it incomplete so it appears next launch. Completion is saved only after permission and a usable installed route are confirmed. Reopen the guide through **도움말 → 시작 안내…** at any time. Finishing opens the lens with translation off; enable its switch when ready.

Incomplete steps are remembered without storing a permission grant. **나중에** shows a normal paused window with **설정 이어가기** and **Lens 종료**. Returning from System Settings restores normal guidance and rechecks macOS permission; it never starts capture or recording. After onboarding is complete, a new launch shows readiness with an explicit start action. Language and save-folder choices remain unchanged by this handoff.

## Windows and controls

Open settings through **Lens → 설정…** or the menu-bar item. Settings remember their own position; closing them does not stop translation. Appearance follows macOS, with native windows, semantic system colors, and SF Symbols.

The lens opens with translation off. Its language bar offers **출발어 ↔ 도착어** and a **번역** switch. The compact Liquid Glass toolbar offers image capture, recording, the reader, and independent settings. Recording turns its toolbar control red and changes it to Stop. When click-through is enabled, the entire lens window, including the toolbar, passes mouse input through. Use the menu-bar item to disable click-through before moving or resizing.

While translation is off, a frosted Liquid Glass background covers the lens. Turning translation on reveals the real desktop underneath and places translations at the original text positions. Pausing or capture failure restores the frosted background. Reduce Transparency uses a solid background instead. **원문 가리기** controls the mask over source text, not translation opacity. A thin border always marks the lens region. The old captured-background display preference is no longer used; exports still include the captured image.

**보기 → 번역 전문** opens a selectable full-text reader with an original-text toggle and copy actions. **파일 → 닫기** closes the focused window: closing the lens pauses translation; closing settings or the reader does not. **도움말 → Lens 도움말** opens in-app help.

Before requesting screen access, and when System Settings becomes active, Lens pauses capture/recording and hides its overlay so system controls can receive input. It does not automatically reappear when focus changes. After finishing in System Settings, use **렌즈 보기** or **번역 시작** explicitly. No macOS authentication or secure-input protection is disabled.

## Languages

Source defaults to automatic detection. Choose an explicit source for short words or names. **macOS 언어 사용** follows the first installed preferred language; if none matches, it uses installed English when available, then the first installed target. Explicit choices persist while still usable. Removed models reset unavailable selections to the installed default / automatic source. Matching preserves writing systems such as Simplified and Traditional Chinese.

Use **↔** to exchange an explicit source and target. Automatic detection cannot be swapped, and the new source must support OCR. Swapping clears stale translations and restarts once when translation is active. Language preparation still happens through settings; changing a picker does not download models automatically.

The catalog uses Apple's **lowLatency** availability for individually downloaded translation packs. Apple Intelligence's shared **highFidelity** model can report many languages as installed without individual language downloads, so it is not used to populate pickers or silently broaden translation. Targets must have at least one installed route from a Vision-readable source; source choices must have an installed route to the selected target. With no usable pair, translation stays disabled and language preparation remains accessible. An OS display language, keyboard, font, or voice installation does not establish translation-pair availability.

**언어 팩 관리…** is the separate add-language screen: it intentionally includes supported but uninstalled languages. Its preparation target does not change the lens target. Search/select a source and prepare that pair through Apple's download sheet. Lens does not automatically bulk-download languages. Both preparation and live translation use the same low-latency pack policy.

Catalog and pair states refresh when Lens becomes active and after preparation. In mixed-language content, installed pairs can translate while another pair needs preparation. Interface-language support is separate from translation-language support.

## Save an image or video

Image export saves a PNG of the captured lens region and currently displayed translations. Video export writes silent H.264 MP4, targeting up to 15 frames per second; this is an implementation setting, not a measured performance guarantee. Save actions require a captured frame.

Choose a shared image/video folder once in onboarding or **설정 → 캡처 → 저장 폴더 → 폴더 변경…**. The initial default is `~/Pictures/Lens`, created when completing onboarding, on the first save, or when opening it in Finder. Lens remembers the chosen folder across launches. Capture and record buttons no longer show a path or filename dialog: images save immediately and recording starts immediately. **Finder에서 열기** opens the folder; **최근 저장** reveals the most recently saved file from this session.

Names include the media type and local date/time, for example `Lens-Image-2026-09-15_14-30-25-123.png` and `Lens-Video-2026-09-15_14-30-25-123.mp4`. Collisions receive a numeric suffix; existing files are never overwritten. Changing folders during a recording affects only subsequent captures and recordings. A disconnected, deleted, or unwritable selected folder causes an error rather than silently saving elsewhere. Reconnect it or choose a folder again in settings. Files accumulate until you remove them yourself.

Both exports include the captured background in transparent mode. Window chrome, the toolbar, and settings are excluded. Inspect exports before sharing.

Use the same recording action to stop and save. Moving or resizing the lens, changing translation languages, pausing, sleeping, or quitting ends the recording. Closing settings does not. The menu-bar item shows recording and saving state. Wait for finalization before opening or moving the file.

Video dimensions follow the initial captured image, rounded down to even pixel dimensions. Failed finalization can leave a recovery file beside the selected destination; force-quitting or power loss can leave it unplayable. See [privacy](privacy.md) and [troubleshooting](troubleshooting.md).

## Shortcuts

These shortcuts work when Lens is active; they are not global hotkeys.

| Action | Shortcut |
| --- | --- |
| Show lens | Command-L |
| Start / pause translation | Command-R |
| Toggle click-through | Command-K |
| Settings | Command-comma |
| Full-text reader | Command-T |
| Save image | Command-Shift-S |
| Start / stop recording | Command-Shift-R |
| Close focused window | Command-W |
