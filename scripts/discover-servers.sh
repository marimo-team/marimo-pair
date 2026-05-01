#!/usr/bin/env bash
# List running marimo instances from the server registry.
# Cleans up stale entries (dead PIDs) and outputs live servers as JSON.
# No marimo installation required.
set -euo pipefail

# Locate the servers directory. Several shells can read marimo's registry,
# and they don't all agree on where it lives:
#   * Linux/macOS native        -> $XDG_STATE_HOME/marimo/servers (POSIX path)
#   * MSYS2 / Cygwin / Git Bash -> $HOME/.marimo/servers (Windows-native marimo)
#   * WSL pointed at Windows    -> $USERPROFILE translated via wslpath/cygpath
#                                  -> .../.marimo/servers
# OSTYPE-based detection misses the WSL case (OSTYPE=linux-gnu there), so we
# scan all candidates and use the first one that actually has registry files.
candidates=(
  "${XDG_STATE_HOME:-$HOME/.local/state}/marimo/servers"
  "$HOME/.marimo/servers"
)
if [[ -n "${USERPROFILE:-}" ]]; then
  if command -v wslpath >/dev/null 2>&1; then
    win_home=$(wslpath -u "$USERPROFILE" 2>/dev/null) || win_home=""
  elif command -v cygpath >/dev/null 2>&1; then
    win_home=$(cygpath -u "$USERPROFILE" 2>/dev/null) || win_home=""
  else
    win_home=""
  fi
  [[ -n "$win_home" ]] && candidates+=("$win_home/.marimo/servers")
fi

servers_dir=""
for d in "${candidates[@]}"; do
  if [[ -d "$d" ]] && compgen -G "$d/*.json" >/dev/null 2>&1; then
    servers_dir="$d"
    break
  fi
done

if [[ -z "$servers_dir" ]]; then
  echo "[]"
  exit 0
fi

# A registry living at .../.marimo/servers belongs to a Windows-native marimo
# (Git Bash, Cygwin, or WSL pointed at Windows) — its PIDs are Windows PIDs
# and won't respond to `kill -0` from any of those shells. Use HTTP probes
# in that case. The XDG path is always native POSIX.
case "$servers_dir" in
  */.marimo/servers) is_windows=true ;;
  *)                 is_windows=false ;;
esac

# Liveness check. On POSIX, `kill -0 $pid` is cheap and reliable. On Windows
# (Git Bash/MSYS2) `kill` operates on Cygwin PIDs, not the native Windows PIDs
# marimo writes, so fall back to an HTTP probe against marimo's /health.
check_live() {
  local f="$1"
  if [[ "$is_windows" == false ]]; then
    local pid
    pid=$(jq -r '.pid' "$f" 2>/dev/null) || return 1
    kill -0 "$pid" 2>/dev/null
  else
    local host port base_url
    host=$(jq -r '.host' "$f" 2>/dev/null) || return 1
    port=$(jq -r '.port' "$f" 2>/dev/null) || return 1
    base_url=$(jq -r '.base_url' "$f" 2>/dev/null) || return 1
    curl -sf --max-time 1 "http://${host}:${port}${base_url}/health" >/dev/null 2>&1
  fi
}

results="[]"
for f in "$servers_dir"/*.json; do
  [[ -e "$f" ]] || continue

  if ! check_live "$f"; then
    # On Windows the HTTP probe can fail transiently (slow start, busy server),
    # so keep the entry; only POSIX `kill -0` is reliable enough to delete on.
    [[ "$is_windows" == false ]] && rm -f "$f"
    continue
  fi

  entry=$(jq '.' "$f" 2>/dev/null) || continue
  results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
done

echo "$results" | jq .
