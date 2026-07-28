# Connection Troubleshooting

Use this reference when `execute-code.sh` or MCP cannot reach the intended
marimo session, cannot select a session, or fails because code was passed
incorrectly.

## Targeting

- `--url` is required, and connects to a marimo server or notebook URL.
- `--session` selects one notebook session on that server.

`discover-servers.sh` reports a `url` for every server it finds, resolved for
wherever the script is running, plus `origin` (`local` or `windows-host`). Pass
it to `--url` as given. A `url` of `null` means the server is running but
nothing answered on any address reachable.

Sessions are resolved automatically when the server has one notebook open. Pass
`--session` only when the script reports several. Session ids go stale on user
page refresh, so be mindful of holding onto session ids for too long. Re-read
it when you need it.

If multiple servers or sessions are available, do not guess. Ask for the URL or
session, or inspect local context.

## Auth

For token-authenticated servers, prefer `MARIMO_TOKEN`.

```bash
MARIMO_TOKEN=... bash scripts/execute-code.sh --url http://localhost:2718 -c "1 + 1"
```

`--token` also works, but may expose the token in process listings. If both are
present, `--token` overrides `MARIMO_TOKEN`. The script sends the token as
`Authorization: Bearer ...` on session discovery and code execution requests.

## Quoting

Use `-c` only for short one-liners. Use a single-quoted heredoc or file input
for multiline code or shell-sensitive characters.

```bash
bash scripts/execute-code.sh --url http://localhost:2718 <<'PY'
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
- **No active sessions on the server** - open the notebook in the browser or
  provide `--session`.
- **Multiple sessions on server** - several notebooks are open; rerun with the
  `--session` id shown next to the filename you want.
- **Failed to connect** - check the URL, token, and whether the server is still
  running.
- **Execution did not complete** - the server ended the stream without a
  result. With `--session`, the id is probably stale after a page refresh;
  retry without it.
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
