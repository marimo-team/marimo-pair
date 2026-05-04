#!/usr/bin/env bash
# List running marimo instances from the server registry.
# Cleans up stale entries (dead PIDs) and outputs live servers as JSON.
# No marimo installation required.
set -euo pipefail

# Build the candidate list of registry directories. Several shells can read
# marimo's registry, and they don't all agree on where it lives:
#   * Linux/macOS native        -> $XDG_STATE_HOME/marimo/servers (POSIX path)
#   * MSYS2 / Cygwin / Git Bash -> $HOME/.marimo/servers (Windows-native marimo)
#   * WSL pointed at Windows    -> $USERPROFILE translated via wslpath/cygpath
#                                  -> .../.marimo/servers
# OSTYPE-based detection misses the WSL case (OSTYPE=linux-gnu there), and
# selecting just the first candidate that *contains files* fails when one
# candidate has only stale entries while another has the live server. So we
# scan every candidate and aggregate live entries across all of them.
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

# Dedupe by string. On Git Bash $HOME and the cygpath translation of
# $USERPROFILE typically resolve to the same path (e.g. /c/Users/foo), and
# without dedupe the same server is listed twice. O(n^2) loop is fine — the
# candidate list never exceeds a handful.
deduped=()
for d in "${candidates[@]}"; do
  is_dup=false
  for e in "${deduped[@]+${deduped[@]}}"; do
    if [[ "$e" == "$d" ]]; then
      is_dup=true
      break
    fi
  done
  $is_dup || deduped+=("$d")
done
candidates=("${deduped[@]}")

# Liveness check. On POSIX, `kill -0 $pid` is cheap and reliable. On Windows
# (Git Bash/MSYS2/WSL pointed at Windows) `kill` operates on Cygwin/Linux PIDs,
# not the native Windows PIDs marimo writes, so fall back to an HTTP probe
# against marimo's /health. The ``is_windows`` flag is set per candidate
# directory below — a registry living at .../.marimo/servers always houses
# Windows-native PIDs regardless of which shell is reading it.
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

# Walk every candidate, applying per-candidate liveness rules, and collect
# every live entry. A stale POSIX/XDG registry can't shadow a live Windows-
# native one this way, and a user with two live marimos in different
# registries (rare but possible) sees both.
results="[]"
for d in "${candidates[@]}"; do
  [[ -d "$d" ]] || continue
  case "$d" in
    */.marimo/servers) is_windows=true ;;
    *)                 is_windows=false ;;
  esac
  for f in "$d"/*.json; do
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
done

echo "$results" | jq .
