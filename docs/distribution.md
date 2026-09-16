# Distribution direction and status

## Planned direction

The owner confirmed a **paid Mac App Store one-time purchase, with no subscriptions**. Planning is allowed; store implementation, signing, submission, and publication are deferred. No store purchase flow, store-ready build, or approval is claimed. Pricing, store identity/configuration, sandbox/export compatibility, and install/update validation remain future work. The existing packaging script is not a Mac App Store submission workflow.

The source remains under the [MIT License](../LICENSE), copyright **2026 kuil09**. The purchase direction does not change that license or its notice requirements.

## Artifact status and history

- **Current notarized prerelease:** [v0.1.0-beta.5](https://github.com/kuil09/lens/releases/tag/v0.1.0-beta.5), app 0.1.0/build 15, adds source filtering, stable reading and rounded resize controls while retaining the redesigned installer. The owner separately authorized notarization and GitHub replacement; see [exact artifact evidence](releases/build-15-validation.md) and [release notes](releases/v0.1.0-beta.5.md). Main history is preserved. No installed app, bundle identity, or user settings were migrated by this publication. App Store work remains separate.
- **Previous development prerelease:** [v0.1.0-beta.4](https://github.com/kuil09/lens/releases/tag/v0.1.0-beta.4), app 0.1.0/build 10, remains historical and unnotarized. It contains capture feedback, save-folder access, and window-return improvements retained by beta.5. See [historical notes](releases/v0.1.0-beta.4.md).

- **Retired downloads:** beta.1/build 2 (ad-hoc ZIP), beta.2/build 6 and beta.3/build 9 (Developer ID signed DMGs) have been replaced. Old release notes are historical evidence. The beta.3 source tag is retained; its binary and checksum attachments were replaced by beta.4.
- **Withdrawn:** the signed beta.2/build 3 notarization candidate was uploaded before the owner's September 15, 2026 withdrawal, but was not installed or published. Its local outputs were removed and version metadata was restored to beta.1 at that time. That rollback is historical; build 3 must not be reused. Local cleanup did not cancel Apple-side processing, and no acceptance is claimed. Certificates and owner-created Keychain credentials were retained. Do not resume that workflow or status polling as part of store planning.
- **Signing continuity:** [machine-local configuration](development.md#stable-local-signing) supplies the existing signer without changing the bundle ID or preferences; fresh clones default to ad-hoc signing. The earlier public identifier `io.github.kuil09.lens` remains inactive and `Config/Distribution.xcconfig` remains blank for the identifier. The new explicitly authorized notarization preserves `dev.local.lens`; it neither enables store signing nor changes the wrapper's public-identifier gate.

## Authoritative guides

- [Development](development.md): local identity, build/test commands, and development packaging.
- [Releasing and manual acceptance](releasing.md): packaging validation, retained inactive Developer ID reference, and runtime acceptance criteria. These do not establish store readiness.
- [Localization](localization.md): English/Korean/Japanese UI coverage and recorded validation, separate from translation packs or store listing localization.

Whole-runtime acceptance remains incomplete. Future distribution work must record evidence for the exact candidate; existing automated checks and text-only model probes do not close runtime NOT_RUN items.
