# Changelog

## 0.1.0-beta.1 — 2026-09-15

App version: **0.1.0 (build 2)**. Development preview; the downloadable Release build is ad-hoc signed and not notarized.

### Added

- Resizable screen-translation lens with reproduced-background and transparent modes, source masking, click-through, and a full-text reader.
- Runtime Apple Translation language catalog, Vision-compatible source selection, installed-pair preparation, and a target preference that can follow supported macOS preferred languages.
- Korean native settings and menus, a lens toolbar, explicit PNG export, and silent MP4 recording.
- Development, usage, privacy, troubleshooting, release/manual acceptance, contribution, and security documentation; issue and pull request templates.
- A blue glass app icon with an A-to-가 translation motif, macOS standard and Retina sizes, and asset validation tests.
- Native About panel reads version, build, and release channel from bundle metadata; the candidate display is 0.1.0-beta.1 (2).
- Privacy manifest declares no tracking or collected data types, with reasons for same-app preferences and elapsed-time APIs. This declaration is not a privacy certification.

### Release readiness

- [MIT License](LICENSE), copyright **2026 kuil09**, is included in the development ZIP alongside the app.
- Public bundle identifier and Developer ID signing/notarization remain pending. This preview retains the development identifier `dev.local.lens`.
- Some translation has been observed during use. Formal whole-runtime acceptance, broad translation-quality review, end-to-end performance, offline/download recovery, multiple monitors, and sustained-operation checks remain incomplete.
- Translation-language selection is dynamic; the app UI remains Korean. Neither every OS language nor full UI localization is claimed.
