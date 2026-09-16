# Privacy

This describes the current source implementation, not an independent privacy audit.

## Screen content and translation

Lens uses ScreenCaptureKit to capture the selected display region while excluding its own application. It requests Screen Recording access through an explicit user action, at most once per launch. Audio capture is disabled.

Vision recognizes screen text and Apple Translation uses installed on-device models. The current app source has no app-operated upload service, analytics integration, or third-party model server. Apple manages model availability and downloads; downloading language packs requires a network connection. Offline behavior still needs the [manual acceptance checks](releasing.md).

## Privacy manifest scope

The source privacy manifest, `Sources/Lens/Resources/PrivacyInfo.xcprivacy`, declares no tracking, no tracking domains, and no collected data types. It declares required-reason API use for same-app UserDefaults preferences (`CA92.1`) and system uptime used for elapsed-time scheduling and recording (`35F9.1`). The current app code does not implement outbound networking.

These statements describe the app's declaration and source scope. They are not certification, independent network-traffic verification, or a claim about every Apple service or user-selected sync destination. Verify that the manifest is included in the final signed bundle during release checks. Explicit screen exports still contain user data as described below.

## In-memory state

Captured frames, recognized text, and translations are held in memory for display and processing. A bounded in-memory translation cache may retain text during the app session; pausing is not a promise to erase that cache. Lens stores preferences, onboarding completion, and window state, not an automatic translation-history archive. Onboarding checks existing permission without requesting access automatically.

## Files you explicitly save

Image and video actions save the lens region with its displayed translations. **Transparent mode still includes the captured background in exports.** Private documents, messages, account details, and other visible content inside that region may be included.

Capture and record actions save automatically to the folder configured in settings without a per-file confirmation. The default is `~/Pictures/Lens`. A folder bookmark and display path persist as preferences; the most recently saved file is tracked only in memory. Lens does not save continuously unless you explicitly start recording, and does not automatically delete accumulated files.

Video frames stream to a temporary MP4 beside the selected destination. The completed file is published only after successful finalization, using a new name if another file already exists; existing exports are never replaced. A failure may leave a recovery file identified in the error dialog. A force quit or power loss may leave an incomplete file. Review and remove unwanted exports and recovery files yourself; Lens does not promise secure erasure.

Copy actions place selected content on the system clipboard. Chosen export folders, backups, clipboard tools, and sync services have their own retention and sharing behavior.

## Diagnostics and reports

Explicit benchmark mode uses synthetic reference text and writes a requested JSON report. Tests can also generate synthetic images and video fixtures. These are separate from screen-capture exports.

Never attach private screen content to an issue or pull request. Reproduce problems with the bundled synthetic fixture or invented text. Remove personal paths, account names, tokens, screen text, and other identifying data from any diagnostic excerpt. Keep private activity logs and screenshots out of the repository.

Report security concerns through the [security policy](../SECURITY.md).
