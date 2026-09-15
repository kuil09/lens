#!/bin/bash
# These mocks are installed only inside a disposable regression repository.
set -euo pipefail
tool=${0##*/}
case "$tool" in
    ps)
        [ "${MOCK_PS_FAILURE:-0}" = 0 ] || exit 1
        printf '/sbin/launchd\n'
        if [ -n "${MOCK_RUNNING:-}" ]; then printf '%s\n' "$MOCK_RUNNING"; fi ;;
    lipo)
        if [ "$#" -ne 3 ] || [ "${1:-}" != "${MOCK_EXPECTED_EXECUTABLE:?}" ] ||
            [ "${2:-}" != -verify_arch ] || [ "${3:-}" != arm64 ]; then
            printf 'Unexpected lipo arguments\n' >&2
            exit 99
        fi
        [ "${MOCK_FAIL:-}" != arm64 ] ;;
    xcrun)
        case "${1:-}" in
            vtool)
                case "${MOCK_FAIL:-}" in
                    minos) printf '    minos 26.3\n' ;;
                    minos-newer) printf '    minos 26.5\n' ;;
                    *) printf '    minos 26.4\n' ;;
                esac ;;
            stapler)
                [ "${2:-}" = validate ] || exit 99
                [ "${MOCK_FAIL:-}" != staple ] ;;
            *) printf 'Unexpected xcrun operation\n' >&2; exit 99 ;;
        esac ;;
    codesign)
        case "${1:-}" in
            --verify) [ "${MOCK_FAIL:-}" != signature ] ;;
            --display)
                if [ "${MOCK_FAIL:-}" = authority ]; then printf 'Signature=adhoc\n'; exit 0; fi
                printf 'Authority=Developer ID Application: Regression Fixture (ABCDEFGHIJ)\nTeamIdentifier=ABCDEFGHIJ\n'
                if [ "${MOCK_FAIL:-}" != runtime ]; then printf 'CodeDirectory v=20500 flags=0x10000(runtime)\n'; fi ;;
            *) printf 'Signing is forbidden in regressions\n' >&2; exit 99 ;;
        esac ;;
    spctl)
        [ "${MOCK_FAIL:-}" != assessment ] || exit 1
        if [ "${MOCK_FAIL:-}" = notarization ]; then printf 'source=Developer ID\n'; else printf 'source=Notarized Developer ID\n'; fi ;;
    xcodebuild|swift)
        printf '%s\n' "$tool" >> "$MOCK_UNEXPECTED"
        printf 'Compilation tools are forbidden in shell regressions\n' >&2
        exit 99 ;;
    *) printf 'Unknown mock\n' >&2; exit 99 ;;
esac
