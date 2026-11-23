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

Match the notebook by name or path. If several match, ask which one the
user means.

Use the notebook's launcher, or `uvx marimo@latest pair`. For a local
notebook, `marimo pair list` discovers the notebook ID and the CLI handles
authentication automatically. For a remote notebook, pass `--url SERVER_URL`
to both `list` and `execute`. If a token file is supplied, pass
`--token-file TOKEN_PATH` to both commands.

**First scratchpad call in each kernel:** inspect the code-mode API with
`help(cm)`. The installed notebook determines which methods are available.
With the CLI, substitute the notebook ID below. With MCP, send the same
Python to the notebook's scratchpad.

```sh
marimo pair execute --notebook NOTEBOOK_ID --code 'import marimo._code_mode as cm; help(cm)'
```

Use `--file -` for multiline Python on stdin or `--file PATH` for a local
file. Each recipe below is a separate scratchpad call.
[Connection troubleshooting](reference/execution-context.md)

**Starting a notebook.** Run `marimo edit notebook.py` to open or create the
file. Include `--sandbox` for inline dependencies. [Startup options](reference/finding-marimo.md)

## Inspect notebook state

List the live cells to find the code the user is looking at and see whether it ran.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code, cell.status, cell.errors)
```

## Inspect a live Python value

Read notebook variables directly. For example, if the notebook defines `df`:

```python
print(df.head())
```

New scratchpad bindings last one call. Existing objects are shared with the
user's kernel, so work on a copy when experimenting with in-place mutations.

## Create and run a cell

To show the preview in the notebook, put the expression in a cell and run it.
Print its ID so you can find the same cell in a later call.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("df.head()")
    ctx.run_cell(cid)
print(cid)
```

## Edit an existing cell

Use the ID from inspection. For example, expand the preview to ten rows
only if the live cell still contains the code you inspected:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cell = ctx.cells["CELL_ID"]
    if cell.code == "df.head()":
        ctx.edit_cell(cell.id, "df.head(10)")
        ctx.run_cell(cell.id)
    else:
        print(cell.code)
```

If the source changed, adapt the edit to the user's current code. Inspect
`cell.errors` and `cell.output` in a fresh call to check the result. To
rename a cell, pass `name="preview"` to `ctx.edit_cell`.

## Install a package

Use the notebook's package manager when the user asks to add a dependency.
Installation happens when the context exits.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
```

## Change a widget's live value

For a marimo slider, this triggers the same reactive updates as moving it
in the notebook UI:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(slider, 50)
```

For an anywidget with a synced `value` trait, assign it directly:

```python
widget.value = 10
```

To change the default for future runs, edit the cell that constructs the
widget. For more involved tasks, see [custom widgets](reference/rich-representations.md),
[graph errors](reference/gotchas.md), or [improving a notebook](reference/notebook-improvements.md).
