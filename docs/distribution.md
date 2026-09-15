# Distribution direction and status

## Planned direction

The owner confirmed a **paid Mac App Store one-time purchase, with no subscriptions**. Planning is allowed; store implementation, signing, submission, and publication are deferred. No store purchase flow, store-ready build, or approval is claimed. Pricing, store identity/configuration, sandbox/export compatibility, and install/update validation remain future work. The existing packaging script is not a Mac App Store submission workflow.

The source remains under the [MIT License](../LICENSE), copyright **2026 kuil09**. The purchase direction does not change that license or its notice requirements.

## Artifact status and history

- **Retired downloads:** beta.1/build 2 (ad-hoc ZIP) and beta.2/build 6 (Developer ID signed DMG) have been replaced by beta.3. Their old release notes are historical evidence; obsolete remote tags and assets were retired during the owner-authorized history cleanup.
- **Withdrawn:** the signed beta.2/build 3 notarization candidate was uploaded before the owner's September 15, 2026 withdrawal, but was not installed or published. Its local outputs were removed and version metadata was restored to beta.1 at that time. That rollback is historical; build 3 must not be reused. Local cleanup did not cancel Apple-side processing, and no acceptance is claimed. Certificates and owner-created Keychain credentials were retained. Do not resume that workflow or status polling as part of store planning.
- **Current development prerelease:** [v0.1.0-beta.3](https://github.com/kuil09/lens/releases/tag/v0.1.0-beta.3), app 0.1.0/build 9, `dev.local.lens`. The owner authorized history consolidation, force-push, and replacement of the preview downloads. The DMG contains a Developer ID signed app and retains the explicit NOT-NOTARIZED label. [Machine-local configuration](development.md#stable-local-signing) supplies the existing signer without changing the bundle ID or preferences; fresh clones default to ad-hoc signing. See [release notes and acceptance limits](releases/v0.1.0-beta.3.md). The earlier public identifier `io.github.kuil09.lens` remains inactive and `Config/Distribution.xcconfig` remains blank for the identifier. No store signing or external notarization workflow was enabled.

## Authoritative guides

- [Development](development.md): local identity, build/test commands, and development packaging.
- [Releasing and manual acceptance](releasing.md): packaging validation, retained inactive Developer ID reference, and runtime acceptance criteria. These do not establish store readiness.
- [Localization](localization.md): English/Korean/Japanese UI coverage and recorded validation, separate from translation packs or store listing localization.

Whole-runtime acceptance remains incomplete. Future distribution work must record evidence for the exact candidate; existing automated checks and text-only model probes do not close runtime NOT_RUN items.
