#!/bin/bash
# Inspect the Git index, including staged additions, without printing file contents.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# NUL delimiters also protect checks for paths containing whitespace or newlines.
git -C "$ROOT" ls-files -z | (
    bad=0
    while IFS= read -r -d '' file; do
        case "$file" in
            Config/LocalSigning.xcconfig)
                printf 'Tracked machine-local signing configuration: %q\n' "$file" >&2
                bad=1 ;;
            .build/*|build/*|build-*/*|DerivedData/*|dist/*|*.dmg|*.pkg|*.zip|*.app/*|*.dSYM/*|*.xcarchive/*|*.xcresult/*|*.xcuserstate|*/xcuserdata/*|.DS_Store|*/.DS_Store|.env|.env.*|*/.env|*/.env.*|*.p12|*.p8|*.keychain|*.keychain-db|*.mobileprovision|*.provisionprofile)
                printf 'Tracked generated/private artifact: %q\n' "$file" >&2
                bad=1 ;;
        esac
    done
    if [ "$bad" != 0 ]; then
        printf 'Lens: Tracked artifact hygiene failed.\n' >&2
        exit 1
    fi
)
