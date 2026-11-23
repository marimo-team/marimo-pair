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

Pair executes Python in the notebook's kernel. Code Mode
(`marimo._code_mode`) is the Python API for inspecting the notebook and
making edits the user can see. On your first execution in each kernel,
run `help(cm)` to see the API available there.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm
help(cm)
PYTHON
```

For a remote notebook, pass the server URL to both commands. If you have
a token file, pass its path to both as well.

```sh
marimo pair list --url https://notebooks.example.org --token-file ./token
# Listing excerpt: {"notebooks": [{"notebook_id": "nb-analysis", "name": "analysis.py"}]}
marimo pair execute --url https://notebooks.example.org --token-file ./token \
  --notebook nb-analysis --code 'import marimo._code_mode as cm; help(cm)'
```

If the notebook isn't running, open or create it with
`marimo edit notebook.py --sandbox`, then list again. Use the project's
launcher or `uvx marimo@latest` for the commands above.
[Startup options](reference/finding-marimo.md) · [Connection troubleshooting](reference/execution-context.md)

## Work in the notebook with Code Mode

### List cells and their execution status

```python
import marimo._code_mode as cm

for cell in cm.get_context().cells:
    print(cell.id, cell.code, cell.status, cell.errors)
```

### Inspect a live variable

If the notebook defines `df`, you can read it directly.

```sh
marimo pair execute --notebook nb-analysis --code 'print(df.head())'
```

Scratchpad assignments last one call. In-place mutations affect the live object.

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
[Custom widgets](reference/rich-representations.md)

### Manage notebook packages

Use a separate Pair call for each package change. Check the result before
editing or running a cell that depends on it.

**List installed packages and versions**

```python
import marimo._code_mode as cm

for package in cm.get_context().packages.list():
    print(package.name, package.version)
```

**Install a package**

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
```

**Remove a package**

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.remove("polars")
```

### Explore the API

Use Python’s `help` on a method for its parameters and examples.

```python
import marimo._code_mode as cm

help(cm.AsyncCodeModeContext.edit_cell)
```

## References

- [Start a notebook](reference/finding-marimo.md) with the project’s Python environment or in sandbox mode.
- [Troubleshoot a connection](reference/execution-context.md) when a notebook is missing, needs a token, or an edit was interrupted.
- [Diagnose notebook errors](reference/gotchas.md) involving cell scope, duplicate definitions, or imports after a package install.
- [Build widgets and visualizations](reference/rich-representations.md) that respond to changes in the notebook.
- [Improve an existing notebook](reference/notebook-improvements.md) by organizing cells, reusing functions, and caching expensive work.
