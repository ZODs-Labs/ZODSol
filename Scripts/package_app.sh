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

# SwiftPM emits a `<Target>_<Name>.bundle/` per library target that declares
# resources. The standard macOS .app layout requires everything to live inside
# Contents/, so we flatten each bundle's payload into Contents/Resources/.
# `BundledAssetLogos` looks there via `Bundle.main` when its `Bundle.module`
# fast path returns nil (which happens in packaged builds because the
# generated accessor expects the bundle at the .app root - a location
# codesign rejects as "unsealed contents present in the bundle root").
# The per-bundle Info.plist is dropped to avoid colliding with the .app's
# own metadata files.
shopt -s nullglob
for resource_bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    find "$resource_bundle" -mindepth 1 -maxdepth 1 \
        ! -name 'Info.plist' \
        -exec cp -R {} "$RESOURCES/" \;
done
shopt -u nullglob

# App icon: build AppIcon.icns from the 1024 master so Finder, Spotlight and
# the Cmd-Tab switcher show the brand mark (the menu-bar PNG is display-only and
# too small to serve as an app icon). Regenerate the master with
# `swift Scripts/make_app_icon.swift <mark.png> Design/AppIcon.png`, or drop a
# hand-designed 1024x1024 PNG at Design/AppIcon.png. Skipped if the master is
# absent so the build never hard-fails on a missing design asset.
ICON_MASTER="$ROOT/Design/AppIcon.png"
if [[ -f "$ICON_MASTER" ]] && command -v iconutil >/dev/null 2>&1; then
    ICONSET_PARENT=$(mktemp -d)
    ICONSET="$ICONSET_PARENT/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x \
        128:128x128 256:128x128@2x 256:256x256 512:256x256@2x \
        512:512x512 1024:512x512@2x; do
        px="${spec%%:*}"
        label="${spec##*:}"
        sips -z "$px" "$px" "$ICON_MASTER" --out "$ICONSET/icon_${label}.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
    rm -rf "$ICONSET_PARENT"
    printf 'Generated AppIcon.icns from %s\n' "$ICON_MASTER"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

    # Entitlements are always applied. The file declares `network.client`
    # (Helius + Jupiter) and `keychain-access-groups` (required by the
    # data-protection keychain even for single-app, non-shared items - without
    # this the first `SecItemAdd` returns errSecMissingEntitlement -34018 on
    # ad-hoc-signed builds). No sandbox entitlement is set, matching the
    # Homebrew/ad-hoc distribution stance documented in CLAUDE.md.
    CODESIGN_ARGS+=(--entitlements "$ROOT/Sources/ZODSol/ZODSol.entitlements")

    codesign "${CODESIGN_ARGS[@]}" "$APP" >/dev/null
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        printf 'Signed with ad-hoc identity. Run Scripts/setup_local_signing.sh once for persistent Keychain trust.\n'
    else
        printf 'Signed with identity: %s\n' "$SIGNING_IDENTITY"
    fi
fi

printf 'Created %s (v%s build %s)\n' "$APP" "$MARKETING_VERSION" "$BUILD_NUMBER"
