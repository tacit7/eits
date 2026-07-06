#!/usr/bin/env bash
# Build the Pi harness sidecar into priv/bin/.
# Usage: scripts/build-pi-harness.sh [--skip-typecheck]
set -euo pipefail
cd "$(dirname "$0")/.."

command -v bun >/dev/null || { echo "error: bun not found on PATH (install: https://bun.sh)"; exit 1; }

pushd pi-harness >/dev/null
bun install --frozen-lockfile
if [[ "${1:-}" != "--skip-typecheck" ]]; then
  bun run typecheck
fi
popd >/dev/null

mkdir -p priv/bin/pi
bun build pi-harness/src/main.ts --compile --outfile priv/bin/eits-pi-harness
chmod +x priv/bin/eits-pi-harness
cp pi-harness/node_modules/@earendil-works/pi-coding-agent/package.json priv/bin/pi/package.json
echo "built priv/bin/eits-pi-harness"
