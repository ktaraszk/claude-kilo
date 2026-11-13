#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
keys="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kilo"
if [ "$(uname)" = Darwin ]; then
  for job in reload proxy; do
    launchctl bootout "gui/$(id -u)/claude-kilo.$job" 2>/dev/null
    rm -f "$HOME/Library/LaunchAgents/claude-kilo.$job.plist"
  done
fi
link="${CLAUDE_KILO_BIN_DIR:-$HOME/.local/bin}/claude-kilo"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$root/bin/claude-kilo" ]; then
  rm -f "$link"
fi
echo "removed autostart and the claude-kilo command"
echo "kept $root (config, venv, logs) and $keys (keys); delete them yourself if you no longer need them"
