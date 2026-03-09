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

You can interact with a running marimo notebook via **bundled scripts** or
**MCP**. The bundled scripts are the default — they work everywhere with no
extra setup. The workflow is identical either way; only the execution method
differs.

## Prerequisites

The marimo server must be started with token and skew protection disabled:

```bash
marimo edit notebook.py --no-token --no-skew-protection
```

This allows the scripts to talk to the HTTP API without authentication.

## How to List Sessions and Execute Code

There are two operations: **list sessions** and **execute code**. Use the
bundled scripts — they talk directly to the marimo HTTP API with no
dependencies beyond `bash`, `curl`, and `jq`.

| Operation | Script | MCP |
|-----------|--------|-----|
| List sessions | `bash scripts/list-sessions.sh` | `list_sessions()` tool |
| Execute code | `bash scripts/execute-code.sh "code"` | `execute_code(code=..., session_id=...)` tool |

The scripts auto-discover sessions from the registry on disk. Use `--port`
to target a specific server when multiple are running.

If the marimo server was started with `--mcp`, you'll have MCP tools
available as an alternative.

The rest of this skill refers to "list sessions" and "execute code" generically.

## Two Modes of Working

Executing code is your only way to interact with the notebook. It serves two
distinct purposes:

**Scratchpad** (simple): Just Python — `print(df.head())`, check data shapes,
test a snippet. The notebook's cell variables are already in scope. Results
come back to you — the user doesn't see them. You can also read and set UI
element state programmatically (see [ui-state](reference/scratchpad.md#ui-state)).
Use this freely.

The kernel preamble in [scratchpad.md](reference/scratchpad.md) has the correct
entry point and imports for kernel-access code.

**Cell operations** (complex): Creating, editing, moving, deleting cells.
These require careful API orchestration — compile, register, notify the
frontend, then execute. Get it wrong and the UI desyncs.

## Decision Tree

| Situation | Action |
|-----------|--------|
| Need to find running sessions | List sessions |
| Need to read data/state | Use recipes in [scratchpad.md](reference/scratchpad.md) via execute code |
| Need to create/edit/move/delete cells | Follow the scratchpad-to-cell workflow below, then use [cell-operations.md](reference/cell-operations.md) |
| Unsure what API to use | See **Discovering the API** in [kernel-api.md](reference/kernel-api.md) |
| Import path fails | See **Discovering the API** in [kernel-api.md](reference/kernel-api.md) |
| Want a full walkthrough | Read [worked-example.md](reference/worked-example.md) |

## The Scratchpad-to-Cell Workflow

Always compile-check before creating or editing a cell — it's cheap and catches
real bugs (syntax errors, broken refs, cycles) before the user sees them.

For non-trivial code, test in the scratchpad first. The user doesn't see
scratchpad output, so it's a safe place to iterate. For expensive operations
(network requests, large queries), test on a subset.

### Adding a new cell

- **Write** your code as a string
- **Compile-check** — verify syntax, defs, and refs:
  ```python
  cell = compile_cell(code, cell_id=CellId_t("test"))
  print(f"defs={cell.defs}, refs={cell.refs}")
  ```
  See `compile-check` in [scratchpad.md](reference/scratchpad.md) for full recipe.
- **Test in scratchpad** if the code is non-trivial
- **Create the cell** — follow `create-cell` in [cell-operations.md](reference/cell-operations.md)

### Editing an existing cell

- **Read** the current cell code from the graph
- **Write** the modified code as a string
- **Compile-check** — verify the edit doesn't break defs/refs or create cycles
- **Test in scratchpad** if the change is non-trivial
- **Update the cell** — follow `edit-cell` in [cell-operations.md](reference/cell-operations.md)

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

- Format with ruff after writing code.
- Validate before writing to the notebook. If you're uncertain about an API or
  behavior, test in the scratchpad first — the user doesn't see errors there.
  For expensive operations (network requests, large queries), test on an
  equivalent subset.
- Keep cells small and focused.
- `code_is_stale=True` sends a draft for user review without executing.

## API Contract

Skip these and the UI breaks:

- Notify the frontend before executing cell operations.
  See `create-cell` / `edit-cell` in [cell-operations.md](reference/cell-operations.md).
- Compile-check before creating or editing cells.
- Clean up dry-run registrations — scratchpad side effects persist in the graph.
- Don't write to the `.py` file directly — the kernel owns it.

## User's Environment

Confirm before:

- **Installing packages** — adds dependencies to the project.
- **Deleting cells** — removes work that may not be recoverable.
