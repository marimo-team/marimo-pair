#!/usr/bin/env bash
# List running marimo instances from the server registry.
# Cleans up stale entries (dead PIDs) and outputs live servers as JSON.
# No marimo installation required.
set -euo pipefail

# Locate the servers directory
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  servers_dir="$HOME/.marimo/servers"
else
  servers_dir="${XDG_STATE_HOME:-$HOME/.local/state}/marimo/servers"
fi

if [[ ! -d "$servers_dir" ]]; then
  echo "[]"
  exit 0
fi

results="[]"
for f in "$servers_dir"/*.json; do
  [[ -e "$f" ]] || continue

  pid=$(jq -r '.pid' "$f" 2>/dev/null) || continue

  # Clean up stale entries. Under MSYS/Cygwin, accept either a Windows-native
  # process lookup or `kill -0` so we handle both Windows and Bash-owned PIDs.
  if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    if ! powershell.exe -NoProfile -Command "Get-Process -Id $pid -ErrorAction SilentlyContinue | Out-Null; if (\$?) { exit 0 } else { exit 1 }" \
      && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f"
      continue
    fi
  else
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f"
      continue
    fi
  fi

  entry=$(jq '.' "$f" 2>/dev/null) || continue
  results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
done

echo "$results" | jq .
