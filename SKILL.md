---
name: marimo-pair
description: >-
  Collaboration protocol for pairing with a user through a running marimo
  notebook via bundled scripts or MCP. Use when the user asks you to work in,
  build, explore, or modify a marimo notebook — or when you detect a running
  marimo session by listing sessions. Do NOT use for general Python scripting
  outside of marimo or for marimo plugin/package development.
---

# marimo Pair Programming Protocol

This skill gives you full access to a running marimo notebook. You can read
cell code, create and edit cells, install packages, run cells, and inspect
the reactive graph — all programmatically. The user sees results live in their
browser while you work through bundled scripts or MCP.

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

## Executing Code

Every execute-code call runs inside the notebook's kernel. All cell variables
are in scope — `print(df.head())` just works. Nothing you define persists
between calls (variables, imports, side-effects all reset), but you can freely
introspect the notebook: inspect variables, test code snippets, check types
and shapes. Use this to explore, prototype, and validate before committing
anything to the notebook — then create cells to persist state and make results
visible to the user.

To mutate the notebook's dataflow graph — create, edit, and delete cells,
install packages, and run cells — use `marimo._code_mode`:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = 1")
    ctx.install_packages("pandas")
    ctx.run_cell(cid)
```

You **must** use `async with` — without it, operations silently do nothing.
All `ctx.*` methods are **synchronous** — they queue operations and the
context manager flushes them on exit. Do **not** `await` them.

**Cells are not auto-executed.** `create_cell` and `edit_cell` are structural
changes only — use `run_cell` to queue execution.

`code_mode` is a tested, safe API for notebook mutations — prefer it for all
structural changes. You also have access to marimo internals from the kernel,
but treat that as a last resort and only with high confidence after exploration.

**UI state lives outside the reactive graph.** Anywidget traitlets can be read
or set directly (e.g., `slider.value = 5`). For `mo.ui.*` elements, use
`ctx.set_ui_value(element, new_value)` inside `code_mode`.

### First Step: Explore the API

The `code_mode` API can change between marimo versions — and each running
server could be a different version. Inspect what's available at the start of
each session, especially when switching between servers.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx  # inspect me — dir(), help(), .cells, ...
```

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
- **Don't worry about cell names.** Most cells don't need explicit names —
  see [notebook-improvements.md](reference/notebook-improvements.md#cell-names).

## Widgets and Reactivity

Anywidget state (traitlets) lives outside marimo's reactive graph. To hook a
widget trait into the graph, pick one strategy per widget — never mix them:

- **`mo.state` + `.observe()`** — you pick specific traits to bridge. Default choice.
- **`mo.ui.anywidget()`** — wraps all synced traits into one reactive `.value`. Convenient but coarser.

Read [rich-representations.md](reference/rich-representations.md) before wiring either.

## Keep in Mind

- **The user is editing too.** The notebook can change between your calls —
  re-inspect notebook state if it's been a while since you last looked.
- **Deletions are destructive.** Deleting a cell removes its variables from
  kernel memory — restoring means recreating the cell and re-running it and
  its dependents. If intent seems ambiguous, ask first.
- **Installing packages changes the project.** `ctx.install_packages()` adds
  real dependencies — confirm when it's not obvious from context.

## References

- [gotchas.md](reference/gotchas.md) — cached module proxies and other traps
- [rich-representations.md](reference/rich-representations.md) — custom widgets and visualizations
- [notebook-improvements.md](reference/notebook-improvements.md) — improving existing notebooks
