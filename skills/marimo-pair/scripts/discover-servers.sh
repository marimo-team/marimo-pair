#!/usr/bin/env bash
# List running marimo instances from the server registry.
# Cleans up stale entries and outputs live servers as JSON.
# No marimo installation required.
#
# Servers started with --no-token register themselves and deregister on clean
# shutdown, so a leftover file means the process was killed hard. See
# marimo/_server/server_registry.py.
#
# Prints one object per live server:
#   server_id             marimo's name for it, e.g. "127.0.0.1:2718"
#   origin                "local" or "windows-host", relative to us
#   url                   base URL that answered from here, or null if none did
#   started_at, version   passed through from the registry
#
# Pass `url` straight to execute-code.sh --url.
set -euo pipefail

missing=""
for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing, }$tool"
done
if [[ -n "$missing" ]]; then
  echo "discover-servers.sh needs ${missing} on PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------- platform ---

if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  platform=windows
elif [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
  platform=wsl
else
  platform=posix
fi

# Path to a Windows executable. With appendWindowsPath=false interop still
# works, it is just not on PATH.
windows_exe() {
  local name=$1 sys32
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  command -v wslpath >/dev/null 2>&1 || return 1
  sys32=$(wslpath -u 'C:\Windows\System32' 2>/dev/null) || return 1
  [[ -x "$sys32/$name" ]] || return 1
  printf '%s\n' "$sys32/$name"
}

# ------------------------------------------------------- registry locations ---
#
# Origin is tracked per directory, not guessed from an entry's path: a Linux box
# may well keep its home under a mount point.

dirs=()
origins=()

if [[ "$platform" == windows ]]; then
  dirs+=("$HOME/.marimo/servers")
else
  dirs+=("${XDG_STATE_HOME:-$HOME/.local/state}/marimo/servers")
fi
origins+=("local")

# From WSL, a notebook may also be running on the Windows host. Ask cmd.exe for
# the profile rather than globbing /mnt for it.
if [[ "$platform" == wsl ]] && cmd_exe=$(windows_exe cmd.exe); then
  # cmd.exe warns on a UNC cwd but still prints the value.
  profile=$("$cmd_exe" /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n') || profile=""
  if [[ -n "$profile" && "$profile" != "%USERPROFILE%" ]] && command -v wslpath >/dev/null 2>&1; then
    win_home=$(wslpath -u "$profile" 2>/dev/null) || win_home=""
    if [[ -n "$win_home" ]]; then
      dirs+=("$win_home/.marimo/servers")
      origins+=("windows-host")
    fi
  fi
fi

# ---------------------------------------------------------------- liveness ---
#
# A server is live if its process is running or something answers at its
# address. Neither signal is reliable alone — Windows recycles PIDs, and a
# healthy server can be unreachable across the WSL boundary — so an entry is
# only deleted when both say it is gone.

tasklist_csv=""
tasklist_state=""

load_tasklist() {
  local exe
  [[ -z "$tasklist_state" ]] || return 0
  tasklist_state=fail
  if exe=$(windows_exe tasklist.exe); then
    # Git Bash would otherwise mangle /FO and /NH into paths.
    tasklist_csv=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
      "$exe" /FO CSV /NH 2>/dev/null) || tasklist_csv=""
  fi
  # tasklist.exe exits 0 even when it only printed an error, so check the shape
  # before trusting this to declare anything dead.
  if grep -qE '^"[^"]*","[0-9]+",' <<<"$tasklist_csv"; then
    tasklist_state=ok
  else
    tasklist_csv=""
  fi
}

# 0 = running, 1 = definitely gone, 2 = cannot tell
process_alive() {
  local pid=$1 origin=$2
  [[ "$pid" =~ ^[0-9]+$ ]] || return 2
  if [[ "$origin" == windows-host || "$platform" == windows ]]; then
    # A POSIX kill cannot see a Windows PID, so ask Windows.
    load_tasklist
    [[ "$tasklist_state" == ok ]] || return 2
    if grep -q "^\"[^\"]*\",\"${pid}\"," <<<"$tasklist_csv"; then
      return 0
    fi
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ------------------------------------------------------------ reachability ---

gateway=""
gateway_resolved=false

# The default gateway, which under WSL NAT is the Windows host.
find_gateway() {
  local hex
  [[ "$gateway_resolved" == false ]] || return 0
  gateway_resolved=true
  if command -v ip >/dev/null 2>&1; then
    # `|| gateway=""` keeps `set -e` from killing us before the fallback runs.
    gateway=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $3 }') || gateway=""
  fi
  if [[ -z "$gateway" && -r /proc/net/route ]]; then
    # Without iproute2, read the default route (destination and mask zero)
    # from the kernel. Its gateway field is little-endian hex.
    hex=$(awk '$2 == "00000000" && $8 == "00000000" { print $3; exit }' /proc/net/route 2>/dev/null) || hex=""
    if [[ "$hex" =~ ^[0-9A-Fa-f]{8}$ ]]; then
      printf -v gateway '%d.%d.%d.%d' \
        "0x${hex:6:2}" "0x${hex:4:2}" "0x${hex:2:2}" "0x${hex:0:2}"
    fi
  fi
}

is_private_ipv4() {
  case "$1" in
    10.*|127.*|192.168.*|169.254.*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    *) return 1 ;;
  esac
}

# Check that a marimo answers here, not just any HTTP server — this is where
# code and tokens get sent. /health needs no auth.
answers_marimo() {
  curl -sf --connect-timeout 1 --max-time 2 "$1/health" 2>/dev/null | grep -q '"healthy"'
}

local_port_taken() {
  local i
  for ((i = 0; i < live_count; i++)); do
    if [[ "${live_origins[$i]}" == local && "${live_ports[$i]}" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

# Addresses worth trying for one entry, best first.
candidate_hosts() {
  local host=$1 port=$2 origin=$3
  if [[ "$origin" == local ]]; then
    # A bind-all address is not a connect target; use loopback.
    case "$host" in
      0.0.0.0|"") echo 127.0.0.1 ;;
      ::) echo ::1 ;;
      *) echo "$host" ;;
    esac
    return 0
  fi

  # A Windows-host server is across the WSL boundary. A specific address names
  # the machine and works from either side.
  case "$host" in
    0.0.0.0|::|127.0.0.1|localhost|::1|"") ;;
    *) echo "$host" ;;
  esac

  find_gateway
  if [[ -n "$gateway" ]] && is_private_ipv4 "$gateway"; then
    echo "$gateway"
  fi

  # Loopback here is the distro's own, and only reaches the host under mirrored
  # networking. Last resort, and skipped when a local server holds the port —
  # that would be the wrong kernel. Local entries are scanned first.
  case "$host" in
    0.0.0.0|::|127.0.0.1|localhost|::1|"")
      local_port_taken "$port" || echo 127.0.0.1
      ;;
  esac
}

# Print a base URL that answered, or nothing.
resolve_url() {
  local host=$1 port=$2 base_url=$3 origin=$4 candidate url
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$candidate" in
      *:*) url="http://[${candidate}]:${port}${base_url}" ;; # IPv6 literal
      *) url="http://${candidate}:${port}${base_url}" ;;
    esac
    if answers_marimo "$url"; then
      printf '%s' "$url"
      return 0
    fi
  done <<<"$(candidate_hosts "$host" "$port" "$origin")"
  return 1
}

# ------------------------------------------------------------------- scan ---

live_files=()
live_origins=()
live_urls=()
live_ids=()
live_pids=()
live_hosts=()
live_ports=()
live_count=0

for ((i = 0; i < ${#dirs[@]}; i++)); do
  dir=${dirs[$i]}
  origin=${origins[$i]}
  [[ -d "$dir" ]] || continue

  for file in "$dir"/*.json; do
    [[ -e "$file" ]] || continue

    meta=$(jq -r '[(.server_id // ""), (.pid|tostring), (.host // ""), (.port|tostring), (.base_url // "")] | @tsv' "$file" 2>/dev/null) || continue
    IFS=$'\t' read -r id pid host port base_url <<<"$meta"

    state=0
    process_alive "$pid" "$origin" || state=$?
    url=$(resolve_url "$host" "$port" "$base_url" "$origin") || url=""

    if [[ $state -ne 0 && -z "$url" ]]; then
      # Nothing answered. Drop the entry only if the process is gone for
      # certain; state 2 means we could not tell, so leave it alone.
      if [[ $state -eq 1 ]]; then
        rm -f "$file"
      fi
      continue
    fi

    live_files+=("$file")
    live_origins+=("$origin")
    live_urls+=("$url")
    live_ids+=("$id")
    live_pids+=("$pid")
    live_hosts+=("$host")
    live_ports+=("$port")
    live_count=$((live_count + 1))
  done
done

# ----------------------------------------------------------------- output ---

entries=""
for ((i = 0; i < live_count; i++)); do
  entry=$(jq -c --arg origin "${live_origins[$i]}" --arg url "${live_urls[$i]}" \
    '{server_id, started_at, version, origin: $origin,
      url: (if $url == "" then null else $url end)}' \
    "${live_files[$i]}" 2>/dev/null) || continue
  entries="${entries}${entry}"$'\n'
done

if [[ -z "$entries" ]]; then
  echo '[]'
else
  printf '%s' "$entries" | jq -s '.'
fi

# Explain any server that is running but answered nowhere. How it was bound and
# which side of the WSL boundary it is on decide the advice.
for ((i = 0; i < live_count; i++)); do
  [[ -z "${live_urls[$i]}" ]] || continue
  id=${live_ids[$i]}
  pid=${live_pids[$i]}
  host=${live_hosts[$i]}
  port=${live_ports[$i]}

  if [[ "${live_origins[$i]}" == windows-host ]]; then
    find_gateway
    echo "${id} is running on the Windows host (PID ${pid}) but answered at no address reachable from WSL." >&2
    case "$host" in
      0.0.0.0|::)
        echo "It is bound to ${host}, so the Windows firewall is the likely cause. Options:" >&2
        echo "  - allow inbound TCP ${port} on the 'vEthernet (WSL)' adapter${gateway:+ (gateway ${gateway})}" >&2
        ;;
      *)
        echo "WSL's NAT network cannot reach a service bound to ${host} on the host. Options:" >&2
        echo "  - restart marimo on the host with --host 0.0.0.0${gateway:+ (reachable from WSL at ${gateway})}" >&2
        echo "  - or switch WSL to mirrored networking: add 'networkingMode=mirrored' under [wsl2] in %USERPROFILE%\\.wslconfig, then run 'wsl --shutdown'" >&2
        ;;
    esac
    echo "  - or run these scripts from Git Bash / PowerShell on the Windows side" >&2
  else
    echo "${id} is registered (PID ${pid}) but nothing answers there." >&2
  fi
  echo "If marimo is no longer running, PID ${pid} may belong to an unrelated process that reused the id." >&2
done
