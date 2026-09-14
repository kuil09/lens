#!/bin/bash
# No Xcode/Swift invocation, app execution, real signing, or notarization submission.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
FIXTURES="$HERE/fixtures"
WORK=$(mktemp -d /private/tmp/lens-shell-regression.XXXXXX)
ALT=$(mktemp -d /private/tmp/lens-derived-data.XXXXXX)
cleanup() {
    # Only the two unique directories created by this test run are disposable.
    case "$WORK" in /private/tmp/lens-shell-regression.??????) [ ! -L "$WORK" ] && rm -rf -- "$WORK" ;; esac
    case "$ALT" in /private/tmp/lens-derived-data.??????) [ ! -L "$ALT" ] && rm -rf -- "$ALT" ;; esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
REPO="$WORK/Repo with spaces"
mkdir -p "$REPO/scripts" "$REPO/Config" "$WORK/bin"
cp "$HERE/../lens.sh" "$REPO/scripts/lens.sh"
cp "$FIXTURES/Version.xcconfig" "$FIXTURES/Distribution.xcconfig" "$FIXTURES/Application.xcconfig" "$REPO/Config/"
# A fixture license is sufficient to exercise presence/packaging; never a release.
cp "$FIXTURES/Version.xcconfig" "$REPO/LICENSE"
for tool in ps xcodebuild swift lipo xcrun codesign spctl; do
    cp "$FIXTURES/mock-tool.sh" "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done
export PATH="$WORK/bin:$PATH"
export MOCK_UNEXPECTED="$WORK/unexpected-compilation"
export MOCK_RUNNING='' MOCK_FAIL='' MOCK_PS_FAILURE=0
DD="$REPO/build-design"
APP="$DD/Build/Products/Release/Lens.app"
export MOCK_EXPECTED_EXECUTABLE="$APP/Contents/MacOS/Lens"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$FIXTURES/Info.plist" "$APP/Contents/Info.plist"
cp "$FIXTURES/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$FIXTURES/mock-tool.sh" "$APP/Contents/MacOS/Lens"
chmod +x "$APP/Contents/MacOS/Lens"
SCRIPT="$REPO/scripts/lens.sh"
COUNT=0
expect_fail() {
    local message=$1
    shift
    if bash "$SCRIPT" "$@" > "$WORK/result" 2>&1; then
        printf 'FAIL: expected refusal (%s)\n' "$message" >&2; exit 1
    fi
    if ! grep -Fq "$message" "$WORK/result"; then
        printf 'FAIL: wrong refusal; expected %s\n' "$message" >&2
        cat "$WORK/result" >&2; exit 1
    fi
    COUNT=$((COUNT + 1))
}
# The previous CLI order must be rejected, even with a valid executable path.
if lipo -verify_arch arm64 "$MOCK_EXPECTED_EXECUTABLE" > "$WORK/result" 2>&1; then
    printf 'FAIL: lipo mock accepted the incorrect argument order\n' >&2; exit 1
else
    test "$?" -eq 99
fi
COUNT=$((COUNT + 1))
expect_fail 'Unknown command' unknown
expect_fail 'Unknown option' clean --force
expect_fail 'Option requires a value' clean --derived-data
expect_fail 'Unsafe path' clean --derived-data /
expect_fail 'Unknown DerivedData location' clean --derived-data "$REPO"
expect_fail 'Unknown DerivedData location' clean --derived-data "$REPO/build-old"
expect_fail 'Unsafe path' clean --derived-data "$DD/../build-design"
expect_fail 'Paths must be absolute' clean --derived-data build-design
expect_fail 'Use a dedicated mktemp' clean --derived-data /private/tmp/not-a-build
ln -s "$DD" "$WORK/link"
expect_fail 'Symlink paths' clean --derived-data "$WORK/link"

export MOCK_RUNNING="$APP/Contents/MacOS/Lens"
for command in build clean; do expect_fail 'A process is running' "$command"; done
expect_fail 'selected app is running' package
test -f "$APP/Contents/Info.plist"
# A running canonical app must not block an independent temporary tree.
bash "$SCRIPT" clean --derived-data "$ALT" > "$WORK/result" 2>&1
COUNT=$((COUNT + 1))
expect_fail 'selected app is running' package --derived-data "$ALT" --app "$APP"
export MOCK_RUNNING='' MOCK_PS_FAILURE=1
for command in build package clean; do expect_fail 'Cannot inspect processes' "$command"; done
export MOCK_PS_FAILURE=0

mkdir -p "$DD/.lens-operation-lock"
expect_fail 'holds the output lock' clean
rmdir "$DD/.lens-operation-lock"
ln -s "$WORK" "$DD/Logs"
expect_fail 'Symlink paths' clean
rm "$DD/Logs"
ln -s "$WORK" "$APP/Contents/MacOS/escape"
# Metadata path protection is checked without invoking any build tool.
mv "$APP/Contents/MacOS/Lens" "$WORK/executable"
ln -s "$WORK/executable" "$APP/Contents/MacOS/Lens"
expect_fail 'Symlink paths' build
rm "$APP/Contents/MacOS/Lens" "$APP/Contents/MacOS/escape"
mv "$WORK/executable" "$APP/Contents/MacOS/Lens"

expect_fail 'requires --confirmed-distribution-id' package
expect_fail 'Placeholder/local' package --confirmed-distribution-id dev.local.lens
expect_fail 'does not match Distribution' package --confirmed-distribution-id org.other.lens
mv "$REPO/LICENSE" "$WORK/license"
expect_fail 'requires LICENSE' package --confirmed-distribution-id org.lens.regression
mv "$WORK/license" "$REPO/LICENSE"
cp "$FIXTURES/Version.xcconfig" "$REPO/Config/Distribution.xcconfig"
expect_fail 'Expected one literal LENS_DISTRIBUTION' package --confirmed-distribution-id org.lens.regression
cp "$FIXTURES/Distribution.xcconfig" "$REPO/Config/Distribution.xcconfig"

for field in CFBundleShortVersionString CFBundleVersion LensReleaseChannel; do
    /usr/libexec/PlistBuddy -c "Set :$field wrong" "$APP/Contents/Info.plist"
    expect_fail 'does not match Version.xcconfig' package --development
    cp "$FIXTURES/Info.plist" "$APP/Contents/Info.plist"
done
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 26.3' "$APP/Contents/Info.plist"
expect_fail 'Minimum macOS' package --development
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 26.5' "$APP/Contents/Info.plist"
expect_fail 'minimum macOS does not match Application' package --development
cp "$FIXTURES/Info.plist" "$APP/Contents/Info.plist"
mv "$APP/Contents/Resources/PrivacyInfo.xcprivacy" "$WORK/privacy"
expect_fail 'Bundled PrivacyInfo' package --development
mv "$WORK/privacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
for gate in arm64 minos minos-newer signature authority runtime assessment notarization staple; do
    export MOCK_FAIL=$gate
    case "$gate" in
        arm64) message='must contain arm64' ;;
        minos) message='Minimum macOS' ;;
        minos-newer) message='Mach-O minimum macOS does not match Application' ;;
        signature) message='signature verification failed' ;;
        authority) message='Developer ID Application signing' ;;
        runtime) message='Hardened runtime' ;;
        assessment) message='Gatekeeper assessment failed' ;;
        notarization) message='Notarized Developer ID assessment' ;;
        staple) message='Stapled notarization ticket' ;;
    esac
    expect_fail "$message" package --confirmed-distribution-id org.lens.regression
    test ! -d "$REPO/dist"
done
export MOCK_FAIL=''

# Real ZIP/SHA operations on a fake app test contents, never public authenticity.
bash "$SCRIPT" package --development > "$WORK/result" 2>&1
PREVIEW="$REPO/dist/Lens-0.1.0-beta.1-1-DEVELOPMENT-NOT-NOTARIZED.zip"
unzip -Z1 "$PREVIEW" | grep -qx LICENSE
unzip -Z1 "$PREVIEW" | grep -qx Lens.app/Contents/Info.plist
(cd "$REPO/dist" && shasum -a 256 -c "${PREVIEW##*/}.sha256") > "$WORK/result"
expect_fail 'refusing overwrite' package --development
COUNT=$((COUNT + 1))
mkdir -p "$ALT/Build" "$ALT/Unrelated" "$ALT/SwiftPM/arm64-apple-macosx/debug" "$REPO/build-historical"
cp "$FIXTURES/Info.plist" "$ALT/Build/generated.plist"
cp "$FIXTURES/Info.plist" "$ALT/Unrelated/keep.plist"
ln -s arm64-apple-macosx/debug "$ALT/SwiftPM/debug"
ln -s "$ALT/Unrelated" "$ALT/Build/external-link"
bash "$SCRIPT" clean --derived-data "$ALT" > "$WORK/result" 2>&1
test ! -e "$ALT/Build"
test ! -e "$ALT/SwiftPM"
test -f "$ALT/Unrelated/keep.plist"
test -d "$REPO/build-historical"
test -f "$PREVIEW"
test -f "$APP/Contents/Info.plist"
# Explicit --app works while another app in the canonical tree is running.
mkdir -p "$WORK/External app"
cp -R "$APP" "$WORK/External app/Lens.app"
export MOCK_RUNNING="$APP/Contents/MacOS/Lens"
export MOCK_EXPECTED_EXECUTABLE="$WORK/External app/Lens.app/Contents/MacOS/Lens"
expect_fail 'refusing overwrite' package --development --app "$WORK/External app/Lens.app"
export MOCK_EXPECTED_EXECUTABLE="$APP/Contents/MacOS/Lens"
export MOCK_RUNNING=''
# The single dist lock serializes package attempts from different DerivedData.
rm "$PREVIEW" "$PREVIEW.sha256"
mkdir "$REPO/dist/.lens-package-lock"
expect_fail 'holds the dist lock' package --development --derived-data "$ALT" --app "$APP"
rmdir "$REPO/dist/.lens-package-lock"
test ! -e "$MOCK_UNEXPECTED"
COUNT=$((COUNT + 1))
printf 'Shell regressions passed (%s assertions; mocked process/signature metadata, no compilation or notarization).\n' "$COUNT"
