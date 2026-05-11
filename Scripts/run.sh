#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

pkill -x ZODSol >/dev/null 2>&1 || true
./Scripts/package_app.sh
exec "$ROOT/ZODSol.app/Contents/MacOS/ZODSol"
