#!/bin/bash
# Exercise the real index check with synthetic files; no signing or app execution.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORK=$(mktemp -d /private/tmp/lens-hygiene-regression.XXXXXX)
cleanup() {
    case "$WORK" in /private/tmp/lens-hygiene-regression.??????) [ ! -L "$WORK" ] && rm -rf -- "$WORK" ;; esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$WORK/scripts"
cp "$HERE/../repository-hygiene.sh" "$WORK/scripts/"
git -C "$WORK" init -q
cp "$HERE/fixtures/Version.xcconfig" "$WORK/Allowed file.xcconfig"
git -C "$WORK" add -- 'Allowed file.xcconfig'
CHECK="$WORK/scripts/repository-hygiene.sh"
bash "$CHECK"
count=1
for file in 'Lens.dmg' 'Release/Lens.pkg' 'Preview.zip' \
    'Config/LocalSigning.xcconfig' 'dist/Preview.zip' 'build-design/output' 'Test.xcresult/Info.plist' \
    'Profile.mobileprovision' 'Profile.provisionprofile' 'Private.p12' 'Private.p8' \
    'login.keychain-db' 'config/.env.local' 'Lens.app/Contents/Info.plist' \
    'Project/xcuserdata/settings.xcuserstate' $'nested\nfolder/Profile.mobileprovision'; do
    mkdir -p "$(dirname "$WORK/$file")"
    cp "$HERE/fixtures/Version.xcconfig" "$WORK/$file"
    # Untracked local artifacts must not block repository checks.
    bash "$CHECK"
    git -C "$WORK" add -- "$file"
    if bash "$CHECK" > "$WORK/result" 2>&1; then
        printf 'FAIL: staged artifact was accepted: %q\n' "$file" >&2
        exit 1
    fi
    grep -Fq 'Tracked artifact hygiene failed' "$WORK/result"
    git -C "$WORK" rm --cached -q -- "$file"
    bash "$CHECK"
    count=$((count + 3))
done
printf 'Repository hygiene regressions passed (%s assertions; synthetic Git index).\n' "$count"
