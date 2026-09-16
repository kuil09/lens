# Distribution scope

Lens source is available under the [MIT License](../LICENSE), copyright **2026 kuil09**. The current external-distribution route is a downloadable GitHub DMG; notarization is separate from App Store submission.

## External distribution

Use [GitHub Releases](https://github.com/kuil09/lens/releases) for downloads and the corresponding [release record](https://github.com/kuil09/lens/releases) for exact artifact version, signature, notarization, checksum and remaining limits. A newer main commit or Actions artifact is not automatically a newer public download.

The workflow preserves `dev.local.lens` and the approved signer. The separate identifier in `Config/Distribution.xcconfig` remains inactive. Do not infer a preferences/permission migration from external notarization. See [Releasing](releasing.md) for supported packaging, protected CI, publication gates and rollback; [Development](development.md#stable-local-signing) covers local identity continuity.

## Deferred store direction

The owner chose a **paid Mac App Store one-time purchase, with no subscriptions** as a possible store distribution direction. Store implementation, signing and submission remain deferred; this repository's DMG workflow does not implement them. Pricing, store identity, sandbox/export compatibility and store install/update verification require separate work. This direction does not alter the MIT license.

## Publication

Keep one current public prerelease with a notarized DMG and its checksum. Retire superseded release entries and tags only after verifying the new public download, and only with explicit maintainer authorization. Keep a local recovery copy until the replacement is accepted. [Historical verification boundaries](validation-history.md) are not current installation instructions.
