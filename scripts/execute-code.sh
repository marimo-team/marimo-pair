#!/usr/bin/env bash
# Execute code in a running marimo session's scratchpad.
# No marimo installation required — talks directly to the HTTP API.
# Requires the server to be started with --no-token.
#
# Usage:
#   execute-code.sh <code>                    # auto-discover single session
#   execute-code.sh --port 2718 <code>        # target by port
#   cat script.py | execute-code.sh           # read code from stdin
set -euo pipefail

port=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [[ $# -gt 0 ]]; then
  code="$1"
elif [[ ! -t 0 ]]; then
  code=$(cat)
else
  echo "Usage: execute-code.sh [--port PORT] <code>" >&2
  echo "       cat script.py | execute-code.sh" >&2
  exit 1
fi

# Locate the sessions directory
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  sessions_dir="$HOME/.marimo/sessions"
else
  sessions_dir="${XDG_STATE_HOME:-$HOME/.local/state}/marimo/sessions"
fi

# Find a live registry entry
entry=""
count=0
for f in "$sessions_dir"/*.json; do
  [[ -e "$f" ]] || continue

  pid=$(jq -r '.pid' "$f" 2>/dev/null) || continue
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
    continue
  fi

  e=$(cat "$f")

  if [[ -n "$port" ]]; then
    e_port=$(echo "$e" | jq -r '.port')
    if [[ "$e_port" == "$port" ]]; then
      entry="$e"
      count=1
      break
    fi
    continue
  fi

  entry="$e"
  count=$((count + 1))
done

if [[ $count -eq 0 ]]; then
  echo "No running marimo sessions found." >&2
  exit 1
fi

if [[ $count -gt 1 ]]; then
  echo "Multiple sessions found. Use --port to specify:" >&2
  for f in "$sessions_dir"/*.json; do
    [[ -e "$f" ]] || continue
    pid=$(jq -r '.pid' "$f" 2>/dev/null) || continue
    kill -0 "$pid" 2>/dev/null || continue
    jq -r '"\(.server_id)  \(.notebook_path // "(multi/new)")"' "$f" >&2
  done
  exit 1
fi

host=$(echo "$entry" | jq -r '.host')
e_port=$(echo "$entry" | jq -r '.port')
base_url=$(echo "$entry" | jq -r '.base_url')
base="http://${host}:${e_port}${base_url}"

# Discover session ID
sessions_resp=$(curl -sf "${base}/api/sessions") || {
  echo "Failed to connect to marimo server at ${base}" >&2
  exit 1
}

session_ids=$(echo "$sessions_resp" | jq -r 'keys[]')

if [[ -z "$session_ids" ]]; then
  echo "No active sessions on the server. Make sure a notebook is open in the browser." >&2
  exit 1
fi

session_count=$(echo "$session_ids" | wc -l | tr -d ' ')

if [[ $session_count -gt 1 ]]; then
  echo "Multiple sessions on server. Cannot auto-select:" >&2
  echo "$sessions_resp" | jq -r 'to_entries[] | "\(.key)  \(.value.filename // "")"' >&2
  exit 1
fi

session_id=$(echo "$session_ids" | head -1)

# Execute code
result=$(curl -sf -X POST "${base}/api/kernel/scratchpad/execute" \
  -H "Content-Type: application/json" \
  -H "Marimo-Session-Id: ${session_id}" \
  -d "$(jq -n --arg c "$code" '{code: $c}')" \
  --max-time 65) || {
  echo "Execution request failed." >&2
  exit 1
}

# Print output
echo "$result" | jq -r '
  (.stdout // [] | join("")),
  (.output // empty),
  (.stderr // [] | join("") | if . != "" then "STDERR: " + . else empty end),
  (.errors // [] | .[] | "ERROR: " + .),
  (.error // empty | "ERROR: " + .)
' 2>/dev/null

# Exit with failure if execution failed
if echo "$result" | jq -e '.success == false' >/dev/null 2>&1; then
  exit 1
fi
