#!/usr/bin/env bash
# Stamp a marker BEFORE strict mode so we can prove the script was invoked
# even if every line below fails. If this file is missing after pressing
# Run in Xcode, Xcode never called the pre-action (almost always: wrong
# scheme selected in the toolbar).
date > /tmp/zodsol-xcode-preaction-fired.txt 2>/dev/null || true

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Xcode buries pre-action stdout inside the Report Navigator and surfaces only
# a generic "Run action failed" toast on errors. Mirror everything to a stable
# log path so any failure is one `tail` away.
LOG="$ROOT/.build/xcode-preaction.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

printf '\n== xcode_package_preaction %s ==\n' "$(date '+%Y-%m-%d %H:%M:%S')"
trap 'rc=$?; printf "\nPre-action FAILED (exit %s). Full log: %s\n" "$rc" "$LOG" >&2; exit "$rc"' ERR

if pgrep -x ZODSol >/dev/null 2>&1; then
    osascript -e 'tell application "ZODSol" to quit' >/dev/null 2>&1 || true
    for _ in {1..30}; do
        if ! pgrep -x ZODSol >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    pkill -x ZODSol >/dev/null 2>&1 || true
fi

./Scripts/setup_local_signing.sh
ZODSOL_BUILD_CONFIGURATION=debug ./Scripts/package_app.sh
codesign --verify --deep --strict "$ROOT/ZODSol.app"

printf '\nPre-action OK. ZODSol.app ready at %s\n' "$ROOT/ZODSol.app"
