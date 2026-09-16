# Releasing and manual acceptance

This is a procedure, not a declaration that a candidate passed. Exact published versions, hashes, signing/notarization routes, and remaining limits belong to [release notes](releases/v0.1.0-beta.5.md) and their linked validation records. Source changes, CI artifacts, and public downloads are separate states.

## Select and preserve the candidate

1. Inspect the worktree, remote main, existing tag/release assets, and any running CI or Apple submissions. Preserve unrelated work and user settings. Do not repeat a partially completed commit, dispatch, submission, or upload.
2. Pin the intended commit. Read version/build/channel from [Version.xcconfig](../Config/Version.xcconfig); compare installed, local-preview, and public artifacts. New application candidates need an unused build number. Packaging-only CI outputs include the source SHA to distinguish otherwise identical version metadata.
3. Preserve the approved `dev.local.lens` identity and Developer ID team unless an identity migration is explicitly requested. [Distribution.xcconfig](../Config/Distribution.xcconfig) still has a blank separate public identifier; do not enable or repurpose it to run the current identity-preserving CI path.
4. Run relevant checks/tests and document runtime acceptance on synthetic content. A build/package operation alone does not authorize publication, a tag move, or history rewriting.

## Development packaging

Build/test instructions are in [Development](development.md). Quit the selected app before packaging an existing Release product:

```sh
make package ARGS='--development'
make package ARGS='--development --format dmg'
```

Choose the required format; ZIP is the default and does not need packaging dependencies. DMG requires [the pinned packaging tools](dmg-installer.md#packaging-only-setup). Both commands consume an existing app: they do not build, sign, notarize, launch, quit, or publish it.

Output names derive from the built version/channel/build and retain **DEVELOPMENT-NOT-NOTARIZED**, even if the contained app has a Developer ID signature. Inspect the path printed by the command and its checksum sidecar, not a historical filename. Existing outputs are not overwritten. `--app` accepts an existing Lens.app by absolute physical path without altering another running build.

The wrapper requires the license and validates app metadata, arm64 support, minimum macOS version in bundle/executable, and privacy manifest. ZIP contains Lens.app and LICENSE; DMG also includes the Applications symlink and installer artwork. A successful development package cannot be relabeled as notarized.

## Notarized DMG via protected CI

The supported automated path is **Lens Notarized DMG**, a manual main-only workflow protected by the `release-signing` environment. See [CI configuration and execution](ci-notarization.md) for the single authoritative list of Secret/variable names and checks. Environment rules and main restrictions must be preserved; required human review must not be self-approved or bypassed.

Before an authorized dispatch, pin/verify remote main and the workflow's source SHA. The workflow validates tools, runs checks/tests, imports the existing signer into a disposable keychain, authenticates with Apple, and builds with hardened runtime, secure timestamp, and no debugger-attachment entitlement. It then:

1. Submits the app ZIP once, requires **Accepted**, staples and validates the app, and assesses Gatekeeper.
2. Creates a staging development DMG from that exact app, signs/submits the DMG separately, requires **Accepted**, staples it and assesses Gatekeeper.
3. Mounts the image read-only and validates the contained app, file equality, license and Applications link.
4. Computes SHA-256 after all mutations and uploads only the DMG, sidecar and allowlisted provenance as an Actions artifact.

It does **not** create/update a GitHub Release. Secret existence, real authentication, app acceptance, DMG acceptance, and public-file validation must each be recorded separately. A corrected workflow's tests do not prove its next Apple submission will pass. Never put private keys, passwords, or unrestricted service logs in documentation/artifacts.

The wrapper's older no-`--development` public-package mode remains guarded by a separately confirmed identifier matching Distribution.xcconfig, a pre-signed/pre-notarized app, and a stapled ticket. That configuration is inactive; it is **not** the entrypoint for the current CI flow and is not a Mac App Store workflow. Historical local notarization records describe what happened, not a copy-and-run fallback recipe. Do not hide CI failures by silently switching to local signing.

## Release gates and recovery

Record PASS, FAIL, NOT_RUN or BLOCKED per candidate. No checked checkbox here is inherited by a future build.

- Verify the final app version/build/channel, existing bundle ID and team, Developer ID Application signature, hardened runtime, secure timestamp and permitted entitlements.
- Check icon resources and actual Finder/Dock/About appearance separately. Verify the privacy manifest matches current API use and the exact [MIT license](../LICENSE) is included.
- Require app and DMG **Accepted** results with submission IDs, stapled-ticket validation, strict signature checks, and Gatekeeper acceptance of both DMG and contained app. Upload success or timeout is not acceptance.
- On timeout, query the existing submission ID instead of blind resubmission. On rejection, distinguish authentication from build/signing/packaging faults and inspect sanitized reasons. Fix a rejected binary before making another submission; do not publish failed output.
- Mount the exact candidate read-only; compare the app against the signed source bundle and inspect Applications link, license, artwork and metadata. Check image integrity and checksum after stapling. Exclude secrets, activity logs, personal screenshots and build scratch material.
- Exercise the acceptance matrix below. Preserve explicit limits and obtain any required maintainer acceptance of deferred items; security checks do not waive data-loss or use-blocking failures.
- Review release notes/changelog, privacy and security-reporting instructions. Any account/repository security-setting changes are separate authorized actions, not implicit packaging steps.
- For an authorized replacement, retain the previous exact assets and tag object temporarily. Upload the uniquely named new DMG/sidecar first; redownload from GitHub and verify checksum, signature, tickets and contained app before removing **only** the named old replacement assets.
- Update release notes/tag only to the approved source. If a tag move is authorized, check its recorded old remote value; never rewrite main as an incidental release operation. Test installation from the public download without clearing quarantine or resetting permissions.
- If public-file/install verification fails, do not report completion; restore the previous assets/tag within the approved replacement scope. After successful replacement, remove temporary recovery copies safely. Publish source SHA, CI link, notarization route/IDs, public download/checksum, actual runtime results and untested boundaries.

## Manual acceptance matrix

Candidate-specific evidence belongs under `docs/releases/`, linked from that release's notes. Record revision/version/build, macOS and architecture, display configuration, installed language pairs, and sanitized observations. A partial observation does not pass an entire scenario.

| Scenario | Acceptance criterion |
| --- | --- |
| Clean install / update | Install the exact downloaded candidate without security bypass. Check identity/icon/version, first-run denial/grant and retry, then paused relaunch after completion. Update without losing language/save-folder choices; record both identities and consent behavior. |
| Core translation | Use synthetic horizontal Korean/Japanese/English in six installed directions; assess meaning, alignment, source filtering and Auto Detect. Exercise line wrapping, changing numbers/negation, scrolling and region/language changes without stale overlays. |
| Reader / overflow | Reader selection/scroll stay fixed until manual Apply; prior-screen/pending labels are clear. Truncated popovers work only when unlocked and close on invalidation/handoff. |
| Languages / offline | Check missing/unsupported pairs, readiness-in-progress, failure/retry and canceled downloads. Follow system guidance, return/recheck, then test new synthetic text offline. Do not remove a user's models merely to create a test case. |
| Sustained use | At least 30 minutes of static/scrolling content, move/resize and language changes; measure responsiveness, CPU/memory and thermal behavior. Duration alone is not a latency guarantee. |
| Displays / Spaces | Different scales, screen boundaries/disconnects, Spaces and full-screen apps; verify alignment, valid capture regions and recovery. |
| Lifecycle / input | Real cross-app body click/drag/scroll and keyboard focus; toolbar/unlock/record-stop/resize remain usable with no double input. Move, zoom, minimize, restore, hide, close, sleep and quit leave no orphan panels. System Settings hides all overlay panels without obstructing authentication. |
| Export / recovery | PNG and playable silent MP4 contain background/translations but no toolbar, resize marks or popover. Check camera success/failure, current-folder opening, persistence, collisions/no overwrite, folder changes mid-recording, missing-folder errors, stop/finalization and recovery with disposable files. |
| UI / accessibility | English/Korean/Japanese, narrow windows, light/dark, Reduce Transparency/Motion, keyboard and VoiceOver. Glass layout screenshots alone do not establish actual compositor appearance or focus/input behavior. |

Keep automated CI, artifact inspection, real macOS use, and clean-machine acceptance separate. Historical records are evidence for their exact builds, not blanket acceptance of newer source.
