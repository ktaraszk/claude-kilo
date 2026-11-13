#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
keys="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kilo"
litellm_version="${LITELLM_VERSION:-1.106.6}"
py="${PYTHON:-python3}"
bin_dir="${CLAUDE_KILO_BIN_DIR:-$HOME/.local/bin}"
mode=""
org_id="${KILO_ORG_ID:-}"
autostart=""

usage() {
  cat <<EOF
usage: ./install.sh [--personal | --org <organization-id>] [--autostart | --no-autostart]

  --personal          bill your personal Kilo balance
  --org <id>          bill a Kilo organization (you must be a member)
  --autostart         start the proxy at login, restart it if it dies, reload on config change (macOS)
  --no-autostart      skip that; start the proxy yourself with bin/claude-kilo-proxy

Non-interactive: set KILO_API_KEY (and KILO_ORG_ID) in the environment.
EOF
}

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
ask() { local a; read -r -p "$1 " a; printf '%s' "$a"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --personal) mode=personal; org_id="" ;;
    --org) mode=organization; org_id="${2:-}"; [ -n "$org_id" ] || die "--org needs an organization id"; shift ;;
    --org=*) mode=organization; org_id="${1#--org=}" ;;
    --autostart) autostart=yes ;;
    --no-autostart) autostart=no ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v claude >/dev/null || die "Claude Code (claude) is not installed"
command -v curl >/dev/null || die "curl is required"
command -v openssl >/dev/null || die "openssl is required"
"$py" -c 'import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] < (3, 15) else 1)' 2>/dev/null \
  || die "Python 3.10 to 3.14 is required (point PYTHON at one)"

if [ -z "$mode" ] && [ ! -f "$root/config.yaml" ]; then
  [ -t 0 ] || die "choose --personal or --org <organization-id>"
  echo "Who pays for the requests?"
  echo "  1) my personal Kilo account"
  echo "  2) a Kilo organization (company)"
  case "$(ask 'Choice [1/2]:')" in
    1) mode=personal ;;
    2) mode=organization ;;
    *) die "pick 1 or 2" ;;
  esac
fi
if [ "$mode" = organization ] && [ -z "$org_id" ]; then
  [ -t 0 ] || die "--org needs an organization id"
  org_id="$(ask 'Kilo organization ID (UUID):')"
fi
if [ -n "$org_id" ] && ! [[ "$org_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  die "organization id should be a UUID, got: $org_id"
fi

say "LiteLLM $litellm_version in $root/.venv"
[ -x "$root/.venv/bin/python" ] || "$py" -m venv "$root/.venv"
installed="$("$root/.venv/bin/python" -c 'import importlib.metadata as m; print(m.version("litellm"))' 2>/dev/null || true)"
if [ "$installed" != "$litellm_version" ]; then
  "$root/.venv/bin/pip" install -q --upgrade pip
  "$root/.venv/bin/pip" install -q "litellm[proxy]==$litellm_version" \
    || "$root/.venv/bin/pip" install -q "litellm[proxy]==$litellm_version"
fi

mkdir -p "$keys" && chmod 700 "$keys"
if [ ! -s "$keys/kilo.key" ]; then
  key="${KILO_API_KEY:-}"
  if [ -z "$key" ]; then
    [ -t 0 ] || die "set KILO_API_KEY or run interactively"
    echo "Kilo API key: app.kilo.ai, switch to your personal account, Profile, bottom of the page."
    read -r -s -p "Paste it (input hidden): " key
    echo
  fi
  [ -n "$key" ] || die "empty key"
  (umask 077 && printf '%s' "$key" > "$keys/kilo.key")
  say "saved Kilo key to $keys/kilo.key"
fi
if [ ! -s "$keys/master.key" ]; then
  (umask 077 && printf 'sk-%s' "$(openssl rand -hex 24)" > "$keys/master.key")
fi

if [ -n "$mode" ]; then
  say "checking the key with one 1-token request ($mode billing)"
  hdr=()
  [ -n "$org_id" ] && hdr=(-H "X-KiloCode-OrganizationId: $org_id")
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 60 https://ai-gateway.kilo.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $(cat "$keys/kilo.key")" ${hdr[@]+"${hdr[@]}"} -H 'Content-Type: application/json' \
    -d '{"model":"anthropic/claude-haiku-5.5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' || true)"
  case "$code" in
    200) say "key works" ;;
    401) die "Kilo rejected the key (HTTP 401); replace $keys/kilo.key and re-run" ;;
    402) warn "no credits on the account being billed (HTTP 402); paid models fail until you add credits" ;;
    403) die "not a member of organization $org_id (HTTP 403)" ;;
    *) warn "key check returned HTTP $code; continuing" ;;
  esac
fi

if [ ! -f "$root/config.yaml" ]; then
  cp "$root/config/config.$mode.yaml" "$root/config.yaml"
  say "created config.yaml ($mode billing)"
elif [ -n "$mode" ]; then
  current=personal
  grep -q 'os.environ/KILO_ORG_ID' "$root/config.yaml" && current=organization
  if [ "$current" != "$mode" ]; then
    cp "$root/config.yaml" "$root/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
    cp "$root/config/config.$mode.yaml" "$root/config.yaml"
    say "switched config.yaml to $mode billing (previous file backed up)"
  fi
fi

[ -f "$root/claude-kilo.env" ] || cp "$root/config/claude-kilo.env.example" "$root/claude-kilo.env"
if [ -n "$mode" ]; then
  awk -v id="$org_id" '/KILO_ORG_ID:=/ { print ": \"${KILO_ORG_ID:=" id "}\""; next } { print }' \
    "$root/claude-kilo.env" > "$root/claude-kilo.env.tmp" && mv "$root/claude-kilo.env.tmp" "$root/claude-kilo.env"
fi
. "$root/claude-kilo.env"
port="${KILO_PROXY_PORT:-4000}"
mkdir -p "$root/logs"
chmod +x "$root"/bin/*

mkdir -p "$bin_dir"
ln -sfn "$root/bin/claude-kilo" "$bin_dir/claude-kilo"
say "linked $bin_dir/claude-kilo"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) warn "$bin_dir is not on your PATH; add it in your shell profile: export PATH=\"$bin_dir:\$PATH\"" ;;
esac

if [ "$(uname)" = Darwin ]; then
  if [ -z "$autostart" ]; then
    if [ -t 0 ]; then
      case "$(ask 'Start the proxy at login and reload it on config changes? [Y/n]')" in
        n|N|no|No) autostart=no ;;
        *) autostart=yes ;;
      esac
    else
      autostart=no
    fi
  fi
  if [ "$autostart" = yes ]; then
    agents="$HOME/Library/LaunchAgents"
    mkdir -p "$agents"
    for job in reload proxy; do
      launchctl bootout "gui/$(id -u)/claude-kilo.$job" 2>/dev/null || true
    done
    if curl -sf -m 2 "http://127.0.0.1:$port/health/liveliness" >/dev/null; then
      die "something already answers on 127.0.0.1:$port; stop it (or set KILO_PROXY_PORT in claude-kilo.env) and re-run"
    fi
    for job in proxy reload; do
      sed "s|@ROOT@|$root|g" "$root/launchd/claude-kilo.$job.plist.in" > "$agents/claude-kilo.$job.plist"
      for attempt in 1 2 3 4 5; do
        launchctl bootstrap "gui/$(id -u)" "$agents/claude-kilo.$job.plist" 2>/dev/null && break
        [ "$attempt" = 5 ] && die "launchctl could not load claude-kilo.$job"
        sleep 1
      done
    done
    say "autostart installed (logs in $root/logs)"
    for _ in $(seq 1 60); do
      curl -sf -m 2 "http://127.0.0.1:$port/health/liveliness" >/dev/null && break
      sleep 1
    done
    if curl -sf -m 2 "http://127.0.0.1:$port/health/liveliness" >/dev/null; then
      say "proxy is up on 127.0.0.1:$port"
    else
      warn "proxy is not answering yet; see $root/logs/proxy.log"
    fi
  fi
fi

echo
say "done"
if ! curl -sf -m 2 "http://127.0.0.1:$port/health/liveliness" >/dev/null; then
  echo "    start the proxy:   $root/bin/claude-kilo-proxy"
fi
echo "    run Claude Code:   claude-kilo"
echo "    test a model:      $root/bin/claude-kilo-smoke claude-haiku-5.5"
