# Troubleshooting

Use synthetic text, such as the bundled `Tools/fixture.html`, while investigating. Never attach private screen content to a report.

## Permission is enabled, but capture does not start

1. Check Lens in System Settings → Privacy & Security → Screen & System Audio Recording.
2. Quit Lens completely and reopen the same app build that you authorized.
3. Start translation explicitly, or use **다시 확인** in settings. Lens requests permission at most once per launch.
4. If you rebuilt or replaced the app, check its Screen Recording entry again. Ad-hoc signing, a different build location, or a changed bundle identity can affect permission continuity.

Keep the canonical development build location and existing identity while diagnosing. Do not reset all macOS privacy permissions as a first step. A visible permission switch alone does not prove capture or translation works.

## A language is missing or needs preparation

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

Wait for the saving indicator to finish. If an error names a recovery file, keep it until you have checked whether it is playable and recovered anything needed. Do not assume it is complete after a crash or power loss. Exported transparent-mode content includes the background by design.

## A downloaded app is blocked

Development builds are not a notarized public distribution. Do not disable Gatekeeper or broadly remove quarantine as a workaround. Use the documented local development workflow, or wait for a signed and notarized release that passes the release checklist.

## Report a problem

Include macOS and app version/build, Mac architecture, source/target languages, permission state, expected and actual behavior, and a minimal reproduction with invented text. State whether the build is local or a packaged candidate. Use the [bug template](../.github/ISSUE_TEMPLATE/bug_report.md); for vulnerabilities, follow [private reporting guidance](../SECURITY.md).
