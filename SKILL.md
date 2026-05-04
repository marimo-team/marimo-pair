---
name: marimo-pair
description: >-
  Execute code in a running marimo notebook via HTTP API. Use ONLY when the
  user explicitly asks to work with a marimo notebook or marimo session.
allowed-tools: Bash(bash **/scripts/discover-servers.sh *), Bash(bash **/scripts/execute-code.sh *), Read
---

# marimo Pair Programming Protocol

Pair-program inside a running marimo notebook. You execute code via bundled
scripts that talk to marimo's HTTP API — no marimo install needed on your side.

## Discover and Execute

```bash
# find running servers
bash scripts/discover-servers.sh

# execute code (one-liner)
bash scripts/execute-code.sh -c "1 + 1"

# execute code (multiline — use heredoc, NOT -c with semicolons)
bash scripts/execute-code.sh <<'EOF'
import marimo._code_mode as cm
async with cm.get_context() as ctx:
    ctx.create_cell("x = 1")
EOF

# target specific server
bash scripts/execute-code.sh --port 2718 -c "print('hello')"
bash scripts/execute-code.sh --url http://localhost:2718 -c "print('hello')"
```

Use `--session ID` to target a specific notebook when multiple are open
on the same server.

Auth: set `MARIMO_TOKEN` env var if the server has token auth.
Only `--no-token` servers are auto-discoverable in the registry.

## Starting marimo

**Always discover before starting.** If no server is running, start one
as a **background task** (use `run_in_background` on the Bash tool):

```bash
# inside a uv project with marimo in deps
uv run marimo edit notebook.py --no-token
# outside a project
uvx marimo@latest edit notebook.py --no-token --sandbox
```

Do NOT use `--headless` unless the user asks.

## Executing Code

Code runs in the notebook kernel. Variables from executed cells are in scope
(cells that haven't been run yet in this session are not available). Nothing
persists between calls (variables, imports reset), but you can inspect state.

To mutate the notebook (create/edit/delete cells, install packages):

```python
import marimo._code_mode as cm
async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = 1")
    ctx.packages.add("pandas")
    ctx.run_cell(cid)
    ctx.edit_cell(cid, code="x = 2")
```

- **`async with` is required** — without it, operations silently do nothing.
  Use it directly (kernel supports top-level await). Do NOT wrap in
  `async def main()` + `asyncio.run()`.
- `ctx.*` methods are synchronous — they queue; the context manager flushes.
  Do NOT `await` them.
- `create_cell`/`edit_cell` are structural — use `run_cell` to execute.
- Explore the API with `help(cm)` at the start of each session.

## Critical Rules

- **NEVER `Edit`/`Write` the `.py` file while a session is running.** Direct
  writes are silently destroyed. Use `ctx.edit_cell()` for all changes.
  (`Read` is okay but may lag — prefer `ctx.cells[target].code`.)
- **Install packages via `ctx.packages.add()`, not `uv add` or `pip`.**
- **No temp-file deps in cells** (`/tmp/...` paths break on restart).
- **Variables with `_` prefix are cell-private** (can't reference from other cells).
- **Duplicate public imports across cells** cause `Multiply-defined names` errors.
- **Deletions are destructive.** Deleting a cell removes its variables from
  kernel memory. If intent is ambiguous, ask first.
- **Installing packages changes the project** — confirm when not obvious.
- **The user is editing too** — re-inspect notebook state if it's been a while.

## Widgets

For `mo.ui.*` elements, use `ctx.set_ui_value(element, new_value)` in code_mode.
For anywidgets, set traitlets directly: `widget.value = 5`.

## Reference docs (read on demand)

Detailed guides are in `reference/` — read them when you need specifics:
- `reference/finding-marimo.md` — invocation decision tree (uv, pixi, global, sandbox)
- `reference/gotchas.md` — cached module proxies, polars+pyarrow workaround
- `reference/rich-representations.md` — anywidget, `_display_()`, reactive widgets
- `reference/notebook-improvements.md` — setup cells, `mo.persistent_cache`
