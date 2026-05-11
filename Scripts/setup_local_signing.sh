#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${ZODSOL_LOCAL_SIGNING_IDENTITY:-ZODSol Local Code Signing}"
CONFIG_DIR="${ZODSOL_CONFIG_DIR:-$HOME/.zodsol}"
KEYCHAIN="${ZODSOL_SIGNING_KEYCHAIN:-$CONFIG_DIR/zodsol-signing.keychain-db}"
PASSWORD_FILE="$CONFIG_DIR/zodsol-signing.pass"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zodsol-signing.XXXXXX")

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

if [[ "${ZODSOL_RESET_LOCAL_SIGNING:-0}" == "1" && -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -f "$PASSWORD_FILE"
fi

if [[ ! -f "$PASSWORD_FILE" ]]; then
    openssl rand -base64 32 > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi
KEYCHAIN_PASSWORD=$(<"$PASSWORD_FILE")

if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null

mapfile -t CURRENT_KEYCHAINS < <(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/^"//' -e 's/"$//')
FOUND_KEYCHAIN=0
for current in "${CURRENT_KEYCHAINS[@]}"; do
    if [[ "$current" == "$KEYCHAIN" ]]; then
        FOUND_KEYCHAIN=1
        break
    fi
done
if [[ "$FOUND_KEYCHAIN" == "0" ]]; then
    security list-keychains -d user -s "$KEYCHAIN" "${CURRENT_KEYCHAINS[@]}" >/dev/null
fi

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -Fq "\"${IDENTITY_NAME}\""; then
    printf 'Local signing identity already exists: %s\n' "$IDENTITY_NAME"
    printf 'Keychain: %s\n' "$KEYCHAIN"
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    printf 'openssl is required to create the local signing identity.\n' >&2
    exit 1
fi

KEY_PEM="$TMP_DIR/zodsol-local-signing.key.pem"
CERT_PEM="$TMP_DIR/zodsol-local-signing.cert.pem"
P12="$TMP_DIR/zodsol-local-signing.p12"
P12_PASSWORD="zodsol-local-signing"

openssl req \
    -new \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -nodes \
    -days 3650 \
    -subj "/CN=${IDENTITY_NAME}/" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$KEY_PEM" \
    -out "$CERT_PEM" >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -legacy \
    -name "$IDENTITY_NAME" \
    -inkey "$KEY_PEM" \
    -in "$CERT_PEM" \
    -out "$P12" \
    -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

security import "$P12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$CERT_PEM" >/dev/null

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

printf 'Created local signing identity: %s\n' "$IDENTITY_NAME"
printf 'Keychain: %s\n' "$KEYCHAIN"
printf 'Future package builds will reuse this identity automatically.\n'
