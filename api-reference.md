# marimo Kernel API Reference

Risk-tiered recipes for the `execute_code` scratchpad on a running notebook.
Each recipe is a self-contained code block you can paste into `execute_code`.

---

## Tier 0: Setup

### `get-context` — Get kernel context

Every recipe starts here. This gives you the kernel, graph, and stream.

```python
from marimo._runtime.context import get_context

ctx = get_context()
kernel = ctx._kernel
graph = kernel.graph
stream = kernel.stream
```

**Do:** Always use `get_context()` — it returns the active runtime context.

**Don't:** Try `mo.App._current_app_graph()` — it doesn't exist.

---

## Tier 1: Observe (read-only, zero risk)

### `inspect-cells` — List cells with defs, refs, and code

```python
for cell_id, cell in graph.cells.items():
    print(cell_id, cell.defs, cell.refs, cell.code[:80])
```

### `check-status` — Check cell runtime status

```python
for cell_id, cell in graph.cells.items():
    print(cell_id,
          f"status={cell._status.state}",      # idle | queued | running | None
          f"stale={cell._stale.state}",         # True | False
          f"exception={cell.exception}",        # None or exception object
          f"disabled={cell.config.disabled}")    # True | False
```

**Don't:** Look for `.state` or `.is_running` — status lives on `._status.state`.

### `check-graph` — Check graph health (cycles, multiple definitions)

```python
# Variables defined by more than one cell
graph.get_multiply_defined()  # e.g. ['df'] if two cells both define df

# Cycle detection
graph.cycles                          # set of cell IDs in cycles
graph.cycle_tracker.get_cycles()      # detailed cycle info

# Per-cell checks
graph.is_disabled(cell_id)
graph.is_any_ancestor_disabled(cell_id)
graph.is_any_ancestor_stale(cell_id)
graph.get_stale()                     # set of all stale cell IDs
```

**Don't:** Use `graph.get_cycles()` — that method is on `graph.cycle_tracker`.

### `inspect-variables` — Inspect kernel variables

`kernel.globals` is a plain Python dict of all variables defined by notebook
cells. Use normal introspection.

```python
# List all variables with types and shapes
for name, val in kernel.globals.items():
    shape = getattr(val, 'shape', None)
    length = len(val) if hasattr(val, '__len__') and not isinstance(val, str) else None
    print(f"{name}: {type(val).__name__}", f"shape={shape}" if shape else "", f"len={length}" if length else "")

# Inspect a specific variable
df = kernel.globals['my_dataframe']
print(df.dtypes)
print(df.head())

# Check what's imported
import sys
[m for m in sys.modules if 'pandas' in m or 'altair' in m or 'polars' in m]
```

---

## Tier 2: Validate (read-only, zero risk)

### `compile-check` — Compile-check code without executing

Parses and analyzes code. Catches syntax errors and extracts defs/refs without
touching the graph.

```python
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

try:
    cell = compile_cell(code, cell_id=CellId_t("test"))
    print(f"OK: defs={cell.defs}, refs={cell.refs}")
except SyntaxError as e:
    print(f"Bad syntax: {e}")
```

### `dry-run-register` — Check if code fits the graph

Register into the graph, inspect for conflicts, then clean up. **Always delete
afterward** to avoid phantom cells.

```python
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

cell_id = CellId_t("dry_run")
cell = compile_cell(code, cell_id=cell_id)

graph.register_cell(cell_id, cell)
errors = graph.get_multiply_defined()   # name conflicts
cycles = graph.cycles                    # circular deps
graph.delete_cell(cell_id)               # ALWAYS clean up

print(f"conflicts={errors}, cycles={cycles}")
```

**Don't:** Forget `graph.delete_cell(cell_id)` — it leaves a phantom cell.

---

## Tier 3: Communicate (low risk, non-destructive)

These send messages to the frontend UI. They don't modify notebook state.

### `send-alert` — Send a toast notification

A transient toast that auto-dismisses. Good for quick status updates.

```python
from marimo._messaging.notification import AlertNotification
from marimo._messaging.serde import serialize_kernel_message

stream.write(serialize_kernel_message(
    AlertNotification(
        title="Analysis complete",
        description="Found 3 outliers in the revenue column",
        variant=None,  # or "danger" for error styling
    )
))
```

**Fields:**
- `title: str` — bold heading
- `description: str` — body text
- `variant: Optional[Literal["danger"]]` — `None` for info, `"danger"` for error

### `send-banner` — Send a persistent banner

A banner that stays until dismissed. Use for important state changes.

```python
from marimo._messaging.notification import BannerNotification
from marimo._messaging.serde import serialize_kernel_message

stream.write(serialize_kernel_message(
    BannerNotification(
        title="Packages needed",
        description="This notebook requires scikit-learn. Install it?",
        variant=None,  # or "danger" for error styling
        action=None,   # or "restart" to show a restart button
    )
))
```

**Fields:**
- `title: str` — bold heading
- `description: str` — body text
- `variant: Optional[Literal["danger"]]` — `None` for info, `"danger"` for error
- `action: Optional[Literal["restart"]]` — adds a restart button if set

### `focus-cell` — Scroll to and highlight a cell

Directs the user's attention to a specific cell.

```python
from marimo._messaging.notification import FocusCellNotification
from marimo._messaging.serde import serialize_kernel_message

stream.write(serialize_kernel_message(
    FocusCellNotification(cell_id=cell_id)
))
```

---

## Tier 4: Modify (medium risk, reversible)

These change notebook state but are easy to undo.

### `create-execute-cell` — Create and execute a new cell

Compile → register → execute → notify frontend (3 messages).

```python
from marimo._ast.compiler import compile_cell
from marimo._runtime.commands import ExecuteCellCommand
from marimo._messaging.notification import (
    UpdateCellIdsNotification,
    UpdateCellCodesNotification,
    CellNotification,
)
from marimo._messaging.cell_output import CellOutput, CellChannel
from marimo._messaging.serde import serialize_kernel_message
from marimo._types.ids import CellId_t

cell_id = CellId_t("my_cell")
code = 'x = 42\nx'

# 1. Compile
cell = compile_cell(code, cell_id=cell_id)

# 2. Register in graph
graph.register_cell(cell_id, cell)

# 3. Execute
await kernel.run([ExecuteCellCommand(cell_id=cell_id, code=code)])

# 4. Notify frontend (all 3 are required for UI to update)
stream.write(serialize_kernel_message(
    UpdateCellIdsNotification(cell_ids=list(graph.cells.keys()))
))
stream.write(serialize_kernel_message(
    UpdateCellCodesNotification(cell_ids=[cell_id], codes=[code], code_is_stale=False)
))
stream.write(serialize_kernel_message(
    CellNotification(
        cell_id=cell_id,
        output=CellOutput(channel=CellChannel.OUTPUT, mimetype="text/plain", data="42"),
        status="idle",
    )
))
```

**Don't:** Skip the 3 `stream.write` calls — kernel works but UI shows nothing.

**Don't:** `kernel.run([req])` without `await` — returns a coroutine, nothing runs.

### `update-cell-config` — Update cell configuration

Change disabled/hide_code/column without re-executing.

```python
from marimo._runtime.commands import UpdateCellConfigCommand

await kernel.run([
    UpdateCellConfigCommand(configs={
        cell_id: {"disabled": True},   # disable the cell
    })
])
```

**CellConfig fields** (all optional in the update dict):
- `disabled: bool` — if `True`, cell and descendants cannot execute
- `hide_code: bool` — if `True`, code is hidden in the editor
- `column: Optional[int]` — column layout position

### `execute-stale` — Execute all stale cells

Runs every cell whose dependencies have changed since last execution.

```python
from marimo._runtime.commands import ExecuteStaleCellsCommand

await kernel.run([ExecuteStaleCellsCommand()])
```

---

## Tier 5: Restructure (high risk, jarring to user)

These change notebook structure. Always confirm with the user first.

### `move-cell` — Reorder cells

Send `UpdateCellIdsNotification` with the full cell list in desired order.

```python
from marimo._messaging.notification import UpdateCellIdsNotification
from marimo._messaging.serde import serialize_kernel_message

ids = list(graph.cells.keys())
ids.remove(cell_id)
ids.insert(0, cell_id)  # move to top

stream.write(serialize_kernel_message(
    UpdateCellIdsNotification(cell_ids=ids)
))
```

**Don't:** Mutate `graph.cells` directly — it tracks topology, not display order.

### `delete-cell` — Remove a cell from the notebook

```python
from marimo._messaging.notification import UpdateCellIdsNotification
from marimo._messaging.serde import serialize_kernel_message

graph.delete_cell(cell_id)
remaining_ids = list(graph.cells.keys())

stream.write(serialize_kernel_message(
    UpdateCellIdsNotification(cell_ids=remaining_ids)
))
```

### `update-cell-code` — Update code in an existing cell

Pushes new code to the frontend. Set `code_is_stale=True` for drafts the user
should review before execution, or `False` if the kernel has already run it.

```python
from marimo._messaging.notification import UpdateCellCodesNotification
from marimo._messaging.serde import serialize_kernel_message

stream.write(serialize_kernel_message(
    UpdateCellCodesNotification(
        cell_ids=[cell_id],
        codes=[new_code],
        code_is_stale=True,  # True = draft, False = already executed
    )
))
```

### `format-cell` — Format cell code with ruff

Formats code in-process using `DefaultFormatter` (tries ruff, then black) and
pushes the formatted result to the frontend. Call this after creating or
updating a cell to keep code tidy.

```python
from marimo._utils.formatter import DefaultFormatter
from marimo._messaging.notification import UpdateCellCodesNotification
from marimo._messaging.serde import serialize_kernel_message

formatter = DefaultFormatter(line_length=79)
formatted = await formatter.format({cell_id: code})

stream.write(serialize_kernel_message(
    UpdateCellCodesNotification(
        cell_ids=[cell_id],
        codes=[formatted[cell_id]],
        code_is_stale=False,
    )
))
```

**Do:** Call this after `create-execute-cell` or `update-cell-code` to
auto-format the code the user sees.

**Don't:** Skip the `await` — `formatter.format()` is async.

### `install-packages` — Install packages into the environment

Always ask the user which package manager to use and confirm versions.

```python
from marimo._runtime.commands import InstallPackagesCommand

await kernel.run([
    InstallPackagesCommand(
        manager="uv",  # or "pip", "conda", etc.
        versions={"scikit-learn": "", "pandas": ">=2.0"},  # "" = latest
    )
])
```

**Fields:**
- `manager: str` — package manager name (`"pip"`, `"uv"`, `"conda"`, etc.)
- `versions: dict[str, str]` — package name → version specifier (empty string = latest)

---

## Tier 6: Dangerous (never agent-initiated)

These operations exist in the kernel but should **never** be triggered by the
agent without an explicit user request. Document them here only so you know
they exist and can warn users if needed.

- **Reload** — reloads the notebook file from disk, discarding in-memory state
- **Restart** — restarts the kernel process, losing all runtime state
- **Shutdown** — kills the notebook session entirely
- **Save** — writes the notebook to disk (user may have unsaved experiments)

If the user asks for any of these, confirm before proceeding and explain what
will be lost.

---

## Import Cheat Sheet

All imports used across the recipes above, in one block:

```python
# Context
from marimo._runtime.context import get_context

# AST / Compilation
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

# Commands (passed to kernel.run)
from marimo._runtime.commands import (
    ExecuteCellCommand,
    UpdateCellConfigCommand,
    ExecuteStaleCellsCommand,
    InstallPackagesCommand,
)

# Notifications (passed to stream.write via serialize)
from marimo._messaging.notification import (
    AlertNotification,
    BannerNotification,
    FocusCellNotification,
    CellNotification,
    UpdateCellCodesNotification,
    UpdateCellIdsNotification,
)

# Output
from marimo._messaging.cell_output import CellOutput, CellChannel

# Serialization
from marimo._messaging.serde import serialize_kernel_message

# Formatting
from marimo._utils.formatter import DefaultFormatter
```
