#!/usr/bin/env bash
# Build & serve the knowledge-base-site locally with full access to every
# curated doc under ../knowledge-base/knowledge.
#
# Differences from the GitHub Pages build:
#   - methodology/ folder is included (PRIVATE_EXCLUDES off)
#   - WhitelistPaths filter is skipped (every category is published)
#   - Quartz binds to all interfaces, so any host on the LAN/VPN can
#     reach it at http://<this-host-ip>:${PORT}/
#
# Usage:
#   ./scripts/serve-local.sh           # default port 8080
#   PORT=9090 ./scripts/serve-local.sh
#
# Stop with Ctrl-C.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

export QUARTZ_LOCAL_FULL=1
PORT="${PORT:-8080}"

bash prebuild.sh

ip_hint="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"

echo
echo "==============================================================="
echo "  knowledge-base-site — local-full mode"
echo "  port  : ${PORT}"
echo "  local : http://localhost:${PORT}/"
[[ -n "${ip_hint}" ]] && echo "  LAN   : http://${ip_hint}:${PORT}/"
echo "  Ctrl-C to stop."
echo "==============================================================="
echo

exec npx quartz build --serve --port "${PORT}"
