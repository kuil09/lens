# Using Lens

This guide describes the current source UI. Check your installed app's version in **Lens → About Lens** and compare it with the [release record](https://github.com/kuil09/lens/releases). Examples below use Korean labels; equivalent English and Japanese controls are available.

## First launch and returning to Lens

**Lens 시작하기** has three steps: screen access, installed translation languages, and the shared save folder. It never requests permission or downloads models automatically. **나중에** or closing an unfinished guide preserves the saved step and shows a paused guide with resume/quit actions. Completion requires screen access, usable installed languages, and a valid save folder. Reopen setup through **도움말 → 시작 안내…**.

After completion, a normal relaunch with permission available opens the **paused lens**, not another setup/readiness window. Turn translation on explicitly. If all windows were closed, returning to Lens restores the paused lens; simply returning to an already visible, running lens does not stop translation.

Ordinary System Settings visits, including language downloads, leave the lens visible at its existing window level and do not pause translation, end recording, cancel a pending start or create a return guide. Lens does not treat application activation as a screen-permission request.

Only Lens's explicit screen-permission Settings button starts a handoff: Lens stops capture and ends recording, hides its body, toolbar, resize edges, and popover, then shows a normal permission/return guide when you return. It rechecks OS permission rather than trusting a saved grant. **나중에** keeps a paused guide; **번역 시작** is an explicit start action. Quit/relaunch only when needed, such as when macOS requests it. Window restoration never automatically resumes capture or recording. Actual permission loss, sleep or lens closure remain separate reasons to stop. See [permission troubleshooting](troubleshooting.md#permission-is-enabled-but-capture-does-not-start).

## Windows and input

The lens has **출발어 ↔ 도착어**, a **번역** switch, and a toolbar for capture, the save folder, recording, click-through, the reader, and settings. Settings are independent: **Lens → 설정…** or Command-comma. Closing settings does not stop translation.

In **설정 → 번역 → 번역 갱신 반응성**, choose **차분하게 / 균형 (기본값) / 빠르게**. Balanced preserves the previous inspection pacing. Faster checks changing regions more often and may consume more CPU/battery; it does not guarantee faster translation completion. Stable regions can recover early at every setting. Changing this setting does not restart capture or recording.

New valid overlay text briefly fades in (140 ms); changed-source translations and their covers disappear immediately. Unchanged paragraphs do not animate again. Rapid repeats at the same location, Reduce Motion, and a partially transparent source cover skip the fade. PNG/MP4 always use completed valid output, never intermediate opacity. The reader and full-text popover retain their fixed reading policy. These source changes are not included in the previously published DMG until a separate release.

**클릭과 스크롤 통과** applies only to the body. Click, drag, and scroll there to interact with the underlying app. The toolbar remains interactive, including the click-through unlock and recording-stop buttons. When not recording, drag the rounded corner markers or edges to resize; the title area moves the lens. During recording these geometry controls are locked. The menu-bar item also provides recovery controls. Narrow windows may put lower-priority toolbar actions in overflow.

With translation off, frosted Liquid Glass covers the body; active translation reveals the desktop with source-position translations. Reduce Transparency substitutes an opaque background for the paused glass. **원문 가리기** controls the source-cover mask, not translation opacity. Changed text may temporarily show its original while a current translation is prepared; unrelated valid translations are retained.

**파일 → 닫기** closes the focused window. Closing the lens pauses translation and ends recording; closing settings or the reader does not. Minimizing pauses translation; restore and start again when ready. Zoom enlarges/restores the lens within the current display's visible area; it is not a dedicated full-screen reading mode. Movement/resizing interrupts translation, then restarts it if it was running; these adjustments are unavailable during recording. Multiple displays, Spaces, and full-screen app interactions still require the candidate-specific [manual acceptance checks](releasing.md#manual-acceptance-matrix).

## Languages

Source defaults to automatic detection. An explicit source is a **filter**, not a command to translate everything as that language: only paragraphs identified as the selected language are sent for translation. Ambiguous short words, numbers alone, conflicting mixed-language text, and other-language paragraphs can remain original. Auto Detect groups recognized languages and excludes text already in the target language.

Normal pickers show installed translation routes, not all macOS languages. Sources additionally require Vision OCR support. The catalog uses individually installed low-latency translation packs, not the Apple Intelligence shared-model language list. A display language, keyboard, font, or voice does not establish translation availability.

**macOS 언어 사용** chooses an installed target from preferred languages, then installed English if available, then another installed target. Explicit selections persist while usable. Confirmed model removal can reset an unavailable selection; a check still in progress does not erase the last completed selection. **↔** exchanges explicit source and target only when the reverse source supports OCR; Auto Detect cannot be swapped. Language changes invalidate old results and end recording.

Use **도움말 → 시스템 언어 다운로드…** or the corresponding Settings action to add languages. This is a guide, not the former in-app source-list/download sheet. **시스템 설정 열기…** opens Language & Region; navigate to **번역 언어 / Translation Languages** there. The deep link does not select or download a model for you, and pane names/availability may vary with macOS. The guide's target is only for checking readiness; it does not change the lens selection. Return, select **다시 확인**, then **완료** to close the guide and refresh the lens catalog.

Lens checks languages at startup, on return from an explicit screen-permission handoff, after the download guide closes, and on explicit recheck; language-pair changes check the selected pair. Ordinary app activation, including System Settings, does not refresh the whole catalog. A start request during a check waits once for readiness; it does not treat checking as missing. Stop, closing a window, changing languages, or requesting screen permission through Lens cancels that pending start. Missing languages open the system guide; a failed check is retryable, not proof of an uninstalled model.

## Read a full translation

**보기 → 번역 전문** opens a selectable snapshot of completed translations. Focus changes and incoming frames do not replace what you are reading. Use **새 번역 반영** to apply the latest results; **전체 복사** copies the displayed snapshot. The reader shows its applied time and can include originals. Pending paragraphs may retain **이전 번역**; page/region/language changes label the retained snapshot **이전 화면의 번역** until you apply updates. Closing and reopening the reader takes a new snapshot.

For a truncated overlay translation, turn click-through **off** and click that paragraph to open a scrollable, selectable popover. Hover alone does not open it. Keyboard users can use **보기 → 말줄임된 번역 보기** (Command-Shift-T). Only currently valid, actually truncated items are eligible. The popover stays fixed while open; Escape/outside click, source changes, pause, move/resize, language change, click-through on, app deactivation/hiding, or system handoff closes it. Lens cannot recover text already missing from a truncated source app.

## Save an image or video

Choose the shared folder in onboarding or **설정 → 캡처 → 저장 폴더 → 폴더 변경…**. The default is `~/Pictures/Lens`, created when needed. Camera/record actions use it without a per-file name/path prompt. The toolbar's **저장 폴더 열기** opens the currently configured folder, even when paused, locked, disconnected from capture, or recording; **최근 저장** instead reveals this session's last completed file.

PNG success changes the camera to a checkmark with **이미지 저장 완료** for about 1.5 seconds. Another capture is still possible; starting it clears the old success state. Failure never produces a success checkmark.

Video uses silent H.264 MP4 at a target of up to 15 fps, not a measured guarantee. Use the red Stop control to finish saving. Saving needs a captured frame. While recording, a continuous red outline surrounds the lens, and movement, resizing, and zoom are locked. Stop recording to adjust the lens again; the toolbar remains usable, including with body click-through enabled. The red outline is not included in saved images or videos. Language changes, pause, minimize, sleep, closing the lens, and quit end recording; closing settings does not. An OS-driven display relocation can still safely end recording. Wait for finalization before opening or moving the file.

Names include media type and date/time, with numeric collision suffixes; existing files are not overwritten. A folder change during recording affects subsequent recordings/captures, not the file already being recorded. Deleted, disconnected, or unwritable custom folders produce an error rather than silently switching destinations. Files accumulate until you remove them.

PNG includes the captured background and currently valid completed translations. Video separately composes translations against the captured source: it can reuse translations as unchanged text moves horizontally or vertically, and briefly waits for newly recognized text. This does not slow the live lens or the video's original timeline. No separate capture target is selected; other windows covering the lens region remain part of the recording.

Best results are on plain document backgrounds. Fast motion, clipping, changing text, complex backgrounds, or late translations can show the original instead; Lens does not hold an old translation over uncertain content. The recording buffer is bounded to 0.8 seconds, 12 source-frame slots, and 96 MiB; memory pressure can shorten the wait. A completed translation can still help later matching frames after the earlier frame has been written. Normal Stop allows the remaining bounded wait before saving; security handoff does not wait for translations.

The toolbar, success indicator, resize handles, red recording outline, popover, and live fade transitions are excluded from image/video composition. Video dimensions follow the initial image, rounded down to even pixels. Failed finalization may leave a recovery file; force quit/power loss can leave it unplayable. See [Privacy](privacy.md) before sharing.

## Interface language and shortcuts

The interface follows macOS preferred/app-specific language settings, with English fallback. Change Lens's UI language under **System Settings → General → Language & Region → Applications**, then restart. UI language is independent of source/target selection and model downloads; system dialogs remain controlled by macOS.

These shortcuts apply when Lens is active, not as global hotkeys.

| Action | Shortcut |
| --- | --- |
| Show lens | Command-L |
| Start / pause translation | Command-R |
| Toggle body click-through | Command-K |
| Settings | Command-comma |
| Full-text reader | Command-T |
| Read truncated translation | Command-Shift-T |
| Save image | Command-Shift-S |
| Start / stop recording | Command-Shift-R |
| Close focused window | Command-W |
