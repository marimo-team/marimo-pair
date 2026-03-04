# marimo Kernel API Reference

Risk-tiered recipes for the `execute_code` scratchpad. Each recipe is
**self-contained** — include all imports and setup inline since `execute_code`
must not introduce persistent globals.

## Common preamble

Every recipe needs the kernel context. Copy these lines at the top of each call:

```python
from marimo._runtime.context import get_context

ctx = get_context()
kernel = ctx._kernel
graph = kernel.graph
stream = kernel.stream
```

To send a notification to the frontend:

```python
from marimo._messaging.serde import serialize_kernel_message
stream.write(serialize_kernel_message(notification))
```

## Discovering the API

If you're unsure what's available, explore from within `execute_code`:

```python
# Find where marimo is installed
import marimo
print(marimo.__file__)  # then use your file tools to browse the source

# List all kernel commands (ExecuteCellCommand, InstallPackagesCommand, etc.)
import marimo._runtime.commands as commands
print([c for c in dir(commands) if c.endswith("Command")])

# List all frontend notifications
import marimo._messaging.notification as notification
print([n for n in dir(notification) if n.endswith("Notification")])
```

Use this to verify import paths and discover new APIs rather than guessing.

---

## Tier 1: Observe (read-only)

```python
# List cells with defs, refs, code
for cid, cell in graph.cells.items():
    print(cid, cell.defs, cell.refs, cell.code[:80])

# Cell status
for cid, cell in graph.cells.items():
    print(cid, cell._status.state, f"stale={cell._stale.state}")

# Graph health
graph.get_multiply_defined()          # name conflicts
graph.cycles                          # cell IDs in cycles
graph.get_stale()                     # all stale cell IDs

# Inspect variables
for name, val in kernel.globals.items():
    print(name, type(val).__name__, getattr(val, 'shape', ''))
```

**Don't:** Use `.state` or `.is_running` — status is on `._status.state`.

---

## Tier 2: Validate (read-only)

```python
# Compile-check (syntax + defs/refs, no execution)
cell = compile_cell(code, cell_id=CellId_t("test"))
print(f"defs={cell.defs}, refs={cell.refs}")

# Dry-run registration (always clean up afterward)
cell_id = CellId_t("dry_run")
cell = compile_cell(code, cell_id=cell_id)
graph.register_cell(cell_id, cell)
print(graph.get_multiply_defined(), graph.cycles)
graph.delete_cell(cell_id)  # ALWAYS clean up
```

---

## Tier 3: Communicate (non-destructive)

```python
# Toast notification
notify(AlertNotification(title="Done", description="Found 3 outliers", variant=None))

# Persistent banner
notify(BannerNotification(title="Packages needed", description="Install scikit-learn?", variant=None, action=None))

# Focus a cell
notify(FocusCellNotification(cell_id=cell_id))
```

`variant`: `None` (info) or `"danger"` (error). Banner `action`: `None` or `"restart"`.

---

## Tier 4: Modify (medium risk, reversible)

### Create & execute a cell

```python
cell_id = CellId_t("my_cell")
cell = compile_cell(code, cell_id=cell_id)
graph.register_cell(cell_id, cell)
await kernel.run([ExecuteCellCommand(cell_id=cell_id, code=code)])

# All 3 notifications required for UI to update
notify(UpdateCellIdsNotification(cell_ids=list(graph.cells.keys())))
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[code], code_is_stale=False))
notify(CellNotification(cell_id=cell_id, output=CellOutput(channel=CellChannel.OUTPUT, mimetype="text/plain", data=""), status="idle"))
```

**Don't:** Skip `await` — `kernel.run()` returns a coroutine.
**Don't:** Skip the 3 `notify()` calls — kernel works but UI shows nothing.

### Other Tier 4 operations

```python
# Update cell config (disabled, hide_code, column)
await kernel.run([UpdateCellConfigCommand(configs={cell_id: {"disabled": True}})])

# Execute all stale cells
await kernel.run([ExecuteStaleCellsCommand()])
```

---

## Tier 5: Restructure (high risk — confirm with user)

```python
# Move cell (reorder by sending full ID list)
ids = list(graph.cells.keys())
ids.remove(cell_id)
ids.insert(0, cell_id)
notify(UpdateCellIdsNotification(cell_ids=ids))

# Delete cell
graph.delete_cell(cell_id)
notify(UpdateCellIdsNotification(cell_ids=list(graph.cells.keys())))

# Update cell code (code_is_stale=True for drafts, False if already executed)
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[new_code], code_is_stale=True))

# Format cell with ruff
formatter = DefaultFormatter(line_length=79)
formatted = await formatter.format({cell_id: code})
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[formatted[cell_id]], code_is_stale=False))

# Install packages (always ask user which manager + versions first)
await kernel.run([InstallPackagesCommand(manager="uv", versions={"scikit-learn": "", "pandas": ">=2.0"})])
```

---

## Tier 6: Dangerous (never agent-initiated)

Reload, restart, shutdown, save — **never** trigger these without explicit user request. Confirm and explain what will be lost.
