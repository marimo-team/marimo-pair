# Worked Example: "I want to plot this data"

This walks through the scratchpad-to-cell workflow from SKILL.md.

## Step 1 — Investigate via scratchpad

Execute code to understand the notebook state. These calls are invisible to
the user — just you gathering info. Cell variables are already in scope, so
you can inspect them directly.

```python
# What variables exist?
for name, val in vars().items():
    if not name.startswith('_'):
        print(name, type(val).__name__, getattr(val, 'shape', ''))
```

Output: `sales DataFrame (1200, 4)`

```python
# What columns?
print(sales.dtypes)
```

Output: `date datetime64, region object, revenue float64, units int64`

```python
# What plotting libraries are available?
import sys
print([m for m in sys.modules if 'plot' in m or 'altair' in m])
```

Output: `['altair', 'altair.vegalite', ...]`

## Step 2 — Act on clear intent

The user said "plot this data." The scratchpad reveals time-series data with a
region dimension and altair available — a line chart colored by region is the
natural default. No need to ask; just build it.

## Step 3 — Write and validate

Compile-check the code (the kernel preamble from scratchpad.md provides graph access):

```python
from marimo._runtime.context import get_context
from marimo._ast.compiler import compile_cell
from marimo._types.ids import CellId_t

code = """
import altair as alt

chart = alt.Chart(sales).mark_line().encode(
    x="date:T",
    y="revenue:Q",
    color="region:N",
)
chart
"""

cell = compile_cell(code, cell_id=CellId_t("test"))
print(f"defs={cell.defs}, refs={cell.refs}")
```

Refs include `sales` — good, that's defined in an existing cell.

Test it in the scratchpad to confirm it runs:

```python
import altair as alt

chart = alt.Chart(sales).mark_line().encode(
    x="date:T", y="revenue:Q", color="region:N",
)
print(type(chart))  # confirm it built without error
```

## Step 4 — Create the cell

Use `_code_mode` to insert it into the notebook — see
[cell-operations.md](cell-operations.md) for how to discover the API.
Then format with ruff.

The user sees one clean cell appear with the chart rendered. The scratchpad
investigation and validation happened behind the scenes.
