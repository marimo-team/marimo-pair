# Execute Code Reference

Everything you do in the notebook goes through execute-code. This file covers
both inspection (reading state) and mutation (creating/editing/deleting cells).

## Scratchpad — inspecting state

The scratchpad is just Python. Cell variables are already in scope — `print(df.head())`
works directly. Results come back to you; the user doesn't see them.

**Scoping:** Variables defined in the scratchpad do not persist between
execute-code calls. Only notebook cell variables survive. Do all dependent
work in a single call.

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
This lets you drive the notebook programmatically — set a dropdown value,
move a slider, enter text — without the user clicking anything.

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

### async with — create, edit, delete cells

All mutations go through an `AsyncCodeModeContext`. Operations are queued
during the block and applied atomically on exit. A dry-run compile check
runs automatically — syntax errors, multiply-defined names, and cycles are
caught before any graph mutations occur.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = 1")
    ctx.create_cell("y = x + 1", after=cid)
    ctx.edit_cell("my_cell", code="z = 42")
    ctx.delete_cell("old_cell")
```
