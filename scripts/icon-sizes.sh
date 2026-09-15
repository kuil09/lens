#!/bin/bash
# Mechanical size exports from the committed master; no design changes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
ICON_SET="$ROOT/Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset"
MASTER="$ICON_SET/icon-1024.png"
test -f "$MASTER"
for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICON_SET/icon-$size.png" >/dev/null
done
printf 'Exported macOS icon sizes from the 1024px master.\n'
