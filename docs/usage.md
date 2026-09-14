# Using Lens

## Windows and controls

Open settings through **Lens → 설정…** or the menu-bar item. Settings remember their own position; closing them does not stop translation. Appearance follows macOS, with native windows, semantic system colors, and SF Symbols.

The lens toolbar offers start/pause, image capture, and recording. When click-through is enabled, the entire lens window, including the toolbar, passes mouse input through. Use the menu-bar item to disable click-through before moving or resizing.

**화면 재현** redraws the captured background inside the lens. **투명** shows the real desktop underneath. **원문 가리기** controls the mask over source text, not translation opacity. A thin border marks the lens region in either mode.

**보기 → 번역 전문** opens a selectable full-text reader with an original-text toggle and copy actions. **파일 → 닫기** closes the focused window: closing the lens pauses translation; closing settings or the reader does not. **도움말 → Lens 도움말** opens in-app help.

## Languages

Source defaults to automatic detection. Choose an explicit source for short words or names. **macOS 언어 사용** follows the first supported preferred language; if none matches, it uses English when available, then the first supported language. Explicit target choices persist between launches. Matching preserves writing systems such as Simplified and Traditional Chinese.

The catalog combines Apple's low-latency and high-fidelity translation availability. Source choices are further limited to Vision's accurate OCR languages. An OS display language, keyboard, font, or voice installation does not establish translation-pair availability.

**언어 팩 관리…** lists source availability for the selected target. Search/select a source and prepare that pair through Apple's download sheet. Lens does not automatically bulk-download languages. It prefers an installed low-latency model, then an installed high-fidelity model. Apple Intelligence availability depends on the Mac and its configuration.

Catalog and pair states refresh when Lens becomes active and after preparation. In mixed-language content, installed pairs can translate while another pair needs preparation. The Korean app interface is separate from translation-language support.

## Save an image or video

Image export saves a PNG of the captured lens region and currently displayed translations. Video export writes silent H.264 MP4, targeting up to 15 frames per second; this is an implementation setting, not a measured performance guarantee. Save actions require a captured frame.

Both exports include the captured background in transparent mode. Window chrome, the toolbar, and settings are excluded. Choose a destination in the save dialog; inspect it before sharing.

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
