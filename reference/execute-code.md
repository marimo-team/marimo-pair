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

### compile-check

Syntax + defs/refs validation without execution. Cheap — always do this before
creating or editing a cell. `compile_cell` does not register the cell in the
graph, so there is nothing to clean up afterward.

```python
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

cell = compile_cell(code, cell_id=CellId_t("test"))
print(f"defs={cell.defs}, refs={cell.refs}")
```

### dry-run

Register a cell in the graph to check for conflicts and cycles, then clean up.

```python
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

cell_id = CellId_t("dry_run")
cell = compile_cell(code, cell_id=cell_id)
graph.register_cell(cell_id, cell)
print(graph.get_multiply_defined(), graph.cycles)
graph.delete_cell(cell_id)  # ALWAYS clean up
```

### ui-state

You can read and set the state of interactive elements from the scratchpad.
This lets you drive the notebook programmatically — set a dropdown value,
move a slider, enter text — without the user clicking anything.

**marimo UI elements** (`mo.ui.*`):

```python
from marimo._plugins.ui._impl.input import set_ui_element_value

# Set a UI element's value by its object ID
set_ui_element_value(element._id, new_value)
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

Cell operations live in `marimo._code_mode`. The module exposes a context
object and an edit system — you apply edits to the notebook through the context.

```python
import marimo._code_mode as cm

ctx = cm.get_context()
```

On first use, discover the API surface:

```python
print([x for x in dir(cm) if not x.startswith('_')])
print([x for x in dir(ctx) if not x.startswith('_')])
```

Drill into classes and methods with `dir()` and `help()`. They are the source
of truth, not this file.

### Common edits

- **Insert cells** at a position
- **Edit a cell's** code or config (supports drafts for user review)
- **Delete cells** by index range
- **Move a cell** — delete + insert (no dedicated primitive)

### Other operations

The context also provides ways to:

- **Execute stale cells**
- **Install packages** (confirm with user first)
- **Notify the user** (toast, banner, focus a cell)

### Pitfalls

- **Must `await` edit calls** — forgetting `await` silently does nothing.
- **Cell handles come from the context** — you can't construct one manually.
- **Don't write to the `.py` file directly** — the kernel owns it.

## Discovering the API

If an import fails or you need something not listed above, explore:

```python
import marimo
print(marimo.__file__)       # browse the source with your file tools
print(marimo.__version__)    # import paths change across releases

# List all kernel commands
import marimo._runtime.commands as commands
print([c for c in dir(commands) if c.endswith("Command")])

# List all frontend notifications
import marimo._messaging.notification as notification
print([n for n in dir(notification) if n.endswith("Notification")])
```

Use this to verify import paths and discover new APIs rather than guessing.
