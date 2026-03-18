---
name: marimo-pair
description: >-
  Collaboration protocol for pairing with a user through a running marimo
  notebook via bundled scripts or MCP. Use when the user asks you to work in,
  build, explore, or modify a marimo notebook — or when you detect a running
  marimo session by listing sessions. Do NOT use for general Python scripting
  outside of marimo or for marimo plugin/package development.
---

> **Notebook metaprogramming** lives in `marimo._code_mode`. You **MUST** use
> `async with` — without it, operations silently do nothing.
>
> All `ctx.*` methods (`create_cell`, `edit_cell`, `delete_cell`,
> `run_cell`, `install_packages`, etc.) are **synchronous** — they queue
> operations and the context manager flushes them on exit. Do **NOT** `await`
> them.
>
> **Cells are not auto-executed.** `create_cell` and `edit_cell` are
> structural — use `run_cell` to queue execution.
>
> ```python
> import marimo._code_mode as cm
>
> async with cm.get_context() as ctx:
>     for c in ctx.cells:
>         print(c.cell_id, c.code[:80])
>     # sync calls — no await
>     cid = ctx.create_cell("x = 1")
>     ctx.install_packages("pandas")
>     ctx.run_cell(cid)
> ```
>
> Explore the API with `dir(ctx)` and `help()` at the start of each session.

# marimo Pair Programming Protocol

You can interact with a running marimo notebook via **bundled scripts** or
**MCP**. Bundled scripts are the default — they work everywhere with no extra
setup. The workflow is identical either way; only the execution method differs.

## Prerequisites

The marimo server must be running with token and skew protection disabled.

### How to invoke marimo

Use the first matching strategy:

| # | Condition | Command | `--sandbox`? |
|---|-----------|---------|-------------|
| 1 | **Project exists** — `pyproject.toml` in cwd or parent | `uv run marimo edit notebook.py --no-token --no-skew-protection` | No (project manages deps) |
| 2 | **No project, `uv` available** | `uvx marimo@latest edit notebook.py --sandbox --no-token --no-skew-protection` | Yes (default) |
| 3 | **No project, no `uv`** — `marimo` on PATH | `marimo edit notebook.py --sandbox --no-token --no-skew-protection` | Yes (default) |

**Detection steps:**
1. Check for `pyproject.toml` in cwd or parents → strategy 1
2. Otherwise check `command -v uv` → strategy 2
3. Otherwise check `command -v marimo` → strategy 3
4. If none found, tell the user to install `uv` or `marimo`

**`--sandbox` is the default when there's no project.** Sandbox mode manages
dependencies in an isolated environment via PEP 723 inline metadata. Only skip
`--sandbox` when inside a project (strategy 1) or when the user explicitly
asks to skip it.

**No python file yet?** If the user asks to create a notebook but doesn't
name one, pick a descriptive filename based on context (e.g., `exploration.py`,
`analysis.py`, `dashboard.py`). Don't ask — just pick something reasonable.

**Do NOT use `--headless` unless the user asks for it.** Omitting it lets
marimo auto-open the browser, which is the expected pairing experience. If the
user explicitly requests headless, offer to open it with
`open http://localhost:<port>`.

If no servers are found, offer to start marimo as a background task. Be
eager — suggest it proactively. The user may also prefer to start it themselves.

**Always discover servers before starting a new one.** Background task
"completed" notifications do not mean the server died — check the output
or run discover before starting another.

## How to Discover Servers and Execute Code

Two operations: **discover servers** and **execute code**.

| Operation | Script | MCP |
|-----------|--------|-----|
| Discover servers | `bash scripts/discover-servers.sh` | `list_sessions()` tool |
| Execute code | `bash scripts/execute-code.sh -c "code"` | `execute_code(code=..., session_id=...)` tool |
| Execute code (complex) | `bash scripts/execute-code.sh /tmp/code.py` | same |

Scripts auto-discover sessions from the registry on disk. Use `--port` to
target a specific server when multiple are running. If the server was started
with `--mcp`, you'll have MCP tools available as an alternative.

**Use a file for complex code.** When code contains quotes, backticks,
`${}` template literals, or multiline strings (common with anywidget ESM
modules), write the code to a temp file with the Write tool first, then pass
the file path as a positional argument. This avoids shell escaping issues
entirely.

**Inline ESM in cell code.** Temp files are for `execute-code.sh` transport
only — never for runtime. Use `"""` for ESM inside `'''` for the cell code.

## First Step: Explore the code_mode Context

The `code_mode` API can change between marimo versions. Your **first
execute-code call** should discover what the running server actually provides:

**Never guess method signatures.** Always `help(ctx.method_name)` before
calling a method for the first time — parameter names and defaults change
across versions.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    print(dir(ctx))
    help(ctx)
```

## Execution Contexts

**execute-code / scratchpad** — runs code in an ephemeral scope. Variables
don't persist between calls and are not registered with the reactive graph.
Mutations to existing notebook objects (e.g. UI state) do take effect.
See [execute-code.md](reference/execute-code.md).

**code_mode context (`ctx`)** — mutates the notebook itself: create/edit/delete
cells, install packages, run visible cells, inspect the reactive graph. Use
`async with cm.get_context() as ctx`. See:
- [execute-code.md — cell operations](reference/execute-code.md#cell-operations--mutating-the-notebook)
- [execute-code.md — other operations](reference/execute-code.md#other-operations)
- [rich-representations.md](reference/rich-representations.md) — custom widgets and visualizations
- [gotchas.md](reference/gotchas.md) — cached module proxies and other traps
- [notebook-improvements.md](reference/notebook-improvements.md) — improving existing notebooks

## Philosophy

marimo notebooks are a dataflow graph — cells are the fundamental unit of
computation, connected by the variables they define and reference. When a cell
runs, marimo automatically re-executes downstream cells. You have full access
to the running notebook.

- **Cells are your main lever.** Use them to break up work and choose how and
  when to bring the human into the loop. Not every cell needs rich output —
  sometimes the object itself is enough, sometimes a summary is better.
  Match the presentation to the intent.
- **Understand intent first.** When clear, act. When ambiguous, clarify.
- **Follow existing signal.** Check imports, `pyproject.toml`, existing cells,
  and `dir(ctx)` before reaching for external tools.
- **Stay focused.** Build first, polish later — cell names, layout, and styling
  can wait.

## Guard Rails

Skip these and the UI breaks:

- **Install packages via `ctx.install_packages()`, not `uv add` or `pip`.**
  The code API handles kernel restarts and dependency resolution correctly.
  Only fall back to external CLIs if the API is unavailable or fails.
- **Custom widget = anywidget.** For bespoke visual components, use anywidget
  with HTML/CSS/JS. Composed `mo.ui` is fine for simple forms and controls.
  See [rich-representations.md](reference/rich-representations.md).
- **NEVER write to the `.py` file directly while a session is running — the kernel owns it.**
- **No temp-file deps in cells.** `pathlib.Path("/tmp/...")` in cell code is a bug.
- **Avoid empty cells.** Prefer `edit_cell` into existing empty cells rather
  than creating new ones. Clean up any cells that end up empty after edits.
- **Don't worry about cell names.** Names are not required for cells and are
  hard to come up with while working. Skip them by default — it's easier
  to add meaningful names later when reviewing the notebook as a whole.

Confirm with the user before:

- **Installing packages** — adds dependencies to their project.
- **Deleting cells** — removes work that may not be recoverable.
