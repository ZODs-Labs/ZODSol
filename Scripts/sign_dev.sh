#!/usr/bin/env bash
#
# Re-sign a SwiftPM-built ZODSol binary with the project's entitlements
# plus `get-task-allow` (so Xcode can debug/launch the binary).
#
# Used as the shared ZODSol scheme's Build → PostActions step. Also runnable
# from the terminal: `Scripts/sign_dev.sh <path-to-binary>`.
#
# Background: Xcode's SwiftPM integration signs executables ad-hoc and does
# not apply `Sources/ZODSol/ZODSol.entitlements`. ZODSol needs both:
#   * `keychain-access-groups` (so the data-protection keychain accepts
#     writes; without it `SecItemAdd` returns errSecMissingEntitlement -34018
#     and wallet import fails)
#   * `get-task-allow` (so Xcode/lldb can attach; without it Xcode reports
#     "Build Succeeded" and then silently fails to launch)
#
# `keychain-access-groups` is a *restricted* entitlement on macOS Tahoe
# (26.x); AMFI refuses to load an ad-hoc-signed binary that carries it
# (Console: "The file is adhoc signed but contains restricted entitlements").
# So we cannot stay on `--sign -`. We instead reuse the project-local self-
# signed code-signing identity that `Scripts/setup_local_signing.sh` creates
# - that identity is allowed to carry restricted entitlements, the same way
# the release path in `Scripts/package_app.sh` does. If the identity is not
# present we abort with a clear instruction rather than silently falling
# back to a build the kernel will kill on launch.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE_ENTITLEMENTS="$ROOT/Sources/ZODSol/ZODSol.entitlements"
LOCAL_SIGNING_IDENTITY="ZODSol Local Code Signing"
LOCAL_SIGNING_KEYCHAIN="${ZODSOL_SIGNING_KEYCHAIN:-$HOME/.zodsol/zodsol-signing.keychain-db}"
LOCAL_SIGNING_PASSWORD_FILE="${ZODSOL_SIGNING_PASSWORD_FILE:-$HOME/.zodsol/zodsol-signing.pass}"

if [[ -n "${BUILT_PRODUCTS_DIR:-}" && -n "${EXECUTABLE_PATH:-}" ]]; then
    TARGET="$BUILT_PRODUCTS_DIR/$EXECUTABLE_PATH"
elif [[ $# -ge 1 ]]; then
    TARGET="$1"
else
    printf 'sign_dev.sh: missing target. Run from an Xcode scheme post-action or pass a path.\n' >&2
    exit 64
fi

if [[ ! -f "$TARGET" ]]; then
    printf 'sign_dev.sh: not a file: %s\n' "$TARGET" >&2
    exit 66
fi

if [[ ! -f "$BASE_ENTITLEMENTS" ]]; then
    printf 'sign_dev.sh: entitlements not found: %s\n' "$BASE_ENTITLEMENTS" >&2
    exit 66
fi

# Resolve the local signing identity using the same precedence as
# package_app.sh: explicit ZODSOL_SIGNING_IDENTITY env var, then the project
# keychain, then the user's default keychain.
SIGNING_IDENTITY="${ZODSOL_SIGNING_IDENTITY:-}"
CODESIGN_KEYCHAIN_ARGS=()
if [[ -z "$SIGNING_IDENTITY" ]]; then
    if [[ -f "$LOCAL_SIGNING_KEYCHAIN" ]]; then
        if [[ -f "$LOCAL_SIGNING_PASSWORD_FILE" ]]; then
            security unlock-keychain \
                -p "$(<"$LOCAL_SIGNING_PASSWORD_FILE")" \
                "$LOCAL_SIGNING_KEYCHAIN" >/dev/null
        fi
        SIGNING_IDENTITY=$(
            security find-identity -v -p codesigning "$LOCAL_SIGNING_KEYCHAIN" 2>/dev/null |
                awk -v name="\"${LOCAL_SIGNING_IDENTITY}\"" '$0 ~ name { print $2; exit }'
        )
        if [[ -n "$SIGNING_IDENTITY" ]]; then
            CODESIGN_KEYCHAIN_ARGS=(--keychain "$LOCAL_SIGNING_KEYCHAIN")
        fi
    fi

    if [[ -z "$SIGNING_IDENTITY" ]] &&
        security find-identity -v -p codesigning 2>/dev/null |
            grep -Fq "\"${LOCAL_SIGNING_IDENTITY}\""
    then
        SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY"
    fi
fi

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    cat >&2 <<EOF
sign_dev.sh: no local code-signing identity found.

ZODSol's entitlements include 'keychain-access-groups', which AMFI on macOS
Tahoe refuses to honor on ad-hoc-signed binaries. The Xcode Run build
would compile fine then be killed by the kernel on launch.

Run this once to create a self-signed local identity:

    ./Scripts/setup_local_signing.sh

Then press Run in Xcode again.
EOF
    exit 70
fi

# Layer entitlements: ZODSol.entitlements + get-task-allow. PlistBuddy
# tolerates dotted entitlement keys cleanly (its path separator is `:`).
TEMP_ENTITLEMENTS=$(mktemp -t zodsol-dev-entitlements.XXXXXX)
trap 'rm -f "$TEMP_ENTITLEMENTS"' EXIT
cp "$BASE_ENTITLEMENTS" "$TEMP_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$TEMP_ENTITLEMENTS" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :com.apple.security.get-task-allow true" "$TEMP_ENTITLEMENTS"

# Pin the same signing identifier `Scripts/package_app.sh` uses so the
# Designated Requirement is byte-identical across the Xcode and packaged
# builds. The keychain ACL is keyed by DR; without this, the Xcode-built
# binary would default its identifier to `ZODSol` (the SwiftPM product
# name) while the .app bundle reports `dev.zods.zodsol`, and the file
# keychain would treat them as two different apps - exactly the
# "ZODSol wants to use your confidential information" password prompt
# the wallet UX must avoid.
codesign \
    --force \
    --identifier dev.zods.zodsol \
    --options runtime \
    "${CODESIGN_KEYCHAIN_ARGS[@]}" \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$TEMP_ENTITLEMENTS" \
    "$TARGET" >/dev/null

codesign --verify --verbose=1 "$TARGET" 2>&1 | sed 's/^/sign_dev: /'
printf 'sign_dev: re-signed %s with %s + get-task-allow (identity: %s)\n' \
    "$TARGET" "$(basename "$BASE_ENTITLEMENTS")" "$LOCAL_SIGNING_IDENTITY"
