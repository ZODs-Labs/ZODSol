#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

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
