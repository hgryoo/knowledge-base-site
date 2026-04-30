#!/usr/bin/env bash
# One-time setup for the local LAN deployment of knowledge-base-site.
#
# Verifies prerequisites (Node 22+, npm, python3, rsync), then runs
# `npm ci`. After this completes, run:
#
#   ./scripts/serve-local.sh        # serves on http://0.0.0.0:${PORT:-8080}
#
# The local serve reads markdown from a sibling clone of knowledge-base:
#   <parent>/knowledge-base-site/   ← this repo
#   <parent>/knowledge-base/        ← content tree
#
# Override that path with SRC=... when invoking serve-local.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

err=0

check_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "MISSING: $cmd"
    echo "  -> $hint"
    err=1
  else
    echo "OK     : $cmd ($("$cmd" --version 2>/dev/null | head -1))"
  fi
}

echo "Checking prerequisites..."
check_cmd node    "install Node.js >=22 (recommended: nvm install 22)"
check_cmd npm     "ships with Node.js"
check_cmd python3 "install python3 (sudo apt install python3 / brew install python)"
check_cmd rsync   "install rsync   (sudo apt install rsync   / brew install rsync)"

if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  if (( node_major < 22 )); then
    echo "MISSING: Node.js >=22 (current: $(node -v))"
    echo "  -> nvm install 22 && nvm use 22"
    err=1
  fi
fi

if (( err )); then
  echo
  echo "Install the missing prerequisites listed above, then re-run ./install.sh"
  exit 1
fi

echo
echo "Installing npm dependencies (npm ci)..."
npm ci

SIBLING="$SCRIPT_DIR/../knowledge-base/knowledge"
if [[ ! -d "$SIBLING" ]]; then
  echo
  echo "WARNING: expected sibling content tree at $SIBLING — not found."
  echo "  Either clone knowledge-base alongside this repo, or pass SRC=... to"
  echo "  scripts/serve-local.sh (e.g. SRC=/path/to/knowledge ./scripts/serve-local.sh)."
fi

echo
echo "Done."
echo "  Start the local server:  ./scripts/serve-local.sh"
echo "  Custom port            :  PORT=9090 ./scripts/serve-local.sh"
