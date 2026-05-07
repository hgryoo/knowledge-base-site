#!/usr/bin/env bash
# deploy.sh — local/LAN deploy of knowledge-base-site, supervised by
# a systemd --user service, with semi-hot rebuilds.
#
# Difference from scripts/serve-local.sh:
#   serve-local.sh    -> quartz dev server (file watcher, in-memory build).
#   deploy.sh         -> production-style. Builds public/ once, hands the
#                        static tree to a long-running python http.server
#                        managed by systemd --user. Updates ship via an
#                        explicit `./deploy.sh refresh` — re-pulls
#                        knowledge-base, rebuilds public/ in place, the
#                        running service picks the new files up on the
#                        next request. No file watcher; user-triggered.
#
# Subcommands:
#   install       create the systemd --user unit, enable+start it
#   uninstall     stop, disable, remove the unit
#   start         systemctl --user start
#   stop          systemctl --user stop
#   restart       systemctl --user restart  (clean restart, brief downtime)
#   refresh       prebuild + build into public/ WITHOUT restarting the
#                 service — semi-hot update, on the next HTTP request
#                 the service serves the new files
#   status        systemctl status + URLs
#   logs [N|-f]   journalctl --user-unit ...; pass -f to follow
#   build         prebuild + build only (no service interaction)
#   serve         (internal) what systemd ExecStart calls — exec http.server
#
# Env (read at install time and baked into the unit file):
#   PORT                 (default 9090) HTTP port to bind on 0.0.0.0
#   QUARTZ_LOCAL_FULL    (default 1) 1=full curated tree, 0=public subset
#   SERVICE_NAME         (default knowledge-base-site)
#
# After install, autostart at boot also requires:
#   loginctl enable-linger "$USER"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${PORT:-9090}"
export QUARTZ_LOCAL_FULL="${QUARTZ_LOCAL_FULL:-1}"
SERVICE_NAME="${SERVICE_NAME:-knowledge-base-site}"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/$SERVICE_NAME.service"

RUN_DIR="$SCRIPT_DIR/.deploy"
LOCK_FILE="$RUN_DIR/build.lock"
mkdir -p "$RUN_DIR"

require_systemd() {
  if ! systemctl --user status >/dev/null 2>&1; then
    echo "ERROR: systemd --user is not available in this session" >&2
    exit 1
  fi
}

unit_installed() {
  [[ -f "$UNIT_PATH" ]]
}

is_active() {
  systemctl --user is-active --quiet "$SERVICE_NAME.service"
}

# Serialize concurrent prebuild+build runs (install vs. refresh) so the
# public/ tree is never written by two processes at once.
do_build() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "another build is in progress; waiting..." >&2
    flock 9
  fi
  echo ">> prebuild (QUARTZ_LOCAL_FULL=$QUARTZ_LOCAL_FULL)"
  bash prebuild.sh
  echo ">> quartz build"
  npx quartz build
}

cmd_install() {
  require_systemd

  local python_bin
  python_bin="$(command -v python3 || true)"
  if [[ -z "$python_bin" ]]; then
    echo "ERROR: python3 not found; required for the static HTTP server" >&2
    exit 1
  fi

  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=knowledge-base-site local LAN deploy (port $PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
Environment=PORT=$PORT
Environment=QUARTZ_LOCAL_FULL=$QUARTZ_LOCAL_FULL
Environment=PYTHON_BIN=$python_bin
ExecStart=/bin/bash $SCRIPT_DIR/deploy.sh serve
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT

  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME.service" >/dev/null
  echo "installed: $UNIT_PATH"

  if [[ ! -d "$SCRIPT_DIR/public" ]]; then
    echo ">> initial build (public/ missing)"
    do_build
  fi

  systemctl --user restart "$SERVICE_NAME.service"
  sleep 1
  status_print

  if ! loginctl show-user "$USER" 2>/dev/null | grep -q '^Linger=yes$'; then
    echo
    echo "tip: enable boot-time autostart with:"
    echo "  loginctl enable-linger $USER"
  fi
}

cmd_uninstall() {
  require_systemd
  if unit_installed; then
    systemctl --user disable --now "$SERVICE_NAME.service" 2>/dev/null || true
    rm -f "$UNIT_PATH"
    systemctl --user daemon-reload
    echo "removed: $UNIT_PATH"
  else
    echo "no unit at $UNIT_PATH"
  fi
}

cmd_start() {
  require_systemd
  unit_installed || { echo "unit not installed; run: $0 install" >&2; exit 1; }
  if [[ ! -d "$SCRIPT_DIR/public" ]]; then
    echo ">> initial build (public/ missing)"
    do_build
  fi
  systemctl --user start "$SERVICE_NAME.service"
  sleep 1
  status_print
}

cmd_stop() {
  require_systemd
  systemctl --user stop "$SERVICE_NAME.service" || true
  echo "stopped."
}

cmd_restart() {
  require_systemd
  unit_installed || { echo "unit not installed; run: $0 install" >&2; exit 1; }
  systemctl --user restart "$SERVICE_NAME.service"
  sleep 1
  status_print
}

cmd_refresh() {
  require_systemd
  do_build
  if is_active; then
    echo "refresh complete; service '$SERVICE_NAME' continues to serve port $PORT (no restart needed)"
  else
    echo "refresh complete; service '$SERVICE_NAME' is not active. Start with: $0 start"
  fi
}

cmd_status() {
  if ! unit_installed; then
    echo "unit not installed (run: $0 install)"
    return
  fi
  systemctl --user --no-pager status "$SERVICE_NAME.service" || true
  echo
  status_print
}

status_print() {
  unit_installed || return 0
  local effective_port active ip_hint
  effective_port="$(systemctl --user show -p Environment "$SERVICE_NAME.service" \
                    | sed -n 's/.*PORT=\([0-9]\+\).*/\1/p')"
  effective_port="${effective_port:-$PORT}"
  active="$(systemctl --user is-active "$SERVICE_NAME.service" 2>/dev/null || true)"
  ip_hint="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  echo "service: $SERVICE_NAME ($active) port=$effective_port"
  echo "  local : http://localhost:$effective_port/"
  [[ -n "$ip_hint" ]] && echo "  LAN   : http://$ip_hint:$effective_port/"
  echo "  logs  : journalctl --user-unit $SERVICE_NAME -f"
}

cmd_logs() {
  require_systemd
  local arg="${1:-}"
  if [[ "$arg" == "-f" ]]; then
    exec journalctl --user-unit "$SERVICE_NAME.service" -f
  fi
  local n="${arg:-100}"
  exec journalctl --user-unit "$SERVICE_NAME.service" -n "$n" --no-pager
}

cmd_build_only() { do_build; }

# What systemd ExecStart calls. Foreground; execs http.server and stays
# in the foreground so systemd can supervise it. Builds on first start
# (when public/ is absent) so a fresh install or post-reboot start has
# something to serve, but does NOT rebuild on subsequent restarts —
# that's what `refresh` is for.
cmd_serve() {
  if [[ ! -d "$SCRIPT_DIR/public" ]]; then
    do_build
  fi
  cd "$SCRIPT_DIR/public"
  exec "${PYTHON_BIN:-python3}" -m http.server "$PORT" --bind 0.0.0.0
}

usage() { sed -n '2,38p' "$0"; }

case "${1:-status}" in
  install)        cmd_install ;;
  uninstall)      cmd_uninstall ;;
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  restart)        cmd_restart ;;
  refresh|reload) cmd_refresh ;;
  status)         cmd_status ;;
  logs)           shift || true; cmd_logs "${1:-100}" ;;
  build)          cmd_build_only ;;
  serve)          cmd_serve ;;
  -h|--help|help) usage ;;
  *)
    echo "unknown subcommand: $1" >&2
    usage >&2
    exit 2
    ;;
esac
