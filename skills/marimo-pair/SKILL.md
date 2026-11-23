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

Use the notebook's launcher, or `uvx marimo@latest pair`. If you already
have the notebook ID, use it. Otherwise, run `marimo pair list` and match
the name or path. If several match, ask which one the user means.

- **Local notebook.** The CLI handles authentication automatically.
- **Remote notebook.** Pass `--url SERVER_URL` to both `list` and `execute`.
  If a token file is supplied, pass `--token-file TOKEN_PATH` to both.
- **Starting a notebook.** Run `marimo edit notebook.py` to open or create
  the file. Include `--sandbox` for inline dependencies. [Startup options](reference/finding-marimo.md)

**Run `help(cm)` as your first scratchpad call in each kernel.** It shows
the code-mode API available in that notebook. With the CLI, substitute the
notebook ID below. With MCP, send the same Python to the scratchpad.

```sh
marimo pair execute --notebook NOTEBOOK_ID --code 'import marimo._code_mode as cm; help(cm)'
```

Use `--file -` for multiline Python on stdin or `--file PATH` for a local
file. Each recipe below is a separate scratchpad call.
[Connection troubleshooting](reference/execution-context.md)

## Inspect the notebook

**Inspect cells.** List their IDs, source, and execution status to find the
code the user is working on.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code, cell.status, cell.errors)
```

**Inspect a live value.** If the notebook defines a DataFrame named `df`,
read it directly in the scratchpad.

```python
print(df.head())
```

New scratchpad bindings last one call. Existing objects are shared with the
user's kernel, so work on a copy when experimenting with in-place mutations.

## Make a change the user can see

**Create the preview.** Choose an unused name such as `x` so other cells can
reuse the preview. End the cell with `x` to display the first five rows.
Name the cell `preview` so you can find it in the next scratchpad call.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = df.head()\nx", name="preview")
    ctx.run_cell(cid)
```

**Edit the preview.** Look up the cell by name and read its current source
before changing it to show ten rows.

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

If the source changed, adapt the edit to the user's current code. In a fresh
call, check the preview cell's errors and output. [Graph errors](reference/gotchas.md) ·
[Notebook improvements](reference/notebook-improvements.md)

## Interact with a widget

Set a marimo slider to trigger the same reactive updates as moving it in
the notebook UI.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(slider, 50)
```

For an anywidget with a synced `value` trait, assign it directly.

```python
widget.value = 10
```

To change the default for future runs, edit the cell that constructs the
widget.
[Custom widgets](reference/rich-representations.md)

## Install a package

To add a dependency to the notebook's environment, queue the package in
code mode. Installation runs when the context exits.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
```
