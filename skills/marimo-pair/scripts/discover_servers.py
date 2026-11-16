#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Discover live marimo servers from the local server registry.

Servers started with ``--no-token`` register themselves and deregister on a
clean shutdown. This script removes entries left by hard exits, but only when
the recorded process is definitely gone *and* no marimo server answers at the
recorded address. Neither signal is sufficient by itself: PIDs are reused, and
a healthy Windows-host server may be unreachable from WSL.

The JSON output intentionally matches ``discover-servers.sh`` so callers can
move between implementations without changing their parsing.
"""

from __future__ import annotations

import csv
import ctypes
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from collections.abc import Iterator
from functools import lru_cache
from pathlib import Path
from typing import Any

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
STILL_ACTIVE = 259


# ------------------------------------------------------------------ platform


def is_wsl() -> bool:
    if "WSL_DISTRO_NAME" in os.environ:
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False


def registry_locations() -> list[tuple[Path, str]]:
    """Return registry directories with origins assigned by location.

    An entry's own path cannot identify its origin: a Linux home directory may
    itself be mounted. Under WSL, ask Windows for its profile rather than
    guessing which mounted drive contains it.
    """
    if os.name == "nt":
        locations = [(Path.home() / ".marimo" / "servers", "local")]
    else:
        state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        locations = [(state_home / "marimo" / "servers", "local")]

    if is_wsl():
        try:
            profile = subprocess.run(
                ["cmd.exe", "/c", "echo", "%USERPROFILE%"],
                capture_output=True,
                check=False,
                text=True,
            ).stdout.strip()
            converted = subprocess.run(
                ["wslpath", "-u", profile],
                capture_output=True,
                check=False,
                text=True,
            ).stdout.strip()
            if converted:
                locations.append((Path(converted) / ".marimo" / "servers", "windows-host"))
        except OSError:
            pass
    return locations


# ------------------------------------------------------------------ liveness


def windows_process_alive(pid: int) -> bool | None:
    """Report Windows process liveness, or None when it cannot be determined."""
    if os.name == "nt":
        # Native Windows can query the PID without parsing localized CLI text.
        kernel32 = ctypes.windll.kernel32
        kernel32.OpenProcess.restype = ctypes.c_void_p
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            error = kernel32.GetLastError()
            if error == 5:  # Access denied proves the process exists.
                return True
            return False if error in {87, 1168} else None
        try:
            exit_code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return None
            return exit_code.value == STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)

    pids = windows_process_ids()
    return None if pids is None else pid in pids


@lru_cache(maxsize=1)
def windows_process_ids() -> frozenset[int] | None:
    """Load Windows PIDs once for WSL-side liveness checks."""
    # WSL cannot use os.kill for a Windows PID. tasklist is the interop
    # fallback; validate its CSV shape before trusting it to declare any PID dead.
    tasklist = shutil.which("tasklist.exe")
    if not tasklist:
        return None
    try:
        result = subprocess.run(
            [tasklist, "/FO", "CSV", "/NH"],
            capture_output=True,
            check=False,
        )
        return parse_tasklist_process_ids(result.stdout)
    except OSError:
        return None


def parse_tasklist_process_ids(output: bytes) -> frozenset[int] | None:
    """Parse tasklist CSV while tolerating localized non-UTF-8 display text.

    Process names and memory-size columns may contain bytes from the Windows
    console code page. The PID column is ASCII, so replacement decoding keeps
    the structural CSV data without guessing the host locale.
    """
    try:
        rows = list(csv.reader(output.decode("utf-8", errors="replace").splitlines()))
    except csv.Error:
        return None
    if not rows or not any(len(row) >= 2 and row[1].isdigit() for row in rows):
        return None
    return frozenset(int(row[1]) for row in rows if len(row) >= 2 and row[1].isdigit())


def process_alive(pid: Any, origin: str) -> bool | None:
    """Return True, False, or None when process state is unknowable."""
    if not isinstance(pid, int) or pid <= 0:
        return None
    if origin == "windows-host" or os.name == "nt":
        return windows_process_alive(pid)
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return None


# --------------------------------------------------------------- reachability


def wsl_gateway() -> str | None:
    """Return WSL's default gateway, normally the Windows host under NAT."""
    try:
        result = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True,
            check=False,
            text=True,
        ).stdout.split()
        if "via" in result:
            return result[result.index("via") + 1]
    except OSError:
        pass

    try:
        for line in Path("/proc/net/route").read_text().splitlines()[1:]:
            fields = line.split()
            if fields[1] == "00000000" and fields[7] == "00000000":
                raw = bytes.fromhex(fields[2])
                return str(ipaddress.ip_address(raw[::-1]))
    except (OSError, IndexError, ValueError):
        pass
    return None


def is_private_ipv4(address: str) -> bool:
    """Match the explicit private/link-local ranges used by the shell client."""
    try:
        ip = ipaddress.IPv4Address(address)
    except ipaddress.AddressValueError:
        return False
    ranges = (
        ipaddress.IPv4Network("10.0.0.0/8"),
        ipaddress.IPv4Network("127.0.0.0/8"),
        ipaddress.IPv4Network("169.254.0.0/16"),
        ipaddress.IPv4Network("172.16.0.0/12"),
        ipaddress.IPv4Network("192.168.0.0/16"),
    )
    return any(ip in network for network in ranges)


def candidate_hosts(
    host: str,
    port: int,
    origin: str,
    local_ports: set[int],
) -> Iterator[str]:
    """Yield connectable addresses in preference order for one registry entry."""
    wildcard_hosts = {"", "0.0.0.0", "::"}
    loopback_hosts = {"127.0.0.1", "localhost", "::1"}
    if origin == "local":
        # Bind-all addresses are not useful connection targets; loopback is.
        yield "::1" if host == "::" else "127.0.0.1" if host in wildcard_hosts else host
        return

    # A specific Windows-host address works from either side of the boundary.
    if host not in wildcard_hosts | loopback_hosts:
        yield host
    gateway = wsl_gateway()
    if gateway and is_private_ipv4(gateway):
        yield gateway
    if host in wildcard_hosts | loopback_hosts and port not in local_ports:
        # Loopback reaches the host under mirrored networking. Do not try it if
        # a local WSL server owns this port: that would target the wrong kernel.
        yield "127.0.0.1"


def answers_marimo(url: str) -> bool:
    """Check for marimo's unauthenticated health response, not merely HTTP."""
    try:
        with urllib.request.urlopen(f"{url}/health", timeout=2) as response:
            payload = json.load(response)
        return payload.get("status") == "healthy"
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return False


def resolve_url(
    metadata: dict[str, Any],
    origin: str,
    local_ports: set[int],
) -> str | None:
    host = str(metadata.get("host") or "")
    port = metadata.get("port")
    if not isinstance(port, int):
        return None
    base_url = str(metadata.get("base_url") or "")
    for candidate in candidate_hosts(host, port, origin, local_ports):
        authority = f"[{candidate}]" if ":" in candidate else candidate
        url = f"http://{authority}:{port}{base_url}".rstrip("/")
        if answers_marimo(url):
            return url
    return None


# ---------------------------------------------------------------------- scan


def load_entries() -> list[tuple[Path, str, dict[str, Any]]]:
    entries = []
    for directory, origin in registry_locations():
        for path in directory.glob("*.json") if directory.is_dir() else ():
            try:
                metadata = json.loads(path.read_text(encoding="utf-8"))
                entries.append((path, origin, metadata))
            except (OSError, json.JSONDecodeError):
                continue
    entries.sort(key=lambda entry: entry[1] != "local")
    return entries


def unreachable_message(metadata: dict[str, Any], origin: str) -> str:
    server_id = metadata.get("server_id", "unknown server")
    pid = metadata.get("pid", "unknown")
    if origin == "windows-host":
        host = metadata.get("host", "")
        port = metadata.get("port", "unknown")
        gateway = wsl_gateway()
        lines = [
            (
                f"{server_id} is running on the Windows host (PID {pid}) but "
                "answered at no address reachable from WSL."
            )
        ]
        if host in {"0.0.0.0", "::"}:
            suffix = f" (gateway {gateway})" if gateway else ""
            lines.append(
                f"Allow inbound TCP {port} on the 'vEthernet (WSL)' adapter{suffix}."
            )
        else:
            suffix = f" (reachable from WSL at {gateway})" if gateway else ""
            lines.append(f"Restart marimo on the host with --host 0.0.0.0{suffix}.")
            lines.append("Alternatively, switch WSL to mirrored networking.")
        lines.append("You can also run these scripts from Windows.")
    else:
        lines = [f"{server_id} is registered (PID {pid}) but nothing answers there."]
    lines.append(
        f"If marimo is no longer running, PID {pid} may belong to an unrelated "
        "process that reused the id."
    )
    return "\n".join(lines)


def main() -> int:
    entries = load_entries()
    local_ports = {
        metadata["port"]
        for _, origin, metadata in entries
        if origin == "local" and isinstance(metadata.get("port"), int)
    }
    live = []
    warnings = []
    for path, origin, metadata in entries:
        alive = process_alive(metadata.get("pid"), origin)
        url = resolve_url(metadata, origin, local_ports)
        if alive is not True and url is None:
            # Delete only when process state is conclusive. An unknowable PID
            # may represent a healthy server across an unavailable boundary.
            if alive is False:
                try:
                    path.unlink()
                except OSError:
                    pass
            continue
        live.append(
            {
                "server_id": metadata.get("server_id"),
                "started_at": metadata.get("started_at"),
                "version": metadata.get("version"),
                "origin": origin,
                "url": url,
            }
        )
        if url is None:
            warnings.append(unreachable_message(metadata, origin))

    # Keep stdout machine-readable; reachability advice belongs on stderr.
    print(json.dumps(live, indent=2))
    for warning in warnings:
        print(warning, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())