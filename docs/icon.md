# App icon

Lens uses an original blue glass icon: an **A** on a document becomes **가** through an overlapping lens. The glyphs signal translation, not a restriction to a single language pair.

The master is [icon-1024.png](../Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png). The icon was created with the built-in ImageGen tool and exported with genuine PNG alpha. Standard macOS and Retina variants live in the same AppIcon catalog. Run `bash scripts/icon-sizes.sh` to regenerate smaller sizes mechanically with macOS `sips`; this does not redesign the master.

Tests validate all ten catalog slots, dimensions, alpha format, transparent corners, and an opaque center. Xcode compiles the catalog into the Release app's icon resources. These checks do not replace visual review at Dock size.

## Design prompt

The edit target was the initial blue glass lens/document concept, also generated with ImageGen.

> Use case: precise-object-edit. Edit target: the attached Lens macOS icon. Keep the blue rounded-square tile and translucent rounded rectangular glass lens aesthetic, but make TRANSLATION instantly recognizable. Replace the generic horizontal document lines with exactly two large bold crisp glyphs: a Latin 'A' on the upper-left part of the white source document, outside the lens; a Korean Hangul syllable '가' prominently centered in the glass lens in the lower-right foreground. Reposition the glass lens modestly down and right so both glyphs are distinct and readable. A single small rightwards arrow from A toward 가 connects the two language states. Preserve restrained native Mac dimensional materials, cool blue palette, bright glass rim, centered overall composition, generous margins. Simplify remaining document detail: no additional text lines or glyphs. Exact text only A and 가; correct Hangul typography, dark navy for contrast. Strong readable silhouette at Dock size, no flags or globe, no camera, no watermark. Production square PNG with genuine transparent ALPHA outside a clean rounded-square tile. No painted checkerboard, no opaque background, no stray pixels or speckles, no exterior haze.

## Final background-extraction prompt

> Use case: background-extraction. Remove the grey checkerboard background from this app icon. Return a transparent-background PNG cutout, with actual zero-alpha transparent pixels outside the blue rounded-square silhouette. The checkerboard is unwanted opaque image content and must disappear completely. This is background removal only: preserve the blue tile, the A, the arrow, the Korean 가, glass lens, lighting, and dimensions exactly. Clean antialiased edges, no remaining checkerboard, no white/black replacement background, no detached pixels. Use the transparent background output mode, not a drawing or simulation of transparency.
