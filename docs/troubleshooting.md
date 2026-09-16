# Troubleshooting

Use synthetic text, such as [the bundled fixture](../Tools/fixture.html), while investigating. Never attach private screen content or credentials to a report. Compare the installed app's About version/build with its release notes; source documentation does not update an installed copy.

## Permission is enabled, but capture does not start

1. Check Lens in **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Return through the Dock or **렌즈 보기**. In the permission guide, choose **권한 다시 확인**; Settings also has an independent recheck. Quit and reopen if macOS requests it. A visible enabled switch alone does not prove capture works.
3. Start translation explicitly after permission and language readiness are confirmed. Only the explicit screen-permission Settings action may request access, at most once per launch; launching/rechecking does not.
4. If rebuilt/replaced, verify the exact app path and signing identity. A different bundle identity or ad-hoc signature can affect consent continuity.

Keep the existing app identity and stable development path. [Stable local signing](development.md#stable-local-signing) avoids changing the code requirement with every build, but does not bypass consent or guarantee macOS will never ask again. Do not alternate ad-hoc/signed builds at the installed path or reset privacy permissions as a troubleshooting shortcut.

## Lens is hidden or a return guide appears

Only the screen-permission Settings action initiated inside Lens intentionally stops capture, finalizes recording, and hides the body, toolbar, resize panels, and popover. Return via the Dock, **보기 → 렌즈 보기**, or the menu-bar item. The normal guide rechecks permission and offers an explicit start; **나중에** keeps a paused guide with resume/quit actions. Incomplete onboarding resumes its saved step next launch. Ordinary System Settings visits and language downloads do not trigger this flow: the visible lens, translation, recording and pending start stay unchanged.

This is distinct from a completed user's normal relaunch: with permission available, that opens the paused lens without another onboarding guide. Returning to an already running, visible lens does not stop translation. Closing/minimizing the lens does pause it; restoring does not start capture automatically.

If administrator-password input is blocked, hide or close Lens before entering the password. Lens yields input before explicitly opening its screen-permission settings, but does not automatically hide for unrelated System Settings use or detect arbitrary authentication dialogs. Do not paste passwords into Lens or reports. This safety behavior is not evidence that Secure Input caused an earlier stall; real authentication remains a separate verification boundary. Lens does not inspect/disable Secure Input, intercept global keystrokes, or bypass authentication.

## System Settings shows a generic Lens icon

Bundle artwork, the running app icon, Launch Services lookup, and a cached Settings row are different boundaries. For a source build, inspect `CFBundleIconFile`/`CFBundleIconName` and `Contents/Resources/AppIcon.icns`; check the exact installed path before diagnosing a stale row. Reopen System Settings if necessary. Do not reset Screen Recording grants or globally delete caches to repair an icon. A correct bundle icon does not establish that a cached Settings row has repainted.

## A language is missing or checking

Pickers intentionally show installed translation routes, with OCR support also required for sources. Open **시스템 언어 다운로드…** from Help/Settings, then open System Settings → General → Language & Region and navigate to Translation Languages. The button opens the parent pane; it does not itself download anything. Return to the guide, choose **다시 확인**, and close it with **완료** to refresh Lens.

Do not look for the old Lens source-list/download sheet. Display/keyboard/voice languages and Apple Intelligence's shared-model support are not proof of individual translation packs. If the system pane differs or is unavailable, include the macOS version in a report rather than changing unrelated language settings.

Checking is not missing: an explicit start can wait for a check without opening download guidance. Ordinary Finder activation does not refresh the entire catalog. A failed readiness check can be retried with Start Translation; it must not be interpreted as proof of missing models. Keep using installed routes while downloading others. Offline behavior and interrupted-download recovery require actual runtime verification, not just a ready catalog.

## Text is absent, wrong, stale, or truncated

Confirm translation is running and a frame has arrived; try larger horizontal synthetic text and different source/target languages. An explicit source filters recognized paragraphs: it does not force ambiguous names, short words, numbers, mixed-language text, or other languages into that selection. Auto Detect can help with a multilingual page, but uncertain text may still remain original.

Changing text temporarily hides the affected overlay and source mask while preserving unrelated valid translations. The **번역 전문** reader deliberately stays fixed; choose **새 번역 반영** for updates and heed **이전 번역 / 이전 화면의 번역** labels. To read an overlay's truncated translation, turn click-through off and click it, or use Command-Shift-T. This does not recover source text the underlying app never displayed.

For stale results, report a minimal move/resize/language-change sequence. Multiple-display acceptance remains incomplete; after a display disconnect, move the lens onto an available display and restart translation.

## Click-through and resize controls

Only the lens body passes clicks, drags, and scrolling through. Toolbar actions must remain usable, including unlocking and recording stop. Resize edges work except during recording, when movement, resizing and zoom are intentionally locked. Use the toolbar cursor button, menu-bar item, or Command-K while Lens is active to unlock body input. If the header also passes input through or a resize panel is left behind, that is not intended behavior: record the build and move/minimize/restore sequence. Panel tests alone do not establish real cross-app input delivery.

## An image or video cannot be saved

Wait for a captured frame; save/start-recording controls require one. **저장 폴더 열기** is independent of that requirement and opens the currently configured folder, not the last saved file's parent. Check **설정 → 캡처 → 저장 폴더**, available space, and write access. Reconnect or reselect a missing custom folder; Lens does not silently fall back elsewhere.

No filename dialog is expected. Successful PNG writes briefly show a camera checkmark; failures retain error guidance instead. A red outline means recording is active; stop recording before moving or resizing Lens. Language change, pause, minimize, sleep, lens close, quit, or an OS-driven display relocation can end recording. Wait for video finalization. Keep any named recovery file until you have recovered what is playable; a crash/power loss can leave it incomplete. Transparent-mode exports include the background by design, but not the red recording outline. See [saving details](usage.md#save-an-image-or-video).

## A downloaded app is blocked

Check the exact asset's [release notes](https://github.com/kuil09/lens/releases) and checksum: development archives marked **DEVELOPMENT-NOT-NOTARIZED** are different from a verified notarized release. A Developer ID signature alone is not Apple notarization. App Store submission is separate and is not required for the GitHub DMG workflow.

Do not disable Gatekeeper, strip quarantine, or reset permissions to pass a check. If the documented notarized asset is blocked, record its filename/checksum, macOS version, and sanitized message. Use the [source-build guide](development.md) if appropriate; release maintainers should follow the [artifact checks](releasing.md#release-gates-and-recovery).

## Report a problem

Include macOS/app version and build, architecture, source/target languages, permission state, local-vs-downloaded origin, expected/actual behavior, and invented-text reproduction. Use the [bug template](../.github/ISSUE_TEMPLATE/bug_report.md); vulnerabilities follow [private reporting guidance](../SECURITY.md).
