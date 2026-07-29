# Connection Troubleshooting

Use this reference when `execute-code.sh` or MCP cannot reach the intended
marimo session, cannot select a session, or fails because code was passed
incorrectly.

## Targeting

- Pass the discovered `--url` unchanged; `null` means no address was reachable.
- With one open notebook, the script resolves its session.
- Use `--file` for an exact, stable file key or path. It resolves the current
  session on every call.
- Use `--session` for an exact active session ID; it goes stale on reconnect.
- The selectors are mutually exclusive. Preserve supplied values; never guess.

## Auth

For token-authenticated servers, prefer `MARIMO_TOKEN`.

```bash
MARIMO_TOKEN=... bash scripts/execute-code.sh --url http://localhost:2718 -c "1 + 1"
```

`--token` also works, but may expose the token in process listings. If both are
present, `--token` overrides `MARIMO_TOKEN`. The script sends the token as
`Authorization: Bearer ...` on session discovery and code execution requests.

## Code Input

Pass code with `-c CODE`, `-` for stdin, or a file path.

```bash
bash scripts/execute-code.sh --url http://localhost:2718 - <<'PY'
print(df.head())
PY
```

```bash
bash scripts/execute-code.sh --url http://localhost:2718 /tmp/code.py
```

## Common Script Errors

- **`[]` from discover-servers.sh** - nothing is registered. Only servers
  started with `--no-token` register; otherwise ask the user for the URL, or
  start marimo with the project's normal tooling.
- **No active sessions on the server** - open the notebook in the browser.
- **No active session matches `--file`** - check the exact file key against the
  available paths printed by the script.
- **Multiple sessions on server** - several notebooks are open; rerun with the
  `--file` path or `--session` ID shown for the notebook you want.
- **Failed to connect** - check the URL, token, and whether the server is still
  running.
- **Execution did not complete** - the server ended the stream without a
  result. With `--file`, retry the same command so it resolves the current
  session. With `--session`, the ID is probably stale after a page refresh.
- **... is running on the Windows host but answered at no address reachable
  from WSL** - WSL's network cannot reach it. The message lists the fixes; the
  usual one is restarting marimo on the host with `--host 0.0.0.0`. Running the
  scripts from Git Bash or PowerShell on the Windows side also works.
- **needs jq / curl on PATH** - install them in whichever environment runs the
  scripts. Inside WSL that means the distro, not Windows.
- **SyntaxError** - the submitted Python was malformed; use a heredoc or file.
- **ImportError** - diagnose in the notebook kernel. Install packages through
  `cm` when needed.

## Starting marimo

Discover first. If no server is running and the user wants a notebook, use
[finding-marimo.md](finding-marimo.md).
