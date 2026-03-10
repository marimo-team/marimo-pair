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

**Prefer compact output.** marimo clips cell output at ~610px and scrolls.
Avoid hitting that limit; if you need more space, manage your own scrolling
inside a fixed-height container.

**Keep it thin, make it compose.** A widget is a thin layer over data, not
an application. One clear purpose, few traitlets, small `_esm`. Build small
pieces that compose in the notebook — combine with other cells, UI elements,
and views. Don't over-engineer.

## Decision tree

| Need | Approach |
|------|----------|
| Custom view, explorer, panel, gallery, or any bespoke UI | **anywidget** — always the default for custom work |
| Display-only rich output (no interaction needed) | `_display_()` or `mo.Html` for one-off static HTML |
| Single built-in control used as-is (slider, dropdown) | `mo.ui.*` |

When in doubt, build an anywidget. Small upfront cost, full control.

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

## Skeleton / empty state

Render an animated placeholder when items are empty — avoids blank flash and
layout shift. Put this at the top of `render()`'s draw function, before the
real content path.

```js
// shimmer keyframe — add to _css
// @keyframes shimmer { to { background-position: -200% 0; } }

function skeleton(el, n = 3) {
  el.innerHTML = Array.from({ length: n }, () =>
    `<div style="height:48px;border-radius:8px;margin-bottom:8px;
      background:linear-gradient(90deg,#e0e0e0 25%,#f0f0f0 50%,#e0e0e0 75%);
      background-size:200% 100%;animation:shimmer 1.5s infinite"></div>`
  ).join("");
}
```

## Selection widget scaffold

Core pattern: `items` list + `selected_index` int, skeleton when empty,
click handler, `model.on("change:…", draw)`.

```python
import anywidget, traitlets

class SelectionWidget(anywidget.AnyWidget):
    items = traitlets.List([]).tag(sync=True)
    selected_index = traitlets.Int(-1).tag(sync=True)

    _css = """
    @keyframes shimmer { to { background-position: -200% 0; } }
    .sel-item { padding:8px 12px; border-radius:6px; cursor:pointer; }
    .sel-item:hover { background:#f0f0f0; }
    .sel-item[aria-selected="true"] { background:#e0edff; font-weight:600; }
    .sel-skeleton { height:40px; border-radius:6px; margin-bottom:6px;
      background:linear-gradient(90deg,#e0e0e0 25%,#f0f0f0 50%,#e0e0e0 75%);
      background-size:200% 100%; animation:shimmer 1.5s infinite; }
    """

    _esm = """
    function render({ model, el }) {
      function draw() {
        const items = model.get("items");
        if (!items.length) {
          el.innerHTML = Array.from({ length: 3 },
            () => `<div class="sel-skeleton"></div>`).join("");
          return;
        }
        const sel = model.get("selected_index");
        el.innerHTML = items.map((item, i) =>
          `<div class="sel-item" data-i="${i}"
               aria-selected="${i === sel}">${item}</div>`
        ).join("");
      }

      el.addEventListener("click", (e) => {
        const row = e.target.closest("[data-i]");
        if (!row) return;
        model.set("selected_index", +row.dataset.i);
        model.save_changes();
      });

      model.on("change:items", draw);
      model.on("change:selected_index", draw);
      draw();
    }
    export default { render };
    """
```

Extend with pagination, search, richer item rendering as needed.
