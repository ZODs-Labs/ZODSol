#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi

# Quiet macOS networking subsystem chatter (nw_*, Connection N, HTTP load
# failed) by default. Set ZODSOL_VERBOSE_LOGS=1 in your shell to opt back in
# when diagnosing transport issues.
if [[ "${ZODSOL_VERBOSE_LOGS:-0}" != "1" ]]; then
    export OS_ACTIVITY_MODE=disable
fi

pkill -x ZODSol >/dev/null 2>&1 || true
./Scripts/package_app.sh
exec "$ROOT/ZODSol.app/Contents/MacOS/ZODSol"
