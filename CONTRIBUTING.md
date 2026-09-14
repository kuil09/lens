# Contributing to Lens

Lens is a development preview. Start with the [development guide](docs/development.md), [privacy notes](docs/privacy.md), and [manual acceptance checklist](docs/releasing.md).

## Issues

Search existing issues, then use the bug or feature template. For bugs, include macOS and app version/build, permission state, expected/actual behavior, and a minimal reproduction with synthetic text. **Never attach private screen content**, personal activity logs, credentials, or unredacted diagnostics.

Security concerns must follow [SECURITY.md](SECURITY.md), not a public bug report.

## Changes

Keep changes focused and preserve unrelated work. Explain the user-visible problem and resulting behavior. Use English for new identifiers, code comments, and technical documentation; preserve the existing Korean UI unless localization is part of the change.

Run checks relevant to the change using the documented development workflow. Report exact results, skipped tests, and remaining manual checks in the pull request. Add a changelog entry for user-visible changes. Automated tests and CI are not evidence of real screen capture, translation quality, sustained performance, or notarization.

Do not include build output, generated screenshots, private screen recordings, personal paths, or secrets. Use synthetic fixtures for reproducible examples.

Lens uses the [MIT License](LICENSE), copyright 2026 kuil09. Preserve the license notice in distributions. This guide does not introduce a separate contributor agreement.
