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

With the CLI, list running notebooks and pass the selected ID to `execute`:

```sh
marimo pair list
marimo pair execute --notebook NOTEBOOK_ID --code 'print("hello")'
```

Use the notebook's launcher, or run `uvx marimo@latest pair`. If you already
have the notebook ID, pass it directly. For a remote server, include its
`--url` in both commands. Pass multiline Python with `--file PATH` or
`--file -` for stdin. [Connection troubleshooting](reference/execution-context.md)

**Starting a notebook.** Run `marimo edit notebook.py` to open or create the
file. Include `--sandbox` for inline dependencies. [Startup options](reference/finding-marimo.md)

## Show a scratchpad result in the notebook

If the notebook defines `df`, run `print(df.head())` in the scratchpad.
Scratchpad bindings last one call. Existing objects are shared, so an in-place
mutation can affect the user's data. Work on a copy when experimenting. For
a lasting transformation, edit the cell that owns the value or define a new
value in a downstream cell.

To show the preview in the notebook, give a cell the expression `df.head()`
and run it from the scratchpad.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("df.head()")
    ctx.run_cell(cid)
```

When editing an existing cell, read `ctx.cells[cid].code` first so you
preserve the user's latest work. Pass the full cell body to
`ctx.edit_cell(cid, code)`, then queue `ctx.run_cell(cid)`. Check the cell's
`errors` and `output` in a fresh call after it runs.

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
