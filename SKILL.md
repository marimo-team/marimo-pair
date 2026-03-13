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
**MCP**. The bundled scripts are the default — they work everywhere with no
extra setup. The workflow is identical either way; only the execution method
differs.

## Prerequisites

The marimo server must be running with token and skew protection disabled:

```bash
marimo edit notebook.py --no-token --no-skew-protection
```

If no servers are found when you discover servers, offer to start marimo for the
user as a background task. Be eager — suggest it proactively rather than
waiting for them to figure it out. They may also prefer to start it themselves.

## How to Discover Servers and Execute Code

There are two operations: **discover servers** and **execute code**. Use the
bundled scripts — they talk directly to the marimo HTTP API with no
dependencies beyond `bash`, `curl`, and `jq`.

| Operation | Script | MCP |
|-----------|--------|-----|
| Discover servers | `bash scripts/discover-servers.sh` | `list_sessions()` tool |
| Execute code | `bash scripts/execute-code.sh "code"` | `execute_code(code=..., session_id=...)` tool |

The scripts auto-discover sessions from the registry on disk. Use `--port`
to target a specific server when multiple are running.

If the marimo server was started with `--mcp`, you'll have MCP tools
available as an alternative.

The rest of this skill refers to "discover servers" and "execute code" generically.

## Two Modes of Working

Executing code is your only way to interact with the notebook. It serves two
distinct purposes:

**Scratchpad** (simple): Just Python — `print(df.head())`, check data shapes,
test a snippet. The notebook's cell variables are already in scope. Results
come back to you — the user doesn't see them. You can also read and set UI
element state programmatically (see [ui-state](reference/execute-code.md#ui-state)).
Use this freely.

The kernel preamble in [execute-code.md](reference/execute-code.md) has the correct
entry point and imports for kernel-access code.

**Cell operations** (complex): Creating, editing, moving, deleting cells.
These require careful API orchestration — compile, register, notify the
frontend, then execute. Get it wrong and the UI desyncs.

## Decision Tree

| Situation | Action |
|-----------|--------|
| Need to find running servers | Discover servers |
| Need to read data/state | Use scratchpad recipes in [execute-code.md](reference/execute-code.md) |
| Need to create/edit/move/delete cells | Follow the scratchpad-to-cell workflow below, then use [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook) |
| Unsure what API to use | See **Discovering the API** in [execute-code.md](reference/execute-code.md#discovering-the-api) |
| Import path fails | See **Discovering the API** in [execute-code.md](reference/execute-code.md#discovering-the-api) |
| Need a custom visualization or interactive widget | See [rich-representations.md](reference/rich-representations.md) (`_display_()` for display-only, anywidget for bidirectional) |
| Widget trait should drive downstream cells | `mo.state()` + `.observe()` — see [Reactive anywidgets](reference/rich-representations.md#reactive-anywidgets-in-marimo) |
| Need to display a notification to the user (toast, banner, focus) | See [other operations](reference/execute-code.md#other-operations) |

## The Scratchpad-to-Cell Workflow

**The cardinal rule: never show the user broken code.** Runtime errors in cells
are a bad experience. Runtime errors in the scratchpad are invisible learning.

**Compile-check is not validation.** It catches syntax errors, broken refs, and
cycles — but tells you nothing about whether the code will actually run. Wrong
arguments, missing methods, type mismatches — all pass compile-check and blow
up at runtime. Don't let a passing compile-check give you false confidence.

**ALWAYS compile-check AND test in the scratchpad before creating or editing a
cell.** No exceptions unless the user explicitly tells you to skip testing.
Compile-check, then run the code in the scratchpad. Only create or edit the
cell after both pass. If the code is expensive (slow queries, large network
requests), test on a subset — or if that's not possible, ask the user.

If both pass, creating or editing the cell is trivial — the validation already
happened. Do it immediately in the same execute-code call as the test when
possible. Never pause to ask; the only reason to pause is ambiguous intent,
not routine cell operations.

### Adding a new cell

- **Compile-check** — verify syntax, defs, and refs. Check new cell's `defs`
  against existing cells — duplicate defs break the graph.
- **Test in scratchpad** — ALWAYS run the code to validate it works at runtime.
  If expensive, test on a subset or ask the user.
- **Create the cell** — this is just the mechanical step. If the above passed,
  do it right away. See [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook).

### Editing an existing cell

- **Read** the current cell code from the graph
- **Compile-check** — verify the edit doesn't break defs/refs or create cycles
- **Test in scratchpad** — ALWAYS run the code to validate it works at runtime.
  If expensive, test on a subset or ask the user.
- **Update the cell** — this is just the mechanical step. If the above passed,
  do it right away. See [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook).

## Philosophy

You have full access to the running notebook — read state, run code, create and
edit cells. Read the user's intent and act on it. When the intent is clear,
go ahead. When it's ambiguous, clarify.

Data work has a lot of implicit context — preferred libraries, naming
conventions, data sources, domain assumptions, how they like results presented.
Acting without understanding this context wastes effort and doesn't serve the
user. Acting aligned with it is high-impact.

You're running in the user's environment. Before making choices, look for
signal — notebook imports, `pyproject.toml`, `sys.modules`, existing cells,
project files, directory structure. If you find a pattern, follow it. If
there's little signal, be resourceful and try to find it. Take agency and
ownership over things you're confident in. If you're not sure, ask.

## How to Write Good Cells

- Validate before writing to the notebook. If you're uncertain about an API or
  behavior, test in the scratchpad first — the user doesn't see errors there.
  For expensive operations (network requests, large queries), test on an
  equivalent subset.
- Keep cells small and focused.
- `code_is_stale=True` sends a draft for user review without executing.

## API Contract

Skip these and the UI breaks:

- Notify the frontend before executing cell operations.
  Use `_code_mode` — see [execute-code.md](reference/execute-code.md#cell-operations--mutating-the-notebook).
- Compile-check before creating or editing cells.
- Clean up dry-run registrations — scratchpad side effects persist in the graph.
- Don't write to the `.py` file directly — the kernel owns it.

## User's Environment

Confirm before:

- **Installing packages** — adds dependencies to the project.
- **Deleting cells** — removes work that may not be recoverable.
