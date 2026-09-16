# GitHub-hosted notarized DMGs

## Two deliberately separate workflows

- `Lens CI`: unprivileged checks, unit tests, ad-hoc build, and an explicitly `DEVELOPMENT-NOT-NOTARIZED` DMG plus checksum. Build and packaging run in the **same job**; `needs` does not share a filesystem. Dependencies use a temporary venv. PRs never receive signing secrets.
- `Lens Notarized DMG`: manual `workflow_dispatch`, only `kuil09/lens` on `main`, protected by the `release-signing` environment. Checks/tests precede signing. It produces a verified artifact, **not a GitHub Release**, and cannot replace existing release files (`contents: read`).

Both use the explicitly checked Xcode 26.4.1 on GitHub's `macos-26` arm64 runner. Development artifacts expire after 7 days; notarized artifacts after 14 days. Downloading Actions artifacts requires GitHub access and is not a substitute for a separately authorized public release.

## Environment configuration

Before registering secrets, configure `release-signing` with a required owner/release-maintainer reviewer and a custom deployment branch rule allowing only `main`. Protect main and review workflow/script changes as signing-sensitive code. Do not use repository-wide secrets or grant signing access to forks, PR events, arbitrary checkout refs, or self-hosted machines. A manual dispatch still needs the environment's approval.

Environment secrets:

| Name | Content |
| --- | --- |
| `LENS_CERTIFICATE_P12_BASE64` | Base64 of an encrypted PKCS#12 containing **only** the existing Developer ID Application certificate and corresponding private key |
| `LENS_CERTIFICATE_PASSWORD` | The PKCS#12 encryption password |
| `LENS_APPLE_ID` | Apple account used for notarization |
| `LENS_APPLE_APP_PASSWORD` | Existing app-specific password; never the account login password |

Environment variable `LENS_TEAM_ID` holds the certificate's 10-character team ID. Keep the existing signer and `dev.local.lens` identity to avoid an unrequested settings/permission migration. Missing inputs fail before importing or submitting anything. Secrets must be transferred only with owner authorization, never via checked-in files, shell tracing, chat, screenshots, or broad exports of all Keychain identities.

GitHub documents [installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications). Apple documents [customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). This is Developer ID distribution, not App Store submission, and this app does not need a provisioning profile for its current entitlements.

## Execution and fail-closed boundary

1. Preflight repository/event/ref, configuration, clean checkout, and source SHA. There are no user-supplied shell arguments or arbitrary build refs.
2. Import the one certificate into an ephemeral, owner-only keychain; require exactly one Developer ID Application identity matching the configured team. Limit key access to signing tools. Store the existing notarization credential in that temporary keychain and unset credential environment variables before compilation.
3. Build with hardened runtime and secure timestamp, explicitly setting `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. Verify signature, team, identity, timestamp, and the signed binary's entitlements before submission. Reject debugger attachment permissions (including malformed/non-boolean values), even if a build setting claims they are disabled. This must not depend on ignored local signing configuration.
4. Submit the app ZIP once. Record the submission ID, wait at most 15 minutes, require `Accepted`, staple, and validate both ticket and Gatekeeper acceptance.
5. Reuse existing metadata-validated development packaging as a staging operation. Sign and separately notarize the DMG. Only after acceptance, stapling, and Gatekeeper assessment may its final filename omit the development warning. The wrapper's old public-identifier gate remains intact.
6. Mount the finished image read-only and validate the **contained app**, ticket, Gatekeeper, byte comparison against the built app, license, and Applications link. This catches Finder-attribute changes that can invalidate an otherwise accepted app.
7. Compute SHA-256 after stapling. Output only the DMG, checksum, and allowlisted source/submission provenance. A source-SHA suffix distinguishes CI artifacts from the already-published beta.5 even while version metadata is unchanged. Use an unused build number for a new application candidate; explicitly distinguish packaging-only replacements by commit and artifact name.
8. Delete the temporary private keychain and signing files on exit, with an `always()` cleanup fallback. Hosted runners are destroyed after execution. Do not upload DerivedData, keychains, certificates, submission archives, or raw service logs.

An Apple timeout is **not** rejection and is not success. Do not automatically resubmit: use the submission ID from that run to investigate first. No artifact-upload step runs after failure. An accepted notarization does not establish a clean-machine install, privacy permission grant, correct translation, or end-to-end UX.

## Validation

Run-specific credential, authentication and rejection evidence belongs in [the build-15 CI follow-up](releases/build-15-validation.md#ci-follow-up--2026-09-16). This guide defines prerequisites and checks, not a live assertion that Secrets are missing or that CI has succeeded.

`make check` includes pure-Python metadata and preflight tests with fake secrets: all missing secrets, forks, PR events, wrong branches, local/self-hosted runs, invalid team/SHA, ambiguous/wrong certificate types, non-Accepted states, mismatched submission IDs, and provenance field allowlisting. These deliberately perform **no** Keychain import or Apple submission. `actionlint` and ShellCheck can validate the workflow/script locally. The real signed workflow requires the configured environment, usable secrets, and its human approval; mocks and local beta.5 notarization are not evidence of CI notarization success.
