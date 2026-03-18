# Execute Code Reference

Everything you do in the notebook goes through execute-code. This file covers
both inspection (reading state) and mutation (creating/editing/deleting cells).

## Scratchpad — ephemeral inspection

The scratchpad is just Python. Cell variables are in scope — `print(df.head())`
works directly. Results come back to you; the user doesn't see them.

**Scoping:** Nothing persists between scratchpad calls — variables, imports,
side-effects all reset. Only notebook cell variables survive. The only way to
persist state is to add cells to the notebook.

### Kernel preamble

Only needed for recipes that access `kernel` or `graph`:

```python
from marimo._runtime.context import get_context

kernel = get_context()._kernel
graph = kernel.graph
```

### list-cells

```python
for cid, cell in graph.cells.items():
    print(cid, cell.defs, cell.refs, cell.code[:80])
```

### cell-status

```python
for cid, cell in graph.cells.items():
    print(cid, cell._status.state, f"stale={cell._stale.state}")
```

**Don't:** Use `.state` or `.is_running` directly — status is on `._status.state`.

### check-graph

```python
graph.get_multiply_defined()   # name conflicts
graph.cycles                   # cell IDs in cycles
graph.get_stale()              # all stale cell IDs
```

### inspect-variables

```python
for name, val in kernel.globals.items():
    print(name, type(val).__name__, getattr(val, 'shape', ''))
```

### ui-state

You can read and set the state of interactive elements from the scratchpad.
This lets you drive UI controls programmatically (set a dropdown, move a
slider) without the user clicking anything. UI state changes propagate to
the notebook even though scratchpad variables don't.

**marimo UI elements** (`mo.ui.*`):

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(element, new_value)
```

**anywidgets** (traitlets are bidirectional — read and write directly):

```python
# Read
print(slider.value)

# Set — updates the widget in the frontend too
slider.value = 5
```

For building custom anywidgets and making them reactive in downstream cells,
see [rich-representations.md](rich-representations.md#reactive-anywidgets-in-marimo).

## Cell operations — mutating the notebook

Cell operations live in `marimo._code_mode`. The module is self-documenting —
use `dir(ctx)` and `help()` to explore. **You MUST use `async with`** (see
top of SKILL.md).

### async with — create, edit, delete, run cells

All mutations go through an `AsyncCodeModeContext`. The `async with` block
is the only async part — **all `ctx.*` methods are synchronous**. They queue
operations during the block and the context manager applies them atomically
on exit. Do NOT `await` individual methods like `ctx.create_cell()` or
`ctx.install_packages()` — they are plain sync calls that return immediately.

**Cells are not auto-executed.** `create_cell` and `edit_cell` queue
structural changes only. Use `run_cell` to queue a cell for execution.
All queued `run_cell` targets are executed in a single batch on context exit.
`run_cell` also works on existing cells that weren't edited — use it to
re-run a cell after environment changes (e.g., installing a package).

A dry-run compile check runs automatically on exit — syntax errors,
multiply-defined names, and cycles are caught before any graph mutations occur.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    # All methods below are sync — no await!
    cid1 = ctx.create_cell("x = 1")
    cid2 = ctx.create_cell("y = x + 1")

    # Use before/after only when position matters
    # ctx.create_cell("setup()", before="my_cell")

    ctx.edit_cell("my_cell", code="z = 42")
    ctx.delete_cell("old_cell")
    ctx.install_packages("pandas", "altair")

    # Queue cells for execution
    ctx.run_cell(cid1)
    ctx.run_cell(cid2)
    ctx.run_cell("my_cell")

    # Re-run an existing cell without editing
    ctx.run_cell("other_cell")
```
