#!/bin/bash
# GitHub-hosted, main-only signing. Never source this file or enable shell tracing.
set +x
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
die() { printf 'Lens notarization: %s\n' "$*" >&2; exit 1; }

require_runner() {
    [ "${GITHUB_ACTIONS:-}" = true ] && [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || die 'Use a GitHub-hosted runner.'
    [ "${GITHUB_REPOSITORY:-}" = kuil09/lens ] && [ "${GITHUB_REF:-}" = refs/heads/main ] &&
        [ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ] || die 'Only an explicit main-branch workflow dispatch can sign.'
    [ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ] && [ ! -L "$RUNNER_TEMP" ] || die 'Invalid runner temporary directory.'
    [[ "$RUNNER_TEMP" = /* ]] && [ "$RUNNER_TEMP" != / ] || die 'Unsafe runner temporary directory.'
}
preflight() {
    require_runner
    local name
    for name in LENS_CERTIFICATE_P12_BASE64 LENS_CERTIFICATE_PASSWORD LENS_APPLE_ID LENS_APPLE_APP_PASSWORD LENS_TEAM_ID; do
        [ -n "${!name:-}" ] || die "Missing $name in release-signing. No signing or submission was attempted."
    done
    [[ "$LENS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die 'Invalid signing team format.'
    [[ "${GITHUB_SHA:-}" =~ ^[a-f0-9]{40}$ ]] || die 'Invalid source commit.'
}
cleanup() {
    require_runner
    local state="$RUNNER_TEMP/lens-notarization-private"
    [ ! -L "$state" ] || die 'Refusing a symlinked signing directory.'
    if [ -d "$state" ]; then
        if [ -f "$state/keychain-db" ]; then security delete-keychain "$state/keychain-db" >/dev/null 2>&1 || true; fi
        # Only this job's disposable private directory, never the login keychain.
        rm -rf -- "$state"
    fi
}
submit() {
    local input=$1 label=$2
    # No automatic retries: a timeout may leave a submission processing at Apple.
    xcrun notarytool submit "$input" --keychain-profile lens-ci --keychain "$keychain" \
        --output-format json > "$state/$label-submit.json"
    local submission
    submission=$(python3 "$ROOT/scripts/notary-result.py" id "$state/$label-submit.json")
    printf '%s submission: %s\n' "$label" "$submission"
    xcrun notarytool wait "$submission" --keychain-profile lens-ci --keychain "$keychain" \
        --timeout 15m --output-format json > "$state/$label-status.json"
    python3 "$ROOT/scripts/notary-result.py" accepted "$state/$label-status.json" "$submission"
}
assess() {
    local path=$1 kind=$2 result
    codesign --verify --deep --strict "$path"
    xcrun stapler validate "$path"
    if [ "$kind" = app ]; then
        result=$(spctl --assess --type execute --verbose=2 "$path" 2>&1)
    else
        result=$(spctl --assess --type open --context context:primary-signature --verbose=2 "$path" 2>&1)
    fi
    printf '%s\n' "$result"
    printf '%s\n' "$result" | grep -qx 'source=Notarized Developer ID' || die 'Expected notarized Gatekeeper acceptance.'
}
build() {
    preflight
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$GITHUB_SHA" ] || die 'Checkout does not match the requested commit.'
    [ -z "$(git -C "$ROOT" status --porcelain)" ] || die 'A clean checkout is required.'
    [ ! -e "$ROOT/Config/LocalSigning.xcconfig" ] || die 'Machine-local signing configuration is not allowed in CI.'
    state="$RUNNER_TEMP/lens-notarization-private"
    output="$RUNNER_TEMP/lens-notarized-output"
    [ ! -e "$state" ] && [ ! -e "$output" ] || die 'Refusing to reuse signing or output directories.'
    mkdir "$state"
    keychain="$state/keychain-db"
    mounted=''
    trap 'if [ -n "$mounted" ]; then hdiutil detach "$mounted" >/dev/null 2>&1 || true; fi; cleanup' EXIT
    local password identity details archive final_name
    password=$(openssl rand -hex 32)
    printf '::add-mask::%s\n' "$password"
    printf '%s' "$LENS_CERTIFICATE_P12_BASE64" | base64 --decode > "$state/certificate.p12"
    security create-keychain -p "$password" "$keychain"
    security set-keychain-settings -lut 3600 "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    security import "$state/certificate.p12" -k "$keychain" -P "$LENS_CERTIFICATE_PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
    security list-keychains -d user -s "$keychain"
    identity=$(security find-identity -v -p codesigning "$keychain" | \
        python3 "$ROOT/scripts/notary-result.py" identity "$LENS_TEAM_ID")
    xcrun notarytool store-credentials lens-ci --keychain "$keychain" --apple-id "$LENS_APPLE_ID" \
        --team-id "$LENS_TEAM_ID" --password "$LENS_APPLE_APP_PASSWORD" >/dev/null
    rm -f "$state/certificate.p12"
    unset LENS_CERTIFICATE_P12_BASE64 LENS_CERTIFICATE_PASSWORD LENS_APPLE_ID LENS_APPLE_APP_PASSWORD password

    xcodebuild -project "$ROOT/Lens.xcodeproj" -scheme Lens -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$state/build" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$LENS_TEAM_ID" \
        PRODUCT_BUNDLE_IDENTIFIER=dev.local.lens ENABLE_HARDENED_RUNTIME=YES \
        OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $keychain" ARCHS=arm64 build
    app="$state/build/Build/Products/Release/Lens.app"
    codesign --verify --deep --strict "$app"
    details=$(codesign --display --verbose=4 "$app" 2>&1)
    printf '%s\n' "$details" | grep -qx "TeamIdentifier=$LENS_TEAM_ID"
    printf '%s\n' "$details" | grep -q '^Authority=Developer ID Application:'
    printf '%s\n' "$details" | grep -q '^Timestamp='
    printf '%s\n' "$details" | grep -Eq '^CodeDirectory .*flags=.*runtime'
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = dev.local.lens ] || die 'Unexpected bundle identity.'
    ditto -c -k --sequesterRsrc --keepParent "$app" "$state/app.zip"
    submit "$state/app.zip" app
    xcrun stapler staple "$app"
    assess "$app" app

    # The existing wrapper checks metadata but does not sign the image. Its public
    # identifier gate stays intact; staging is honestly labeled nonnotarized.
    bash "$ROOT/scripts/lens.sh" package --app "$app" --development --format dmg
    shopt -s nullglob
    local images=("$ROOT"/dist/*-DEVELOPMENT-NOT-NOTARIZED.dmg)
    [ "${#images[@]}" = 1 ] || die 'Expected exactly one staging DMG.'
    archive=${images[0]}
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp "$archive"
    submit "$archive" dmg
    xcrun stapler staple "$archive"
    assess "$archive" dmg
    mkdir "$state/mount"
    mounted="$state/mount"
    hdiutil attach -readonly -nobrowse -mountpoint "$mounted" "$archive"
    assess "$mounted/Lens.app" app
    diff -qr "$app" "$mounted/Lens.app"
    cmp "$ROOT/LICENSE" "$mounted/LICENSE"
    [ "$(readlink "$mounted/Applications")" = /Applications ] || die 'Invalid Applications link.'
    hdiutil detach "$mounted"
    mounted=''
    hdiutil verify "$archive"

    final_name="$(basename "$archive" -DEVELOPMENT-NOT-NOTARIZED.dmg)-ci-${GITHUB_SHA:0:12}.dmg"
    mkdir "$output"
    cp "$archive" "$output/$final_name"
    (cd "$output" && shasum -a 256 "$final_name" > "$final_name.sha256" && shasum -c "$final_name.sha256")
    python3 "$ROOT/scripts/notary-result.py" provenance "$output/provenance.json" "$GITHUB_SHA" \
        "$state/app-status.json" "$state/dmg-status.json" "$final_name"
    printf 'Verified notarized artifact: %s\n' "$final_name"
}
case "${1:-}" in
    preflight) preflight ;;
    build) build ;;
    cleanup) cleanup ;;
    *) die 'Use preflight, build, or cleanup.' ;;
esac
