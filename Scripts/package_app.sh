#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Versioning sourced from version.env so we have a single place to bump.
MARKETING_VERSION="0.1.0"
BUILD_NUMBER="1"
if [[ -f "$ROOT/version.env" ]]; then
    # shellcheck disable=SC1090
    source "$ROOT/version.env"
fi

YEAR=$(date +%Y)
MIN_MACOS="14.0"
BUNDLE_ID="dev.zods.zodsol"
APP_NAME="ZODSol"
BUILD_CONFIGURATION="${ZODSOL_BUILD_CONFIGURATION:-release}"
LOCAL_SIGNING_IDENTITY="ZODSol Local Code Signing"
LOCAL_SIGNING_KEYCHAIN="${ZODSOL_SIGNING_KEYCHAIN:-$HOME/.zodsol/zodsol-signing.keychain-db}"
LOCAL_SIGNING_PASSWORD_FILE="${ZODSOL_SIGNING_PASSWORD_FILE:-$HOME/.zodsol/zodsol-signing.pass}"

case "$BUILD_CONFIGURATION" in
    debug)
        SWIFT_BUILD_ARGS=()
        ;;
    release)
        SWIFT_BUILD_ARGS=(-c release)
        ;;
    *)
        printf 'Unsupported ZODSOL_BUILD_CONFIGURATION: %s\n' "$BUILD_CONFIGURATION" >&2
        printf 'Expected "debug" or "release".\n' >&2
        exit 1
        ;;
esac

swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)
APP="$ROOT/${APP_NAME}.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_DIR/${APP_NAME}" "$MACOS/${APP_NAME}"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© ${YEAR} ZODs.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    SIGNING_IDENTITY="${ZODSOL_SIGNING_IDENTITY:-}"
    CODESIGN_KEYCHAIN_ARGS=()
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        if [[ -f "$LOCAL_SIGNING_KEYCHAIN" ]]; then
            if [[ -f "$LOCAL_SIGNING_PASSWORD_FILE" ]]; then
                security unlock-keychain -p "$(<"$LOCAL_SIGNING_PASSWORD_FILE")" "$LOCAL_SIGNING_KEYCHAIN" >/dev/null
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
            security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"${LOCAL_SIGNING_IDENTITY}\""; then
            SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY"
        fi

        if [[ -z "$SIGNING_IDENTITY" ]]; then
            SIGNING_IDENTITY="-"
        else
            :
        fi
    fi

    CODESIGN_ARGS=(--force --options runtime "${CODESIGN_KEYCHAIN_ARGS[@]}" --sign "$SIGNING_IDENTITY")

    # Homebrew/local builds do not have a Developer ID provisioning profile, so
    # do not sandbox by default. Sandboxed Keychain access needs matching
    # signing entitlements that ad-hoc/Homebrew builds cannot reliably provide.
    if [[ "${ZODSOL_ENABLE_SANDBOX:-0}" == "1" ]]; then
        CODESIGN_ARGS+=(--entitlements "$ROOT/Sources/ZODSol/ZODSol.entitlements")
    fi

    codesign "${CODESIGN_ARGS[@]}" "$APP" >/dev/null
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        printf 'Signed with ad-hoc identity. Run Scripts/setup_local_signing.sh once for persistent Keychain trust.\n'
    else
        printf 'Signed with identity: %s\n' "$SIGNING_IDENTITY"
    fi
fi

printf 'Created %s (v%s build %s)\n' "$APP" "$MARKETING_VERSION" "$BUILD_NUMBER"
