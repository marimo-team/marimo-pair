# Cell Operations Reference

Recipes for creating, editing, moving, and deleting cells. These require careful
orchestration — compile, register, notify the frontend, then execute. Get the
order wrong and the UI desyncs.

## Contents

- [create-cell](#create-cell) — compile, register, notify, execute
- [edit-cell](#edit-cell) — update code (draft or immediate)
- [move-cell](#move-cell) — reorder cells
- [delete-cell](#delete-cell) — remove a cell
- [format-cell](#format-cell) — format with ruff
- [install-packages](#install-packages) — add dependencies
- [cell-config](#cell-config) — hide_code, disabled, etc.
- [run-stale](#run-stale) — execute all stale cells
- [notify-user](#notify-user) — toast, banner, focus

## Preamble

```python
from marimo._runtime.context import get_context
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t
from marimo._runtime.commands import ExecuteCellCommand
from marimo._messaging.notification import (
    UpdateCellIdsNotification,
    UpdateCellCodesNotification,
)
from marimo._messaging.serde import serialize_kernel_message

kernel = get_context()._kernel
graph = kernel.graph
stream = kernel.stream

def notify(n):
    stream.write(serialize_kernel_message(n))
```

## create-cell

Every step matters — skipping one breaks the UI.

```python
cell_id = CellId_t("my_cell")
cell = compile_cell(code, cell_id=cell_id)
graph.register_cell(cell_id, cell)

# 1. Notify frontend about the new cell and its code
notify(UpdateCellIdsNotification(cell_ids=list(graph.cells.keys())))
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[code], code_is_stale=False))

# 2. Execute AFTER notifying
await kernel.run([ExecuteCellCommand(cell_id=cell_id, code=code)])
```

## edit-cell

**As a draft** (user reviews before execution):

```python
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[new_code], code_is_stale=True))
```

**Update and execute immediately:**

```python
graph.delete_cell(cell_id)  # must delete before re-registering
cell = compile_cell(new_code, cell_id=cell_id)
graph.register_cell(cell_id, cell)
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[new_code], code_is_stale=False))
await kernel.run([ExecuteCellCommand(cell_id=cell_id, code=new_code)])
```

## move-cell

```python
ids = list(graph.cells.keys())
ids.remove(cell_id)
ids.insert(0, cell_id)  # move to top
notify(UpdateCellIdsNotification(cell_ids=ids))
```

## delete-cell

```python
graph.delete_cell(cell_id)
notify(UpdateCellIdsNotification(cell_ids=list(graph.cells.keys())))
```

## format-cell

Format after writing code.

```python
from marimo._utils.formatter import DefaultFormatter

formatter = DefaultFormatter(line_length=79)
formatted = await formatter.format({cell_id: code})
notify(UpdateCellCodesNotification(cell_ids=[cell_id], codes=[formatted[cell_id]], code_is_stale=False))
```

## install-packages

Installing packages modifies the user's environment — confirm first.

```python
from marimo._runtime.commands import InstallPackagesCommand

await kernel.run([
    InstallPackagesCommand(
        manager=kernel.user_config["package_management"]["manager"],
        versions={"scikit-learn": "", "pandas": ">=2.0"},
    )
])
```

## cell-config

```python
from marimo._runtime.commands import UpdateCellConfigCommand

await kernel.run([UpdateCellConfigCommand(configs={cell_id: {"disabled": True}})])
```

## run-stale

```python
from marimo._runtime.commands import ExecuteStaleCellsCommand

await kernel.run([ExecuteStaleCellsCommand()])
```

## notify-user

```python
from marimo._messaging.notification import (
    AlertNotification,
    BannerNotification,
    FocusCellNotification,
)

# Toast notification
notify(AlertNotification(title="Done", description="Found 3 outliers", variant=None))

# Persistent banner
notify(BannerNotification(title="Packages needed", description="Install scikit-learn?", variant=None, action=None))

# Focus a cell
notify(FocusCellNotification(cell_id=cell_id))
```

`variant`: `None` (info) or `"danger"` (error). Banner `action`: `None` or `"restart"`.

## Common Pitfalls

- **Don't skip `await`** — `kernel.run()` returns a coroutine; without `await` nothing executes.
- **Don't send `CellNotification` with empty output after `kernel.run()`** — it clobbers the real output the kernel just produced.
- **Don't skip notifications before execute** — the kernel runs the code but the frontend won't know about the cell, so the user sees nothing.
- **Don't skip formatting** — unformatted code is harder for the user to read and edit.
