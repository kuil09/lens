# App icon

Lens uses an original blue glass icon: an **A** on a document becomes **가** through an overlapping lens. The glyphs signal translation, not a restriction to a single language pair.

The master is [icon-1024.png](../Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png). The icon was created with the built-in ImageGen tool and exported with genuine PNG alpha. Standard macOS and Retina variants live in the same AppIcon catalog. Run `bash scripts/icon-sizes.sh` to regenerate smaller sizes mechanically with macOS `sips`; this does not redesign the master.

Tests validate all ten catalog slots, dimensions, alpha format, transparent corners, and an opaque center. Xcode compiles the catalog into the Release app's icon resources. These checks do not replace visual review at Dock size.

Preserve the checked-in master and alpha edges when regenerating sizes. New artwork requires visual review rather than replaying historical generation prompts.
