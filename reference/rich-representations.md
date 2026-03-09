# Rich Representations

Custom visual encodings for data that go beyond standard charts and tables.

## Guiding principles

**Visualization matters.** Helping users build custom visual representations
is one of the highest-impact things the agent can do. A bespoke encoding
tailored to the task — labeling, batch review, comparing variants — lets
users *see* their data in ways that tables and numbers never will. marimo
is an environment where users create their own views, not just consume
library charts. Help them imagine what's possible, then build it.

**Use the modern web.** Always use the most modern HTML, CSS, and JavaScript
available. If a feature is supported in every browser, even if only the most
recent version, use it.

**Keep it thin, make it compose.** A widget is a thin layer over data, not
an application. One clear purpose, few traitlets, small `_esm`. Build small
pieces that compose in the notebook — combine with other cells, UI elements,
and views. Don't over-engineer.

## Decision tree

| Need | Approach |
|------|----------|
| Display-only rich output | `_display_()` — return any renderable object |
| Bidirectional/interactive (user input ↔ Python state) | anywidget — traitlets protocol |
| Standard controls (sliders, dropdowns, text) | `mo.ui.*` — already built-in |

If the user just needs to *see* something, use `_display_()`.
If they need to *interact* and feed values back to Python, use anywidget.

## `_display_()` protocol

Any object with a `_display_()` method renders richly in marimo. Return
anything marimo can render — `mo.Html`, `mo.md()`, a chart, a string.

Precedence: `_display_()` > built-in formatters > `_mime_()` > IPython
`_repr_*_()` methods.

```python
from dataclasses import dataclass
import marimo as mo

@dataclass
class ColorSwatch:
    colors: list[str]

    def _display_(self):
        divs = "".join(
            f'<div style="width:40px;height:40px;background:{c};border-radius:4px;"></div>'
            for c in self.colors
        )
        return mo.Html(f'<div style="display:flex;gap:8px;">{divs}</div>')
```

For inline `<script>` tags, use `document.currentScript.previousElementSibling`
to scope to the element — never hardcode IDs (breaks with multiple instances).

## anywidget

[anywidget](https://anywidget.dev) bridges Python and JavaScript via
traitlets. `.tag(sync=True)` makes a traitlet bidirectional — Python sets a
value → JS sees it; JS calls `model.set()` + `model.save_changes()` →
Python sees it. `_css` is optional global CSS.

### `_esm` lifecycle

**Render only** (most widgets):

```js
function render({ model, el }) { /* ... */ }
export default { render };
```

**Initialize + render** (shared state across views, one-time setup):

```js
export default () => {
  return {
    initialize({ model }) {
      // Once per widget instance — timers, connections, shared handlers
      return () => { /* cleanup */ };
    },
    render({ model, el }) {
      // Once per view — display in 3 cells = 3 renders
      return () => { /* cleanup DOM listeners */ };
    }
  };
};
```

- `model.on()` is auto-cleaned when a view is removed
- DOM `addEventListener` is **not** — clean up with `AbortController`

### Timer example (initialize + render)

`initialize` owns one interval; each `render` view displays it.

```python
import anywidget
import traitlets

class Timer(anywidget.AnyWidget):
    seconds = traitlets.Int(0).tag(sync=True)
    running = traitlets.Bool(True).tag(sync=True)

    _esm = """
    export default () => {
      return {
        initialize({ model }) {
          const id = setInterval(() => {
            if (model.get("running")) {
              model.set("seconds", model.get("seconds") + 1);
              model.save_changes();
            }
          }, 1000);
          return () => clearInterval(id);
        },
        render({ model, el }) {
          const controller = new AbortController();
          const { signal } = controller;

          const span = document.createElement("span");
          span.style.cssText = "font: 24px monospace;";

          const btn = document.createElement("button");
          btn.style.cssText = "margin-left: 8px; cursor: pointer;";

          function update() {
            const s = model.get("seconds");
            const mm = String(Math.floor(s / 60)).padStart(2, "0");
            const ss = String(s % 60).padStart(2, "0");
            span.textContent = `${mm}:${ss}`;
            btn.textContent = model.get("running") ? "⏸" : "▶";
          }

          model.on("change:seconds", update);
          model.on("change:running", update);

          btn.addEventListener("click", () => {
            model.set("running", !model.get("running"));
            model.save_changes();
          }, { signal });

          update();
          el.append(span, btn);
          return () => controller.abort();
        }
      };
    };
    """
```

### CDN dependencies

Import JS libraries from [esm.sh](https://esm.sh) — no build step:

```js
import * as d3 from "https://esm.sh/d3@7";
import { tableFromIPC } from "https://esm.sh/@uwdata/flechette@2";
```

### DataFrames and binary data

**Prefer reducing data on the Python side.** Aggregate, filter, sample —
send the widget only what it needs. Most widgets should receive a small,
pre-processed payload via simple traitlets (lists, dicts). This keeps the
widget simple and avoids extra dependencies.

**For large tabular data (>2k rows)** where the widget genuinely needs
row-level access, send Arrow IPC bytes instead of JSON. This adds
complexity and dependencies, so only reach for it when the data volume
justifies it.

**Python — serialize:**

```python
# Polars (native, no pyarrow needed)
_ipc=df.write_ipc(None).getvalue()

# Any __arrow_c_stream__ source (pandas, narwhals, pyarrow, etc.)
import io, pyarrow as pa, pyarrow.feather as feather

def to_arrow_ipc(data) -> bytes:
    table = pa.RecordBatchReader.from_stream(data).read_all()
    sink = io.BytesIO()
    feather.write_feather(table, sink, compression="uncompressed")
    return sink.getvalue()
```

**JS — deserialize with `@uwdata/flechette`:**

```js
import { tableFromIPC } from "https://esm.sh/@uwdata/flechette@2";
const table = tableFromIPC(new Uint8Array(model.get("_ipc").buffer));
// table.numRows, table.numCols, table.get(i), table.getChild("col_name")
```

Use `traitlets.Any().tag(sync=True)` for the IPC bytes traitlet.

## Reactive anywidgets in marimo

When an anywidget trait (selection, value, zoom, etc.) should drive a
downstream marimo cell, use `mo.state()` + `.observe()` on the **specific
trait**. This is the common pattern.

```python
# In the cell that creates the widget:
get_selection, set_selection = mo.state(widget.selection)
widget.observe(
    lambda _: set_selection(widget.selection),
    names=["selection"],
)

# In a downstream cell — re-executes when selection changes:
selection = get_selection()
```

**`mo.ui.anywidget(widget)`** wraps the *entire* widget and makes *all* synced
traits reactive. This is rare — only use it when the full widget state should
drive downstream cells, not just one trait.

### Scratchpad access

Read/write widget state from the scratchpad — no clicking:

```python
print(timer.seconds)    # read
timer.seconds = 0       # set — frontend updates automatically
```

See [ui-state](scratchpad.md#ui-state). `mo.ui.*` elements need
`set_ui_element_value`; anywidgets use direct assignment.
