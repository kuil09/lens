# Troubleshooting

Use synthetic text, such as the bundled `Tools/fixture.html`, while investigating. Never attach private screen content to a report.

## Permission is enabled, but capture does not start

1. Check Lens in System Settings → Privacy & Security → Screen & System Audio Recording.
2. Return to Lens from the Dock and choose **권한 다시 확인**. Quit and reopen only if macOS asks you to; a missing grant alone is not evidence that relaunch is required.
3. Start translation explicitly once access and languages are ready. Only **시스템 설정 열기…** may request permission, at most once per launch. Reopening, rechecking, and launching do not.
4. If you rebuilt or replaced the app, check its Screen Recording entry again. Ad-hoc signing, a different build location, or a changed bundle identity can affect permission continuity.

Keep the canonical development build location and existing identity while diagnosing. Do not reset all macOS privacy permissions as a first step. A visible permission switch alone does not prove capture or translation works.

Ad-hoc signatures identify one specific build. Rebuilding can therefore invalidate an earlier grant even at the same path. [Stable local signing](development.md#stable-local-signing) lets successive builds satisfy the same signer/app requirement. The first transition from ad-hoc signing may need another grant and relaunch; future permission behavior still needs verification on the actual signed app. Do not alternate signed and ad-hoc builds at the installed path.

## Keyboard input stalls in a system permission dialog

Close or hide the lens before entering an administrator password; never paste a password into Lens or an issue report. Current source relinquishes the overlay before requesting Screen Recording access or opening System Settings. Activating System Settings directly also pauses capture/recording and hides the lens. It stays hidden until an explicit **렌즈 보기** or **번역 시작** action. The panel uses ordinary app activation rather than a nonactivating panel's keyboard focus behavior.

This removes an overlay/focus interference path; it does not establish that Secure Input caused a reported stall. Lens does not inspect or disable Secure Input, install keyboard event taps, or bypass authentication. A real authentication check must be performed by the user after installing the updated build.

It is intentional for Lens to remain running with its overlay hidden during this handoff. Returning from the Dock, **보기 → 렌즈 보기** (Command-L), or the menu-bar item's **렌즈 보기** opens a normal guide, not the floating overlay. The guide rechecks OS permission and offers setup or an explicit translation-start action. **나중에** leaves a paused guide with resume and quit actions. Intentionally closing all windows is allowed; reopening restores guidance. Incomplete onboarding progress survives normal quit. Capture and recording never resume just because a window or app was reopened.

Before Lens opens Settings it awaits pending capture shutdown and video finalization. Recording errors during handoff are retained in the guide rather than shown as focus-stealing alerts. A direct user switch to Settings hides the overlay immediately while shutdown finishes in the background. If macOS requests a restart, use its restart action or quit Lens normally after saving; Lens has no automatic restart loop.

## System Settings shows a generic Lens icon

App artwork, the running app icon, Launch Services lookup, and a cached System Settings row are different verification boundaries. Confirm the selected app path and its built `CFBundleIconFile`/`CFBundleIconName` entries, and verify that `Contents/Resources/AppIcon.icns` contains the intended icon. Do not clear Screen Recording grants to repair artwork.

On 2026-09-15, the canonical development bundle contained the correct icon while `NSWorkspace.icon(forFile:)` returned a generic icon. Re-registering only that exact app using the system `lsregister -f` refreshed the workspace lookup to the blue translation icon. The System Settings row still required a native visual recheck; reopening System Settings may be necessary. No global Launch Services rebuild, icon-cache deletion, or TCC reset was used.

## A language is missing or needs preparation

Normal pickers intentionally show only installed translation routes, not every language supported by macOS. In **언어 팩 관리…**, supported but uninstalled models remain visible so you can add them. Its selection does not change the active lens language. If no pair is installed, translation and onboarding completion remain disabled; you can still close the guide with **나중에**.

Open **언어 팩 관리…** for the selected target and inspect the desired source pair. A supported pair can still require installation. Accept Apple's download sheet with internet access, then recheck after preparation or after bringing Lens to the foreground.

Source choices require both translation support and accurate Vision OCR support; targets do not require OCR. macOS display-language support does not guarantee either. If a download fails, record the sanitized error and retry the selected pair once the connection is restored. Download recovery and offline operation remain manual acceptance items.

## Text is absent, wrong, or stale

Confirm a frame has arrived and translation is running. Keep the lens within one display, pause and restart, and try larger horizontal text with an explicit source language. Use different source and target languages.

Short labels, vertical writing, rapidly changing content, and text outside OCR support may not work well. Use the full-text reader when translations do not fit. Reproduce a suspected stale-result issue by moving, resizing, or changing languages over synthetic content and describe the exact sequence.

Multiple-display behavior is not formally accepted. If a display disconnects or capture reports it unavailable, move the lens onto an available display and restart.

## Mouse events go through the toolbar

Click-through affects the whole lens window. Turn off **클릭과 스크롤 통과** using the menu-bar item, or Command-K when Lens is active.

## An image or video cannot be saved

Wait for a captured frame; save controls are disabled before one exists. Check that the selected destination is writable and has available space. Recording ends when the lens moves/resizes, languages change, translation pauses, the Mac sleeps, or Lens quits.

Exports now go directly to **설정 → 캡처 → 저장 폴더**, initially `~/Pictures/Lens`. No filename or path dialog is expected. If that folder was deleted, disconnected, or lost permission, reconnect it or choose it again with **폴더 변경…**. Lens does not silently fall back to another location. **최근 저장 → Finder에서 보기** reveals the last completed export from this session.

Wait for the saving indicator to finish. If an error names a recovery file, keep it until you have checked whether it is playable and recovered anything needed. Do not assume it is complete after a crash or power loss. Exported transparent-mode content includes the background by design.

## A downloaded app is blocked

Development builds are not a notarized public distribution. Do not disable Gatekeeper or broadly remove quarantine as a workaround. Use the documented local development workflow. Future distribution is planned as a paid Mac App Store one-time purchase, with no subscriptions; implementation and submission are deferred. The earlier external Developer ID notarization workflow remains withdrawn. See [distribution status](distribution.md) and the [release checklist](releasing.md).

## Report a problem

Include macOS and app version/build, Mac architecture, source/target languages, permission state, expected and actual behavior, and a minimal reproduction with invented text. State whether the build is local or a packaged candidate. Use the [bug template](../.github/ISSUE_TEMPLATE/bug_report.md); for vulnerabilities, follow [private reporting guidance](../SECURITY.md).
