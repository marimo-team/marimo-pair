# `marimo._code_mode` API Surface

> This is a **point-in-time snapshot** for retro discussions. The live API may
> differ — always verify with `dir(ctx)` and `help()` in the running session.

## Entry Point

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ...  # all operations go here
```

The `async with` is mandatory — without it, operations silently do nothing.
The context manager auto-compile-checks on exit: syntax errors, multiply-defined
names, and cycles are caught before any graph mutation occurs.

## Context Object (`ctx`)

### Reading State

| Attribute / Method | Returns | Notes |
|-------------------|---------|-------|
| `ctx.cells` | List of cell objects | Each has `.cell_id`, `.code`, `.name` |
| `ctx.graph` | Kernel graph | Has refs/defs info (cells themselves lack this) |
| `dir(ctx)` | All attributes | Always check this first — API evolves |

### Cell Operations (Mutating)

| Operation | Method | Notes |
|-----------|--------|-------|
| Create cell | `ctx.create_cell(code, ...)` | Adds to graph, auto-compile-checks |
| Edit cell | `ctx.edit_cell(cell_id, code, ...)` | Edits existing cell in-place |
| Delete cell | `ctx.delete_cell(cell_id)` | Confirm with user first |
| Move cell | `ctx.move_cell(cell_id, ...)` | Reorder in notebook |

### Execution

| Operation | Method | Notes |
|-----------|--------|-------|
| Execute code (scratchpad) | Via `execute-code.sh` or MCP | Results return to Claude, not user |
| Execute cell | `ctx.run_cell(cell_id)` | Explicitly queue execution; `create_cell` / `edit_cell` are structural only and do not auto-execute |

### Package Management

| Operation | Method | Notes |
|-----------|--------|-------|
| Install package | Explore via `dir(ctx)` | Prefer API over `uv add` |

## Known Friction Points

Track recurring issues here as they surface in retros:

- **Compile-check false positives on delete+create:** When deleting a cell and
  creating a replacement that defines the same variables, the compile check can
  see the old definitions still present and reject the new cell. Workaround:
  use `check=False` or `edit_cell` instead of delete+create.

- **`ctx.cells` lacks refs/defs:** Cell objects don't expose which variables
  they reference or define. Must use `ctx.graph` directly for variable flow
  analysis.
