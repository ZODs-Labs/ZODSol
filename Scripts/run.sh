#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Load developer-only env vars (e.g. ZODSOL_HELIUS_API_KEY) so the launched
# binary inherits them. The file is gitignored and never read in production
# builds; missing file is the normal case once secrets live in the Keychain.
if [[ -f "$ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi

pkill -x ZODSol >/dev/null 2>&1 || true
./Scripts/package_app.sh
exec "$ROOT/ZODSol.app/Contents/MacOS/ZODSol"
