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
> ```python
> import marimo._code_mode as cm
>
> async with cm.get_context() as ctx:
>     for c in ctx.cells:
>         print(c.cell_id, c.code[:80])
> ```
>
> Explore the API with `dir(ctx)` and `help()` at the start of each session.

# marimo Pair Programming Protocol

You can interact with a running marimo notebook via **bundled scripts** or
**MCP**. Bundled scripts are the default — they work everywhere with no extra
setup. The workflow is identical either way; only the execution method differs.

## Prerequisites

The marimo server must be running with token and skew protection disabled:

```bash
marimo edit notebook.py --no-token --no-skew-protection
```

By default, omit `--headless` so marimo auto-opens the browser. If you use
`--headless`, offer to open it with `open http://localhost:<port>`.

If no servers are found, offer to start marimo as a background task. Be
eager — suggest it proactively. The user may also prefer to start it themselves.

## How to Discover Servers and Execute Code

Two operations: **discover servers** and **execute code**.

| Operation | Script | MCP |
|-----------|--------|-----|
| Discover servers | `bash scripts/discover-servers.sh` | `list_sessions()` tool |
| Execute code | `bash scripts/execute-code.sh "code"` | `execute_code(code=..., session_id=...)` tool |

Scripts auto-discover sessions from the registry on disk. Use `--port` to
target a specific server when multiple are running. If the server was started
with `--mcp`, you'll have MCP tools available as an alternative.

## First Step: Explore the code_mode Context

The `code_mode` API can change between marimo versions. Your **first
execute-code call** should discover what the running server actually provides:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    print(dir(ctx))
    help(ctx)
```

## Two Modes of Working

**Scratchpad** (simple): Just Python — `print(df.head())`, check data shapes,
test a snippet. Cell variables are already in scope. Results come back to
you — the user doesn't see them. You can also read and set UI element state
programmatically (see [ui-state](reference/execute-code.md#ui-state)). The
kernel preamble in [execute-code.md](reference/execute-code.md) has the correct
entry point and imports.

**Cell operations** (complex): Creating, editing, moving, deleting cells.
These require careful API orchestration — compile, register, notify the
frontend, then execute. Get it wrong and the UI desyncs.

## Decision Tree

| Situation | Action |
|-----------|--------|
| Need to find running servers | Discover servers |
| Need to read data/state | Use scratchpad recipes in [execute-code.md](reference/execute-code.md) |
| Need to create/edit/move/delete cells | Follow the scratchpad-to-cell workflow below, then use [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook) |
| Need to install a package | Use the `code_mode` context — see [Installing Packages](#installing-packages) |
| Unsure what API to use | See **Discovering the API** in [execute-code.md](reference/execute-code.md#discovering-the-api) |
| Import path fails | See **Discovering the API** in [execute-code.md](reference/execute-code.md#discovering-the-api) |
| Need a custom visualization or interactive widget | See [rich-representations.md](reference/rich-representations.md) (`_display_()` for display-only, anywidget for bidirectional) |
| Widget trait should drive downstream cells | `mo.state()` + `.observe()` — see [Reactive anywidgets](reference/rich-representations.md#reactive-anywidgets-in-marimo) |
| Need to display a notification to the user (toast, banner, focus) | See [other operations](reference/execute-code.md#other-operations) |

## The Scratchpad-to-Cell Workflow

**The cardinal rule: never show the user broken code.** Runtime errors in cells
are a bad experience. Runtime errors in the scratchpad are invisible learning.

**Compile-check is not validation.** It catches syntax errors, broken refs, and
cycles — but not wrong arguments, missing methods, or type mismatches. Don't
let a passing compile-check give you false confidence.

**ALWAYS compile-check AND test in the scratchpad before creating or editing a
cell.** No exceptions unless the user explicitly says to skip testing. If the
code is expensive, test on a subset — or if that's not possible, ask the user.

If both pass, do the cell operation immediately — in the same execute-code call
when possible. Never pause to ask; the only reason to pause is ambiguous intent.

### Steps (same for add or edit)

1. If editing, **read** the current cell code from the graph
2. **Compile-check** — verify syntax, defs, refs, no cycles. For new cells,
   check `defs` against existing cells — duplicate defs break the graph.
3. **Test in scratchpad** — run the code to validate at runtime
4. **Create or update the cell** — the mechanical step. See
   [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook).

Keep cells small and focused. Use `code_is_stale=True` to send a draft for
user review without executing.

## Philosophy

You have full access to the running notebook. When the user's intent is clear,
act on it. When it's ambiguous, clarify.

Before reaching for external tools or CLIs, explore what `ctx` and marimo
already provide — marimo has integrations for many common operations (e.g.,
installing packages). Use `dir(ctx)` and `help()` to discover capabilities.

Before making choices, look for signal — notebook imports, `pyproject.toml`,
`sys.modules`, existing cells, directory structure. Follow existing patterns.
Take agency over things you're confident in. If you're not sure, ask.

## Installing Packages

The `code_mode` context exposes package installation capabilities. Explore
`dir(ctx)` and `help()` to find the right method — don't guess the API, as it
may change across marimo versions.

Always try the code API first. Only fall back to external CLIs (`uv add`,
`uv pip install`, etc.) if the API is unavailable or fails.

## Guard Rails

Skip these and the UI breaks:

- Notify the frontend before executing cell operations — use `_code_mode`.
- Compile-check before creating or editing cells.
- Clean up dry-run registrations — scratchpad side effects persist in the graph.
- Don't write to the `.py` file directly — the kernel owns it.

Confirm with the user before:

- **Installing packages** — adds dependencies to their project.
- **Deleting cells** — removes work that may not be recoverable.
