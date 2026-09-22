#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Execute code in a running marimo session's scratchpad.

This client talks directly to marimo's HTTP API and therefore does not require
marimo in its own environment. It resolves a browser session, submits code,
and relays the server-sent event stream without buffering stdout or stderr.

The command-line interface intentionally matches ``execute-code.sh`` so callers
can move between implementations without changing how they select sessions,
provide code, or authenticate.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

# -------------------------------------------------------------- command line


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Execute code in a running marimo session's scratchpad.",
        epilog=(
            "Set MARIMO_TOKEN for authenticated servers. "
            "Run discover_servers.py to find the URL."
        ),
    )
    parser.add_argument("--url", required=True)
    parser.add_argument("--token", default=os.environ.get("MARIMO_TOKEN", ""))
    selectors = parser.add_mutually_exclusive_group()
    selectors.add_argument("--file")
    selectors.add_argument("--session")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("-c", "--code")
    source.add_argument("script", nargs="?", help="Python file, or - for stdin")
    args = parser.parse_args()
    if args.code is None and args.script is None:
        parser.error("provide code with -c, -, or a file path")
    return args


def read_code(args: argparse.Namespace) -> str:
    if args.code is not None:
        return args.code
    if args.script == "-":
        return sys.stdin.read()
    try:
        return Path(args.script).read_text(encoding="utf-8")
    except OSError as error:
        raise SystemExit(f"Could not read {args.script!r}: {error}") from error


def authorization_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"} if token else {}


# --------------------------------------------------------- session selection


def request_json(url: str, headers: dict[str, str]) -> Any:
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as error:
        raise RuntimeError(str(error)) from error


def session_label(session_id: str, session: dict[str, Any]) -> str:
    return f"{session_id}  {session.get('path') or session.get('filename') or ''}"


def resolve_session(
    base_url: str,
    headers: dict[str, str],
    selected_file: str | None,
    selected_session: str | None,
) -> str:
    """Resolve a stable file key or the server's sole active session."""
    if selected_session:
        # Explicit session IDs are ephemeral but need no discovery request.
        return selected_session

    try:
        sessions = request_json(f"{base_url}/api/sessions", headers)
    except RuntimeError as error:
        raise SystemExit(
            f"Failed to connect to marimo server at {base_url}: {error}"
        ) from error

    if not sessions:
        raise SystemExit(
            "No active sessions on the server. Make sure a notebook is open "
            "in the browser."
        )

    if selected_file:
        matches = [
            session_id
            for session_id, session in sessions.items()
            if session.get("path") == selected_file
            or session.get("filename") == selected_file
        ]
        if not matches:
            available = "\n".join(
                session_label(session_id, session)
                for session_id, session in sessions.items()
            )
            raise SystemExit(
                f"No active session matches --file {selected_file!r}. "
                f"Available sessions:\n{available}"
            )
        if len(matches) > 1:
            matching = "\n".join(
                session_label(session_id, sessions[session_id])
                for session_id in matches
            )
            raise SystemExit(
                f"Multiple active sessions match --file {selected_file!r}:\n"
                f"{matching}"
            )
        return matches[0]

    if len(sessions) > 1:
        available = "\n".join(
            session_label(session_id, session)
            for session_id, session in sessions.items()
        )
        raise SystemExit(
            "Multiple sessions on server. Select one with --file or "
            f"--session:\n{available}"
        )
    return next(iter(sessions))


# ------------------------------------------------------------ trust boundary


def is_wsl() -> bool:
    """Return whether this process is running under Windows Subsystem for Linux."""
    if "WSL_DISTRO_NAME" in os.environ:
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False


def wsl_gateway() -> str | None:
    if not is_wsl():
        return None
    try:
        route = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True,
            check=False,
            text=True,
        ).stdout.split()
        if "via" in route:
            return route[route.index("via") + 1]
    except OSError:
        pass
    return None


def warn_if_remote(url: str) -> None:
    """Warn before sending notebook data to a host that is not local."""
    host = urllib.parse.urlsplit(url).hostname
    if not host or host in {"localhost", "127.0.0.1", "::1", "0.0.0.0"}:
        return
    if host != wsl_gateway():
        print(
            f"Warning: connecting to non-local server {host!r}. "
            "Ensure this is trusted.",
            file=sys.stderr,
        )


# ---------------------------------------------------------------- execution


def print_event(event: str, payload: dict[str, Any]) -> bool:
    if event == "stdout":
        print(payload.get("data", ""), end="", flush=True)
    elif event == "stderr":
        print(payload.get("data", ""), end="", file=sys.stderr, flush=True)
    elif event == "done":
        if not payload.get("success", True):
            return False
        output = payload.get("output") or {}
        if output.get("data") is not None:
            print(output["data"])
    return True


def execution_failed(detail: object, retry_hint: str | None) -> bool:
    """Report an execution failure with selector-specific recovery advice."""
    print(f"Execution did not complete: {detail}", file=sys.stderr)
    if retry_hint:
        print(retry_hint, file=sys.stderr)
    return False


def execute(
    base_url: str,
    headers: dict[str, str],
    session_id: str,
    code: str,
    retry_hint: str | None = None,
) -> bool:
    """Submit code and relay marimo's SSE stream; return whether it succeeded."""
    request_headers = {
        **headers,
        "Content-Type": "application/json",
        "Marimo-Session-Id": session_id,
    }
    body = json.dumps({"code": code}).encode()
    request = urllib.request.Request(
        f"{base_url}/api/kernel/execute",
        data=body,
        headers=request_headers,
        method="POST",
    )
    current_event = ""
    done_received = False
    success = True
    try:
        with urllib.request.urlopen(request) as response:
            for raw_line in response:
                # SSE permits CRLF. Each marimo event currently carries one
                # JSON data line, with stdout/stderr preceding the final done.
                line = raw_line.decode("utf-8").rstrip("\r\n")
                if line.startswith("event:"):
                    current_event = line.removeprefix("event:").strip()
                elif line.startswith("data:"):
                    payload = json.loads(line.removeprefix("data:").strip())
                    success = print_event(current_event, payload)
                    if current_event == "done":
                        done_received = True
                        break
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        try:
            detail = json.loads(detail).get("detail", detail)
        except json.JSONDecodeError:
            pass
        return execution_failed(detail, retry_hint)
    except (TimeoutError, urllib.error.URLError, json.JSONDecodeError) as error:
        return execution_failed(error, retry_hint)

    if not done_received:
        # An HTTP 200 without `done` still means the code never completed.
        return execution_failed(
            "the server ended the stream without a result.",
            retry_hint,
        )
    return success


def log_execution() -> None:
    """Record an invocation without logging code, tokens, or notebook data."""
    log_path = os.environ.get("EXECUTE_CODE_LOG")
    if log_path:
        timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with Path(log_path).open("a", encoding="utf-8") as log:
            log.write(f"{timestamp}\n")


def stale_session_hint(
    selected_file: str | None,
    selected_session: str | None,
) -> str | None:
    """Explain how to recover when a browser reconnect changes its session ID."""
    if selected_file:
        return (
            "The session for --file may have changed during execution. "
            "Retry the same --file command."
        )
    if selected_session:
        return (
            "The --session id may be stale: marimo renames a session when the "
            "browser reconnects. Retry without --session."
        )
    return None


def main() -> int:
    args = parse_args()
    log_execution()
    base_url = args.url.rstrip("/")
    warn_if_remote(base_url)
    headers = authorization_headers(args.token)
    session_id = resolve_session(base_url, headers, args.file, args.session)
    retry_hint = stale_session_hint(args.file, args.session)
    return 0 if execute(base_url, headers, session_id, read_code(args), retry_hint) else 1


if __name__ == "__main__":
    raise SystemExit(main())