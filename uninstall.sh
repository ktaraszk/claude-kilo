#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
keys="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kilo"
case "$(uname)" in
  Darwin)
    for job in reload proxy; do
      launchctl bootout "gui/$(id -u)/claude-kilo.$job" 2>/dev/null
      rm -f "$HOME/Library/LaunchAgents/claude-kilo.$job.plist"
    done
    ;;
  Linux)
    if command -v systemctl >/dev/null; then
      systemctl --user disable --now claude-kilo.reload.path claude-kilo.proxy.service claude-kilo.reload.service 2>/dev/null
    fi
    units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    rm -f "$units/claude-kilo.proxy.service" "$units/claude-kilo.reload.service" "$units/claude-kilo.reload.path"
    if command -v systemctl >/dev/null; then
      systemctl --user daemon-reload 2>/dev/null
      systemctl --user reset-failed claude-kilo.proxy.service claude-kilo.reload.service 2>/dev/null
    fi
    ;;
esac
link="${CLAUDE_KILO_BIN_DIR:-$HOME/.local/bin}/claude-kilo"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$root/bin/claude-kilo" ]; then
  rm -f "$link"
fi
echo "removed autostart and the claude-kilo command"
echo "kept $root (config, venv, logs) and $keys (keys); delete them yourself if you no longer need them"
