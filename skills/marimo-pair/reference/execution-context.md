# Connection troubleshooting

## Find the intended notebook

Use `marimo pair list` for local discovery. If the user gives a server URL,
preserve its base path and pass it to `list`. Use the same URL and notebook
ID for execution. A URL alone selects a notebook only when exactly one is
open on that server.

```sh
marimo pair list --url SERVER_URL
marimo pair execute --url SERVER_URL --notebook NOTEBOOK_ID --code 'print(1 + 1)'
```

If the notebook is missing, check the listing's warnings. A running server
can have no open notebook. Open the requested notebook in the browser and
start its kernel, then list it again. For startup options, see
[Finding and invoking marimo](finding-marimo.md).

If an existing connection supplies a stable session ID, keep using it with
`execute --url SERVER_URL --session SESSION_ID`. Inbox connections use a
notebook ID, which you can obtain with `pair list`.

## Authenticate to the server

Local discovery uses private credentials automatically. For a server that
requires explicit credentials, use the supplied token file or the
`MARIMO_TOKEN` environment variable. Keep token values out of command output.

```sh
marimo pair list --url SERVER_URL --token-file TOKEN_PATH
marimo pair execute --url SERVER_URL --notebook NOTEBOOK_ID --token-file TOKEN_PATH --code 'print(1 + 1)'
```

If authentication fails, check the credentials for the same server. If the
URL is unreachable, verify that the server is running and that the URL is
reachable from the environment running the CLI.

## Check an interrupted execution

By default `execute` returns a JSON result. Read its `error` and `next` fields
when it fails. If completion was unconfirmed, the code may already have run.
Inspect the same notebook before taking another action. For example, after
adding a cell, check its source and status:

```sh
marimo pair execute --notebook NOTEBOOK_ID --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code, cell.status, cell.errors)
PYTHON
```

For remote notebooks include the same `--url` and authentication options.
For a Python exception, inspect the kernel traceback. Use `--file -` or
`--file PATH` for multiline input so shell quoting preserves the Python.
