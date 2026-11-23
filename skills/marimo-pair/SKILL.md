---
name: marimo-pair
description: >-
  Start a marimo notebook or pair on a running one. Inspect live Python state,
  edit and run cells, and interact with widgets in the user's kernel.
---

marimo is a reactive Python notebook. You and the user share a live kernel.
When a cell runs, marimo reruns the cells that depend on its variables.

> **WARNING. The active runtime is the source of truth.** Use the Pair CLI
> (`marimo pair`) or MCP to work in the running notebook. Direct edits to
> the `.py` file may never appear in the user's UI, and the kernel can
> overwrite them on save.

## Pair with the user's notebook

Use the notebook's launcher or `uvx marimo@latest pair`.

- Run `marimo pair list` to find the notebook ID.
- Local notebooks authenticate automatically. For remote notebooks, pass
  `--url SERVER_URL` to both `list` and `execute`. Include `--token-file TOKEN_PATH`
  on both commands if a token file is supplied. [Connection troubleshooting](reference/execution-context.md)
- Run `marimo edit notebook.py` to open or create a notebook. Add `--sandbox` for
  inline dependencies. [Startup options](reference/finding-marimo.md)

**Run `help(cm)` first in each kernel** to see the available code-mode API.

```sh
marimo pair execute --notebook NOTEBOOK_ID --code 'import marimo._code_mode as cm; help(cm)'
```

Run each Python example in a separate scratchpad call. For multiline code,
use `--file PATH` or `--file -` (stdin) with the CLI, or send the Python via MCP.

## Inspect the notebook

### List cells and their execution status

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code, cell.status, cell.errors)
```

### Inspect a live value

Read a DataFrame named `df` directly from the scratchpad.

```python
print(df.head())
```

Assignments in the scratchpad last one call. In-place mutations can change
the user's live data.

## Make a change the user can see

### Create and run a cell

This defines `x` for other cells and displays its value in the notebook.
Use a free variable name if `x` is already defined.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = df.head()\nx", name="preview")
    ctx.run_cell(cid)
```

### Edit and rerun the preview

Check the live source before replacing it. The user may have edited it.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cell = ctx.cells["preview"]
    if cell.code == "x = df.head()\nx":
        ctx.edit_cell(cell.id, "x = df.head(10)\nx")
        ctx.run_cell(cell.id)
    else:
        print(cell.code)
```

Check the cell’s errors and output in a fresh call. [Graph errors](reference/gotchas.md) ·
[Notebook improvements](reference/notebook-improvements.md)

## Interact with a widget

### Set a marimo slider

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(slider, 50)
```

### Set an anywidget’s synced trait

```python
widget.value = 10
```

To change the default for future runs, edit the cell that creates the widget.
[Custom widgets](reference/rich-representations.md)

## Install a package

The notebook installs the package when the context exits.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
```
