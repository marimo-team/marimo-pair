#!/usr/bin/env bash
# Execute code in a running marimo session's scratchpad.
# No marimo installation required — talks directly to the HTTP API.
# Requires the server to be started with --no-token.
#
# Usage:
#   execute-code.sh [--port PORT] -c "code"   # inline code
#   execute-code.sh [--port PORT] script.py    # code from file
set -euo pipefail

# Optional eval logging: set EXECUTE_CODE_LOG to a file path to record each call
if [[ -n "${EXECUTE_CODE_LOG:-}" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EXECUTE_CODE_LOG"
fi

port=""
code=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    -c)     code="$2"; shift 2 ;;
    -*)     echo "Unknown option: $1" >&2; exit 1 ;;
    *)      break ;;
  esac
done

if [[ -n "$code" ]]; then
  : # set via -c
elif [[ $# -gt 0 ]]; then
  code=$(cat "$1")
else
  echo "Usage: execute-code.sh [--port PORT] -c 'code'" >&2
  echo "       execute-code.sh [--port PORT] script.py" >&2
  exit 1
fi

# Locate the servers directory
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  servers_dir="$HOME/.marimo/servers"
else
  servers_dir="${XDG_STATE_HOME:-$HOME/.local/state}/marimo/servers"
fi

# Find a live registry entry
entry=""
count=0
for f in "$servers_dir"/*.json; do
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
  echo "No running marimo instances found." >&2
  exit 1
fi

if [[ $count -gt 1 ]]; then
  echo "Multiple instances found. Use --port to specify:" >&2
  for f in "$servers_dir"/*.json; do
    [[ -e "$f" ]] || continue
    pid=$(jq -r '.pid' "$f" 2>/dev/null) || continue
    kill -0 "$pid" 2>/dev/null || continue
    jq -r '.server_id' "$f" >&2
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

# Execute code via SSE stream
# Events: stdout/stderr stream as JSON {"data":"..."}, done is final result.
exit_code=0
current_event=""
done_received=false
while IFS= read -r line && [[ "$done_received" == false ]]; do
  case "$line" in
    event:*)
      current_event="${line#event: }"
      ;;
    data:*)
      payload="${line#data: }"
      case "$current_event" in
        stdout)
          echo "$payload" | jq -jr '.data'
          ;;
        stderr)
          echo "$payload" | jq -jr '.data' >&2
          ;;
        done)
          if echo "$payload" | jq -e '.success == false' >/dev/null 2>&1; then
            echo "$payload" | jq -r '.error.msg' >&2
            exit_code=1
          else
            echo "$payload" | jq -r '.output.data // empty'
          fi
          done_received=true
          ;;
      esac
      ;;
  esac
done < <(curl -sN -X POST "${base}/api/kernel/execute" \
  -H "Content-Type: application/json" \
  -H "Marimo-Session-Id: ${session_id}" \
  -d "$(jq -n --arg c "$code" '{code: $c}')" \
  --max-time 65)

exit "$exit_code"
