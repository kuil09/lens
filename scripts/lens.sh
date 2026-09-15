#!/bin/bash
# Compatible with the macOS system Bash (3.2). Never enable shell tracing here.
set -euo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

die() { printf 'Lens: %s\n' "$*" >&2; exit 1; }
usage() {
    printf '%s\n' \
        'Usage: bash scripts/lens.sh check|test|build|package|clean [options]' \
        '  --derived-data PATH    Default: <repo>/build-design' \
        '                         Alternate: existing physical mktemp directory named' \
        '                         lens-derived-data.XXXXXX or tmp.XXXXXX directly in' \
        '                         /private/tmp or the physical system TMPDIR.' \
        '  --installed-languages  test only; opt in to already-installed model tests' \
        '  --app PATH            package only; existing Lens.app (default: Release product)' \
        '  --development         package only; explicitly nonnotarized preview archive' \
        '  --format zip|dmg      package only; default zip, dmg includes Applications link' \
        '                         DMG requires dmgbuild (see Packaging/requirements.txt).' \
        '  --confirmed-distribution-id ID  public package only; user-confirmed bundle ID' \
        'Public packaging only validates pre-signed, pre-notarized, stapled apps.' \
        'It never signs, submits for notarization, launches, or quits an app.' \
        'clean removes only known generated children of the selected DerivedData.' \
        'It preserves dist, legacy build directories, and the separate root .build.'
}

# Reject ambiguous spellings and symlink components before any mutation.
safe_path() {
    local path=$1 cursor='' part
    case "$path" in
        /*) ;;
        *) die 'Paths must be absolute physical paths.' ;;
    esac
    case "$path" in
        /|*/|*//*|*/../*|*/..|*/./*|*/.|*$'\n'*|*$'\r'*|*$'\t'*) die 'Unsafe path.' ;;
    esac
    local rest=${path#/}
    while [ -n "$rest" ]; do
        part=${rest%%/*}
        cursor="$cursor/$part"
        [ ! -L "$cursor" ] || die 'Symlink paths are not allowed.'
        if [ "$rest" = "$part" ]; then break; fi
        [ ! -e "$cursor" ] || [ -d "$cursor" ] || die 'Non-directory path component.'
        rest=${rest#*/}
    done
}

validate_derived_data() {
    safe_path "$DD"
    if [ "$DD" != "$ROOT/build-design" ]; then
        local parent=${DD%/*} name=${DD##*/} system_tmp
        system_tmp=$(cd "${TMPDIR:-/private/tmp}" && pwd -P)
        [ "$parent" = /private/tmp ] || [ "$parent" = "$system_tmp" ] || die 'Unknown DerivedData location.'
        [[ "$name" =~ ^(lens-derived-data|tmp)\.[A-Za-z0-9]{6,}$ ]] || die 'Use a dedicated mktemp DerivedData directory.'
        [ -d "$DD" ] && [ -O "$DD" ] || die 'Alternate DerivedData must exist and be owned by this user.'
    fi
    [ ! -e "$DD" ] || [ -d "$DD" ] || die 'DerivedData must be a directory.'
}

# ps failure is never evidence that an app is stopped. Do not print process args.
# Only processes inside this output tree block alternate-tree integration tests.
guard_running() {
    local processes line
    processes=$(ps -ww -axo comm= 2>/dev/null) || die 'Cannot inspect processes; refusing mutation.'
    [ -n "$processes" ] || die 'Empty process snapshot; refusing mutation.'
    while IFS= read -r line; do
        # macOS ps can pad the comm column; preserve spaces inside the executable path.
        line="${line#"${line%%[![:space:]]*}"}"
        if [ "$COMMAND" != package ]; then
            case "$line" in
                "$DD"/*) die 'A process is running from the selected DerivedData; stop it manually or use alternate DerivedData.' ;;
            esac
        fi
        if [ -n "$APP" ]; then
            case "$line" in "$APP"/*) die 'The selected app is running; refusing packaging.' ;; esac
        fi
    done <<< "$processes"
}

LOCK=''
PACKAGE_LOCK=''
PARTIAL=''
STAGING=''
unlock() {
    if [ -n "$PARTIAL" ]; then rm -f -- "$PARTIAL" "$PARTIAL.sha256"; fi
    if [ -n "$PACKAGE_LOCK" ]; then rmdir "$PACKAGE_LOCK" 2>/dev/null || true; fi
    if [ -n "$LOCK" ]; then rmdir "$LOCK" 2>/dev/null || true; fi
    case "$STAGING" in /private/tmp/lens-dmg.??????) [ ! -L "$STAGING" ] && rm -rf -- "$STAGING" ;; esac
}
lock_outputs() {
    mkdir -p "$DD"
    safe_path "$DD/.lens-operation-lock"
    mkdir "$DD/.lens-operation-lock" 2>/dev/null || die 'Another Lens operation holds the output lock; inspect before removing a stale lock.'
    LOCK="$DD/.lens-operation-lock"
    trap unlock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    guard_running
}

xcvalue() {
    # Read literal assignments only; never source configuration as shell code.
    local file=$1 key=$2
    [ -f "$file" ] && [ ! -L "$file" ] || die 'Required xcconfig is missing or symlinked.'
    awk -v key="$key" '
        { sub(/\/\/.*$/, ""); if ($0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
            sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); value=$0; count++
        }}
        END { if (count != 1 || value == "") exit 1; print value }
    ' "$file" || die "Expected one literal $key assignment."
}

read_version() {
    VERSION=$(xcvalue "$ROOT/Config/Version.xcconfig" MARKETING_VERSION)
    BUILD_NUMBER=$(xcvalue "$ROOT/Config/Version.xcconfig" CURRENT_PROJECT_VERSION)
    CHANNEL=$(xcvalue "$ROOT/Config/Version.xcconfig" LENS_RELEASE_CHANNEL)
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Expected a numeric three-part marketing version.'
    [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || die 'Expected a positive integer build number.'
    [[ "$CHANNEL" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$ ]] || die 'Invalid release channel.'
}

require_xcode() {
    local version major minor
    version=$(xcodebuild -version | awk '/^Xcode / {print $2}')
    [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die 'Cannot identify the selected Xcode.'
    major=${version%%.*}; minor=${version#*.}; minor=${minor%%.*}
    (( major > 26 || (major == 26 && minor >= 4) )) || die 'Xcode 26.4 or newer is required.'
}

check_repo() {
    local file
    while IFS= read -r -d '' file; do bash -n "$file"; done < <(find "$ROOT/scripts" -type f -name '*.sh' -print0)
    git -C "$ROOT" diff --check
    git -C "$ROOT" diff --cached --check
    bash "$ROOT/scripts/repository-hygiene.sh"
    bash "$ROOT/scripts/tests/repository-hygiene.sh"
    bash "$ROOT/scripts/tests/regression.sh"
    python3 -B "$ROOT/scripts/tests/dmg-settings.py"
    python3 -B "$ROOT/scripts/tests/notarization.py"
    printf 'Lens checks passed.\n'
}

clean_outputs() {
    local name target
    local names=(Build CompilationCache.noindex Logs ModuleCache.noindex SDKStatCaches.noindex Index.noindex SourcePackages SwiftPM info.plist .DS_Store)
    # Preflight every exact target before deleting any. Never glob historical builds.
    for name in "${names[@]}"; do
        target="$DD/$name"
        safe_path "$target"
        # Child symlinks (including SwiftPM/debug) are unlinked by rm, never followed.
        # The target and every parent component must themselves be real paths.
    done
    guard_running
    for name in "${names[@]}"; do
        target="$DD/$name"
        safe_path "$target"
        if [ -e "$target" ]; then
            rm -rf -- "$target"
            printf 'Removed generated output: %s (not recoverable)\n' "$target"
        fi
    done
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }

minimum_os() {
    local version=$1 major minor
    [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die 'Cannot identify minimum macOS version.'
    major=${version%%.*}; minor=${version#*.}; minor=${minor%%.*}
    (( major > 26 || (major == 26 && minor >= 4) )) || die 'Minimum macOS must be 26.4 or newer.'
}

validate_app_metadata() {
    local executable minos supported_os plist_os
    [ -d "$APP/Contents/MacOS" ] && [ -f "$APP/Contents/Info.plist" ] || die 'Existing app bundle required; build separately.'
    safe_path "$APP/Contents/Info.plist"
    [ "$(plist_value CFBundleShortVersionString)" = "$VERSION" ] || die 'App marketing version does not match Version.xcconfig.'
    [ "$(plist_value CFBundleVersion)" = "$BUILD_NUMBER" ] || die 'App build number does not match Version.xcconfig.'
    [ "$(plist_value LensReleaseChannel)" = "$CHANNEL" ] || die 'App channel does not match Version.xcconfig.'
    [ "$(plist_value CFBundleExecutable)" = Lens ] || die 'Expected the Lens executable.'
    executable="$APP/Contents/MacOS/Lens"
    safe_path "$executable"
    [ -f "$executable" ] && [ -x "$executable" ] || die 'App executable is missing.'
    lipo "$executable" -verify_arch arm64 >/dev/null 2>&1 || die 'App must contain arm64.'
    supported_os=$(xcvalue "$ROOT/Config/Application.xcconfig" MACOSX_DEPLOYMENT_TARGET)
    minimum_os "$supported_os"
    plist_os=$(plist_value LSMinimumSystemVersion)
    minimum_os "$plist_os"
    [ "$plist_os" = "$supported_os" ] || [ "$plist_os" = "$supported_os.0" ] || die 'App minimum macOS does not match Application.xcconfig.'
    minos=$(xcrun vtool -arch arm64 -show-build "$executable" | awk '$1 == "minos" {print $2}')
    minimum_os "$minos"
    [ "$minos" = "$supported_os" ] || [ "$minos" = "$supported_os.0" ] || die 'Mach-O minimum macOS does not match Application.xcconfig.'
    safe_path "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
    [ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] || die 'Bundled PrivacyInfo.xcprivacy is required.'
    plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null || die 'Invalid bundled privacy manifest.'
}

validate_public_app() {
    local distribution_id product_id details assessment
    [ -s "$ROOT/LICENSE" ] && [ ! -L "$ROOT/LICENSE" ] || die 'Public packaging requires LICENSE.'
    [ -n "$CONFIRMED_ID" ] || die 'Public packaging requires --confirmed-distribution-id after user confirmation.'
    [[ "$CONFIRMED_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die 'Invalid confirmed distribution ID.'
    case "$CONFIRMED_ID" in dev.local.*|com.example.*|*PLACEHOLDER*|*PENDING*|*UNCONFIRMED*) die 'Placeholder/local distribution ID is not public-ready.' ;; esac
    distribution_id=$(xcvalue "$ROOT/Config/Distribution.xcconfig" LENS_DISTRIBUTION_BUNDLE_IDENTIFIER)
    product_id=$(xcvalue "$ROOT/Config/Distribution.xcconfig" PRODUCT_BUNDLE_IDENTIFIER)
    [ "$distribution_id" = "$CONFIRMED_ID" ] || die 'Confirmed ID does not match Distribution.xcconfig.'
    # Match Xcode's literal variable reference without evaluating it as shell code.
    # shellcheck disable=SC2016
    [ "$product_id" = "$CONFIRMED_ID" ] || [ "$product_id" = '$(LENS_DISTRIBUTION_BUNDLE_IDENTIFIER)' ] || die 'Distribution product ID does not match.'
    [ "$(plist_value CFBundleIdentifier)" = "$CONFIRMED_ID" ] || die 'App bundle ID does not match the confirmed distribution ID.'
    codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || die 'App signature verification failed.'
    details=$(codesign --display --verbose=4 "$APP" 2>&1) || die 'Cannot inspect app signature.'
    printf '%s\n' "$details" | grep -q '^Authority=Developer ID Application:' || die 'Developer ID Application signing is required.'
    printf '%s\n' "$details" | grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' || die 'A valid signing team is required.'
    printf '%s\n' "$details" | grep -Eq '^CodeDirectory .*flags=.*runtime' || die 'Hardened runtime is required.'
    assessment=$(spctl --assess --type execute --verbose=2 "$APP" 2>&1) || die 'Gatekeeper assessment failed.'
    printf '%s\n' "$assessment" | grep -q '^source=Notarized Developer ID$' || die 'Notarized Developer ID assessment is required.'
    xcrun stapler validate "$APP" >/dev/null 2>&1 || die 'Stapled notarization ticket validation failed.'
}

package_app() {
    # This command consumes an existing app and never builds or signs it.
    local suffix='' archive checksum dist="$ROOT/dist"
    read_version
    validate_app_metadata
    [ -s "$ROOT/LICENSE" ] && [ ! -L "$ROOT/LICENSE" ] || die 'Packaging requires LICENSE.'
    if [ "$DEVELOPMENT" = 1 ]; then
        suffix='-DEVELOPMENT-NOT-NOTARIZED'
        printf 'Development preview only; not validated for public distribution.\n'
    else
        validate_public_app
    fi
    safe_path "$dist"
    archive="$dist/Lens-$VERSION-$CHANNEL-$BUILD_NUMBER$suffix.$FORMAT"
    checksum="$archive.sha256"
    safe_path "$archive"; safe_path "$checksum"
    [ ! -e "$archive" ] && [ ! -e "$checksum" ] || die 'Package output already exists; refusing overwrite.'
    guard_running
    mkdir -p "$dist"
    safe_path "$dist/.lens-package-lock"
    mkdir "$dist/.lens-package-lock" 2>/dev/null || die 'Another package operation holds the dist lock.'
    PACKAGE_LOCK="$dist/.lens-package-lock"
    [ ! -e "$archive" ] && [ ! -e "$checksum" ] || die 'Package output already exists; refusing overwrite.'
    # No retained staging/build copies. ditto preserves bundle metadata and tickets.
    if [ "$FORMAT" = zip ]; then
        PARTIAL=$(mktemp "$dist/.lens-package.XXXXXX")
        ditto -c -k --sequesterRsrc --keepParent "$APP" "$PARTIAL"
        (cd "$ROOT" && zip -q "$PARTIAL" LICENSE)
    else
        command -v dmgbuild >/dev/null 2>&1 || die 'DMG packaging requires dmgbuild; see docs/dmg-installer.md.'
        safe_path "$ROOT/Packaging/background.tiff"
        [ -s "$ROOT/Packaging/background.tiff" ] || die 'DMG background is missing.'
        STAGING=$(mktemp -d /private/tmp/lens-dmg.XXXXXX)
        PARTIAL="$STAGING/Lens.dmg"
        dmgbuild -s "$ROOT/scripts/dmg-settings.py" -D root="$ROOT" -D app="$APP" \
            -D background="$ROOT/Packaging/background.tiff" Lens "$PARTIAL"
        hdiutil verify "$PARTIAL"
        printf 'DMG created; public DMGs must also be signed, notarized, and stapled before publication.\n'
    fi
    # Hash under the final basename so shasum -c works directly in dist.
    local digest
    digest=$(shasum -a 256 "$PARTIAL"); digest=${digest%% *}
    printf '%s  %s\n' "$digest" "${archive##*/}" > "$PARTIAL.sha256"
    mv "$PARTIAL.sha256" "$checksum"
    mv "$PARTIAL" "$archive"
    PARTIAL=''
    printf 'Created %s\nSHA256: %s\n' "$archive" "$checksum"
}

COMMAND=${1:-help}
if [ "$#" -gt 0 ]; then shift; fi
case "$COMMAND" in check|test|build|package|clean) ;; help|--help|-h) usage; exit 0 ;; *) die 'Unknown command.' ;; esac
DD="$ROOT/build-design"
APP=''; DEVELOPMENT=0; CONFIRMED_ID=''; INSTALLED=0; FORMAT=zip
while [ "$#" -gt 0 ]; do
    case "$1" in
        --derived-data|--app|--confirmed-distribution-id|--format)
            [ "$#" -ge 2 ] && [ -n "$2" ] || die 'Option requires a value.'
            case "$1" in
                --derived-data) DD=$2 ;;
                --app) [ "$COMMAND" = package ] || die '--app is package-only.'; APP=$2 ;;
                --confirmed-distribution-id) [ "$COMMAND" = package ] || die 'Distribution confirmation is package-only.'; CONFIRMED_ID=$2 ;;
                --format) [ "$COMMAND" = package ] || die 'Format is package-only.'; FORMAT=$2
                    case "$FORMAT" in zip|dmg) ;; *) die 'Format must be zip or dmg.' ;; esac ;;
            esac
            shift 2 ;;
        --development) [ "$COMMAND" = package ] || die '--development is package-only.'; DEVELOPMENT=1; shift ;;
        --installed-languages) [ "$COMMAND" = test ] || die '--installed-languages is test-only.'; INSTALLED=1; shift ;;
        *) die 'Unknown option.' ;;
    esac
done
[ "$DEVELOPMENT" = 0 ] || [ -z "$CONFIRMED_ID" ] || die 'Development and public confirmation options cannot be combined.'
validate_derived_data
if [ "$COMMAND" = check ]; then check_repo; exit 0; fi
if [ "$COMMAND" = package ]; then
    APP=${APP:-"$DD/Build/Products/Release/Lens.app"}
    safe_path "$APP"
    [ "${APP##*/}" = Lens.app ] || die 'Expected a Lens.app bundle.'
fi
guard_running
if [ "$COMMAND" = package ]; then
    # Packaging reads APP and writes only dist. A running canonical app must not
    # block packaging a different app, nor should packaging touch its DerivedData.
    trap unlock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
else
    lock_outputs
fi
case "$COMMAND" in
    test)
        safe_path "$DD/SwiftPM"
        require_xcode
        # The explicit option prevents accidental inherited opt-in in CI or shells.
        LENS_TEST_INSTALLED_LANGUAGES=$INSTALLED swift test --package-path "$ROOT" --scratch-path "$DD/SwiftPM" ;;
    build)
        safe_path "$DD/Build/Products/Release/Lens.app/Contents/MacOS/Lens"
        read_version
        require_xcode
        xcodebuild -project "$ROOT/Lens.xcodeproj" -scheme Lens -configuration Release \
            -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
            -xcconfig "$ROOT/Config/Version.xcconfig" \
            CODE_SIGN_STYLE=Manual PRODUCT_BUNDLE_IDENTIFIER=dev.local.lens \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
            LENS_RELEASE_CHANNEL="$CHANNEL" ARCHS=arm64 build ;;
    package) package_app ;;
    clean) clean_outputs ;;
esac
