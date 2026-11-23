---
name: marimo-pair
description: >-
  Start a marimo notebook or pair on a running one. Inspect live Python state,
  edit and run cells, and interact with widgets in the user's kernel.
---

marimo is a reactive Python notebook. You and the user share a live kernel.
When a cell runs, marimo reruns the cells that depend on its variables.

> **WARNING. The active runtime is the source of truth.** Use the
> `marimo pair` CLI to inspect and edit the running notebook. If you edit the
> `.py` file directly, the user may never see your changes in the notebook,
> and the kernel can overwrite them on save.

## Pair with the user's notebook

Use the notebook's marimo launcher, or `uvx marimo@latest` for a standalone
CLI. Use marimo 0.26+ for the CLI and server.

1. **Find the notebook.** Use the supplied notebook ID or run `marimo pair list`
   to find it. For a specific server, pass its `--url` to both `list` and
   `execute`. If several notebooks match, ask which one the user means.
2. **Start it if needed.** Run `marimo edit notebook.py` to open or create the
   file. For a standalone notebook with inline dependencies, use
   `uvx marimo@latest edit --sandbox notebook.py`. Once it opens in the
   browser, run `pair list` with the same launcher. [Startup options](reference/finding-marimo.md)
3. **Work in its kernel.** Run `marimo pair execute --notebook NOTEBOOK_ID`
   with `--code` for a one-liner, `--file PATH` for a Python file, or
   `--file -` for stdin.
   In supported agents, `execute` also tries to connect the notebook's message
   inbox. Scratchpad execution works independently of inbox setup.

For example, see what the user is working on:

```sh
marimo pair execute --notebook NOTEBOOK_ID --file - <<'PY'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code, cell.status)
PY
```

Use `marimo pair --help` for commands and flags. For authentication or an
interrupted execution, see [Connection troubleshooting](reference/execution-context.md).

## Show a scratchpad result in the notebook

If the notebook defines `df`, inspect it with `--code 'print(df.head())'`.
Scratchpad bindings last one call. Existing objects are shared, so an in-place
mutation can affect the user's data. Work on a copy when experimenting. For
a lasting transformation, edit the cell that owns the value or define a new
value in a downstream cell.

To show the preview in the notebook, give a cell the expression `df.head()`
and run it. The Python snippets below run in the scratchpad via `pair execute`.

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
