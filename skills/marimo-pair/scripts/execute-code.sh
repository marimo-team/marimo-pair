#!/usr/bin/env bash
# Execute code in a running marimo session's scratchpad.
# No marimo installation required — talks directly to the HTTP API.
# Usage:
#   execute-code.sh --url URL [--session ID] -c "code"    # inline code
#   execute-code.sh --url URL [--session ID] script.py    # code from file
#   execute-code.sh --url URL [--session ID] <<< "code"   # stdin (here-string)
#   execute-code.sh --url URL [--session ID] <<'EOF'      # stdin (heredoc)
#     code
#   EOF
#
# Find the URL with discover-servers.sh. With one notebook open on the server
# the session is resolved automatically; --session picks one of several.
#
# Auth: set MARIMO_TOKEN env var (preferred) or pass --token TOKEN (visible in ps).
set -euo pipefail

usage() {
  echo "Usage: execute-code.sh --url URL [--session ID] -c 'code'" >&2
  echo "       execute-code.sh --url URL [--session ID] script.py" >&2
  echo "       echo 'code' | execute-code.sh --url URL [--session ID]" >&2
  echo "URL:   run discover-servers.sh; it reports the url to use." >&2
  echo "Auth:  set MARIMO_TOKEN env var (preferred) or pass --token TOKEN" >&2
  exit 1
}

# Optional eval logging: set EXECUTE_CODE_LOG to a file path to record each call
if [[ -n "${EXECUTE_CODE_LOG:-}" ]]; then
  date -u +%Y-%m-%dT%H:%M:%SZ >> "$EXECUTE_CODE_LOG"
fi

code=""
url=""
token="${MARIMO_TOKEN:-}"
session=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)     url="$2"; shift 2 ;;
    --token)   token="$2"; shift 2 ;;
    --session) session="$2"; shift 2 ;;
    -c)        code="$2"; shift 2 ;;
    -*)      echo "Unknown option: $1" >&2; usage ;;
    *)       break ;;
  esac
done

if [[ -z "$url" ]]; then
  echo "Missing --url." >&2
  usage
fi

if [[ -n "$code" ]]; then
  : # set via -c
elif [[ $# -gt 0 ]]; then
  code=$(cat "$1")
elif [[ ! -t 0 ]]; then
  code=$(cat)
else
  usage
fi

missing=""
for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing, }$tool"
done
if [[ -n "$missing" ]]; then
  echo "execute-code.sh needs ${missing} on PATH." >&2
  exit 1
fi

base="${url%/}"

# Warn when connecting to a non-local server (data exfiltration risk)
url_authority="${url#*://}"
url_authority="${url_authority%%[/?#]*}"
# Strip userinfo so this check uses the same effective host as curl.
url_authority="${url_authority##*@}"
case "$url_authority" in
  \[*\]*)
    url_host="${url_authority#\[}"
    url_host="${url_host%%\]*}"
    ;;
  *)
    url_host="${url_authority%%:*}"
    ;;
esac
case "$url_host" in
  localhost|127.0.0.1|::1|0.0.0.0) ;;
  *)
    # Under WSL the gateway is the Windows host running this distro, not a
    # remote machine.
    gateway=""
    if command -v ip >/dev/null 2>&1; then
      gateway=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $3 }') || gateway=""
    fi
    if [[ -z "$gateway" || "$url_host" != "$gateway" ]]; then
      echo "Warning: connecting to non-local server '${url_host}'. Ensure this is trusted." >&2
    fi
    ;;
esac

# Build optional auth header
auth_args=()
if [[ -n "$token" ]]; then
  auth_args+=(-H "Authorization: Bearer ${token}")
fi

# Discover session ID
if [[ -n "$session" ]]; then
  session_id="$session"
else
  sessions_resp=$(curl -sf --connect-timeout 5 "${auth_args[@]+"${auth_args[@]}"}" "${base}/api/sessions") || {
    echo "Failed to connect to marimo server at ${base}" >&2
    case "$base" in
      *//127.0.0.1:*|*//localhost:*)
        if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
          echo "Under WSL, 127.0.0.1 is the distro's own loopback, not the Windows host's." >&2
          echo "Run discover-servers.sh and use the url it reports." >&2
        fi
        ;;
    esac
    exit 1
  }

  session_ids=$(jq -r 'keys[]' <<<"$sessions_resp")

  if [[ -z "$session_ids" ]]; then
    echo "No active sessions on the server. Make sure a notebook is open in the browser." >&2
    exit 1
  fi

  session_count=$(wc -l <<<"$session_ids" | tr -d ' ')

  if [[ $session_count -gt 1 ]]; then
    # TODO: select by filename instead. An id is only good until the browser
    # reconnects; the filename is stable. Needs an upstream change first.
    echo "Multiple sessions on server. Cannot auto-select:" >&2
    jq -r 'to_entries[] | "\(.key)  \(.value.filename // "")"' <<<"$sessions_resp" >&2
    exit 1
  fi

  session_id=$(head -1 <<<"$session_ids")
fi

# Execute code via SSE stream
# Events: stdout/stderr stream as JSON {"data":"..."}, done is final result.
exit_code=0
current_event=""
done_received=false
unparsed=""
# An error body has no trailing newline, so keep what `read` got on its last,
# failing call.
while { IFS= read -r line || [[ -n "$line" ]]; } && [[ "$done_received" == false ]]; do
  line="${line%$'\r'}" # SSE permits CRLF; `read` strips only the LF
  case "$line" in
    event:*)
      current_event="${line#event: }"
      ;;
    "") ;; # SSE record separator
    data:*)
      payload="${line#data: }"
      case "$current_event" in
        stdout)
          jq -jr '.data' <<<"$payload"
          ;;
        stderr)
          jq -jr '.data' <<<"$payload" >&2
          ;;
        done)
          # Carries the success bit and output only; errors arrived as stderr.
          if jq -e '.success == false' >/dev/null 2>&1 <<<"$payload"; then
            exit_code=1
          else
            jq -r '.output.data // empty' <<<"$payload"
          fi
          done_received=true
          ;;
      esac
      ;;
    *)
      # Not SSE at all — an error body rather than a stream.
      unparsed="${unparsed}${line}"$'\n'
      ;;
  esac
done < <(curl -sN -X POST "${base}/api/kernel/execute" \
  -H "Content-Type: application/json" \
  -H "Marimo-Session-Id: ${session_id}" \
  ${auth_args[@]+"${auth_args[@]}"} \
  -d "$(jq -n --arg c "$code" '{code: $c}')" \
)

if [[ "$done_received" == false ]]; then
  # No `done` event means the code never ran; without this we would exit 0.
  echo "Execution did not complete: the server ended the stream without a result." >&2
  if [[ -n "$unparsed" ]]; then
    detail=$(jq -r '.detail // empty' <<<"$unparsed" 2>/dev/null) || detail=""
    if [[ -n "$detail" ]]; then
      echo "$detail" >&2
    else
      printf '%s' "$unparsed" >&2
    fi
  fi
  if [[ -n "$session" ]]; then
    echo "The --session id may be stale: marimo renames a session when the browser reconnects. Retry without --session." >&2
  fi
  exit 1
fi

exit "$exit_code"
