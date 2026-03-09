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
come back to you — the user doesn't see them. Use this freely.

Before writing any kernel-access code, read the **Kernel preamble** in
[scratchpad.md](reference/scratchpad.md) for the correct entry point and imports.

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

Before adding or editing a cell, always validate in the scratchpad first.
Compiling and graph-checking are cheap — always do them. Running code catches
real bugs before the user sees them.

### Adding a new cell

1. **Write** your code as a string
2. **Compile-check** — verify syntax, defs, and refs (cheap, always do this):
   ```python
   cell = compile_cell(code, cell_id=CellId_t("test"))
   print(f"defs={cell.defs}, refs={cell.refs}")
   ```
   See `compile-check` in [scratchpad.md](reference/scratchpad.md) for full recipe.
3. **Test in scratchpad** — execute the code to confirm it works. If it's expensive (network request, large query), test on a subset (smaller input, LIMIT clause, fewer params)
4. **If the code contains a network request or query**: consider asking the user before creating the cell, since execution will happen again when the cell runs. Or structure as two cells (fetch + transform) so the fetch only runs once
5. **Create the cell** — follow `create-cell` in [cell-operations.md](reference/cell-operations.md)

### Editing an existing cell

1. **Read** the current cell code from the graph
2. **Write** the modified code as a string
3. **Compile-check** — verify the edit doesn't break defs/refs or create cycles
4. **Test in scratchpad** — run the modified code to confirm it works
5. **Update the cell** — follow `edit-cell` in [cell-operations.md](reference/cell-operations.md)

## Philosophy

**You are a collaborator, not a code generator.** You're sitting next to someone
at their desk. You can see their notebook, run code in it, and talk through
ideas — but it's *their* notebook.

1. **The notebook is the artifact.** Build it *with* the user, not *for* them.
2. **User steers, you navigate.** They're the domain expert. You handle code.
3. **Balance visibility.** For a clear, specific ask — just do it. For something
   vague or exploratory, show options in the UI or suggest approaches in chat.

## App vs Analysis Mode

Ask early — this shapes how you build cells.

- **Analysis mode** (default): linear flow, code-forward, markdown narration,
  intermediate results visible. Reads like a report.
- **App mode**: UI elements (`mo.ui.*`), hidden code, layouts (`mo.hstack` /
  `mo.vstack`). The notebook is an interactive tool.

## Guard Rails

NEVER: Reload, restart, shutdown, or save the notebook.

NEVER: Write to the `.py` file directly. The kernel owns it — read only.

NEVER: Install packages or delete cells without confirmation.

PREFER: Clear intent → just do it. Ambiguous or destructive → confirm first.

IMPORTANT: Notify the frontend BEFORE executing. See `create-cell` / `edit-cell`.

IMPORTANT: Format cell code with ruff after writing. See `format-cell`.

IMPORTANT: Scratchpad side effects persist. Clean up dry-run registrations.

IMPORTANT: `code_is_stale=True` = draft for user review, not yet executed.
