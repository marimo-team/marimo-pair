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

## Pair with a notebook

Discover notebooks with `marimo pair list`. Local notebooks authenticate
automatically.

```sh
marimo pair list
# Listing excerpt: {"notebooks": [{"id": "nb-analysis", "name": "analysis.py"}]}
```

Use the notebook ID to run Python in its kernel. On your first call in each
kernel, run `help(cm)` to see the Code Mode API available there.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm
help(cm)
PYTHON
```

If you need to open or create a notebook, see the [startup guide](reference/finding-marimo.md)
to choose the launcher and Python environment. For a notebook that declares
its dependencies inline, use `--sandbox`. Once it’s open, run `marimo pair list` again.

```sh
marimo edit notebook.py --sandbox
```

### Connect to a remote notebook

For a remote notebook, pass the server URL to both commands. If you have
a token file, pass its path to both as well. See `marimo pair --help` for
other connection options.

```sh
marimo pair list --url https://notebooks.example.org --token-file ./token
# Listing excerpt: {"notebooks": [{"notebook_id": "nb-analysis", "name": "analysis.py"}]}
marimo pair execute --url https://notebooks.example.org --token-file ./token \
  --notebook nb-analysis --code 'import marimo._code_mode as cm; help(cm)'
```

If the notebook is missing from the listing or authentication fails, see the
[connection troubleshooting guide](reference/execution-context.md#find-the-intended-notebook).

## Work in the notebook

Pair runs Python in the user’s live notebook. You can inspect notebook
variables directly and use the Code Mode API (`marimo._code_mode`) to edit
cells, run them, and update widgets. Each execution has its own scratchpad
scope, so names you assign there last only for that call.

### Inspect notebook state

If the notebook defines `df`, you can preview it directly.

```python
print(df.head())
```

Avoid mutating notebook data in the scratchpad. marimo does not track
in-place mutations or rerun dependent cells when they happen.

To see which cells ran or raised an error, inspect their live state.

```python
import marimo._code_mode as cm

for cell in cm.get_context().cells:
    print(cell.id, cell.code, cell.status, cell.errors)
```

### Edit and run cells

Create and run a cell to display the preview and define `x` for other cells.
Choose another name if the notebook already defines `x`.
[How names work across cells](reference/gotchas.md#redefining-a-public-name-across-cells).

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = df.head()\nx", name="preview")
    ctx.run_cell(cid)
```

To show ten rows, edit the same cell and rerun it. Check its live source
first in case the user has edited it.

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

Check the cell’s errors and output in a fresh call. For details on an API
method, use Python’s `help` in the scratchpad.

```python
import marimo._code_mode as cm

help(cm.AsyncCodeModeContext.edit_cell)
```

### Update a widget

To move a marimo slider and rerun its dependents, set its UI value.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(slider, 50)
```

For an anywidget, assign its synced trait directly.

```python
widget.value = 10
```

To change the default for future runs, edit the cell that creates the widget.
For a custom widget that drives other cells, see [reactive anywidgets](reference/rich-representations.md#reactive-anywidgets-in-marimo).

### Manage notebook packages

List installed packages and versions in the notebook’s environment.

```python
import marimo._code_mode as cm

for package in cm.get_context().packages.list():
    print(package.name, package.version)
```

To install a missing package, add it in its own Pair call. Check the result
before editing or running a cell that depends on it.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
```

To uninstall a package, remove it in its own call.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.remove("polars")
```

## References

- [Start a notebook](reference/finding-marimo.md) with the project’s Python environment or in sandbox mode.
- [Troubleshoot a connection](reference/execution-context.md) when a notebook is missing, needs a token, or an edit was interrupted.
- [Diagnose notebook errors](reference/gotchas.md) involving cell scope, duplicate definitions, or imports after a package install.
- [Build widgets and visualizations](reference/rich-representations.md) that respond to changes in the notebook.
- [Improve an existing notebook](reference/notebook-improvements.md) by reviewing cell dependencies, organizing cells, and caching expensive work.
