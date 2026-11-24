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
cells, run them, and update widgets. **Run `help(cm)` first in each notebook kernel** to see
the Code Mode API available there. Use the notebook ID from `marimo pair list`.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm
help(cm)
PYTHON
```

### Inspect notebook state

Python runs in a temporary execution environment with access to variables
defined in notebook cells. For example, if a cell defines `df`, you can
inspect it directly.

```sh
marimo pair execute --notebook nb-analysis --code 'print(df.head())'
```

**Variables you assign during an execution are local to that call.** To keep
a variable in the notebook, define it in a cell through Code Mode.
Code Mode also lets you inspect each cell’s source, status, and errors.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.code[:50], cell.status, cell.errors)
PYTHON
```

Notebook variables refer to live objects. Avoid mutating notebook data in
place because marimo does not track those changes. For intentional UI
updates, see [Update a widget](#update-a-widget).

### Edit and run cells

Work becomes part of the user’s notebook when you create or edit a cell
through Code Mode. The user can rerun the code, see the result, and discuss
it with you.

**Notebook rules**

- Each public name can be defined in only one cell. Names like `_x` are local to their cell.
- Cells cannot depend on each other in a cycle.
- Wildcard imports (`from module import *`) are unsupported.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = 1\nx")
    ctx.run_cell(cid)
    print(cid)
PYTHON
```

The printed ID works across executions. If the ID is `Hbol`, this shows
the cell’s current source, including any edits the user has made.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    print(ctx.cells["Hbol"].code)
PYTHON
```

A later execution can update that same cell. Here the user sees its output
change from `1` to `2`.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.edit_cell("Hbol", "x = 2\nx")
    ctx.run_cell("Hbol")
PYTHON
```

Cell names are optional. This call gives the existing cell the name `initial_value`.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.edit_cell("Hbol", name="initial_value")
PYTHON
```

A later call can read the cell’s source by name.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    print(ctx.cells["initial_value"].code)
PYTHON
```

### Update a widget

For a marimo slider or another `mo.ui` element, use Code Mode to set its
value. This triggers the same reactive updates as a user interaction.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.set_ui_value(slider, 50)
PYTHON
```

For an anywidget, assign its synced trait directly.

```sh
marimo pair execute --notebook nb-analysis --code 'widget.value = 10'
```

To change the default for future runs, edit the cell that creates the widget.
For a custom widget that drives other cells, see [reactive anywidgets](reference/rich-representations.md#reactive-anywidgets-in-marimo).

### Manage notebook packages

List installed packages and versions in the notebook’s environment.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for package in ctx.packages.list():
        print(package.name, package.version)
PYTHON
```

To install a missing package, add it in its own Pair call. Check the result
before editing or running a cell that depends on it.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.add("polars")
PYTHON
```

To uninstall a package, remove it in its own call.

```sh
marimo pair execute --notebook nb-analysis --file - <<'PYTHON'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.packages.remove("polars")
PYTHON
```

## References

- [Start a notebook](reference/finding-marimo.md) with the project’s Python environment or in sandbox mode.
- [Troubleshoot a connection](reference/execution-context.md) when a notebook is missing, needs a token, or an edit was interrupted.
- [Diagnose notebook errors](reference/gotchas.md) involving cell scope, duplicate definitions, or imports after a package install.
- [Build widgets and visualizations](reference/rich-representations.md) that respond to changes in the notebook.
- [Improve an existing notebook](reference/notebook-improvements.md) by reviewing cell dependencies, organizing cells, and caching expensive work.
