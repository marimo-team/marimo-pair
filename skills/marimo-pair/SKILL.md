---
name: marimo-pair
description: >-
  Drive a live marimo notebook as a workspace: run Python in the same kernel
  the user does, inspect live notebook state, and commit durable notebook
  changes. Use when the user wants to start a marimo notebook or pair on an
  active marimo session.
allowed-tools: Bash(bash **/scripts/discover-servers.sh *), Bash(bash **/scripts/execute-code.sh *), Read
---

marimo is a reactive Python runtime for building reproducible Python programs
(marimo notebooks). Cells are connected by the variables they define and
reference. Running a cell re-executes dependents in dataflow order. The active
runtime holds the kernel namespace, cell state, and dataflow graph. The
notebook (`.py` file) is the artifact the kernel writes from that state while a
session is running.

A user interacts with the same runtime via a notebook UI with cells, outputs,
and widgets.

**WARNING. The active runtime is the source of truth.** During a session, you
SHOULD NOT modify the associated `.py` file directly. File edits WILL NOT reach
the active kernel or user, and the kernel may overwrite them on save. Use
`marimo._code_mode` (`cm`) for notebook changes. Reading disk is fine, but
prefer `ctx.cells[...].code` for current cell code.

## Connect to a Notebook

Use the bundled script (`bash scripts/execute-code.sh`) or MCP
(`execute_code(...)`) to run Python in a live marimo kernel.

`execute-code.sh` always takes `--url`. If the user provides a notebook URL,
target it directly:

```bash
bash scripts/execute-code.sh --url http://localhost:2718 -c "print('connected')"
```

Pass code with `-c CODE`, `-` for stdin, or a file path:

```bash
bash scripts/execute-code.sh --url http://localhost:2718 - <<'PY'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = df.head()")
    ctx.run_cell(cid)
PY
```

If the user gives no URL, find or start a notebook. Look for a running server
with `bash scripts/discover-servers.sh`, MCP `list_sessions()`, or local
process context, and pass the `url` it reports to `--url`. With one notebook
open, the script targets it automatically; with several, pass `--file` with
the notebook's file key.

If no server is running and the user wants a notebook, start marimo with
`--no-token` (and without `--headless`) so it auto-registers for discovery. The
notebook UI must be open for `execute-code` to target it. The right invocation
depends on context (project tooling, global install, sandbox mode). If the
notebook file contains a PEP 723 `#
/// script` header, it MUST be opened with `--sandbox` — otherwise marimo
ignores the inline dependencies. See
[finding-marimo.md](reference/finding-marimo.md) for the full decision tree and
[execution-context.md](reference/execution-context.md) for selector resolution,
scripts, MCP, and shell quoting.

## Scratchpad Scope

`execute-code` evaluates Python in marimo's scratchpad: a temporary namespace
with a shallow copy of the kernel globals. Notebook variables are available by
name, but new top-level bindings and rebindings are discarded after each call.
In-place mutations to notebook-owned objects can persist because those names
still reference live objects.

Each call reports stdout and stderr from the scratchpad, plus console output
from notebook cells it causes to run, including reactive descendants.

### Ordinary Python

**Match your first move to the request type:**

**Minimize scratchpad round-trips** — each `execute-code` call is a model
  turn. Combine related computations into one script that prints all results
  together. Never make a separate call just to print or verify a value you
  could have printed in the previous call.

**No planning-only turns** — every model turn must either execute code or
  deliver the final answer. Never spend a turn on text-only reasoning,
  outlining what you plan to compute, or narrating your analysis strategy.
  Fold planning into the same turn as the scratchpad call it informs.

- **Directed request** — the task names the specific columns, variables, or
  metrics to produce. Read all requirements first and write a single script
  that inspects the data AND computes every required value; print all results
  together. Skip standalone structure exploration (shape, dtypes, head) and go
  straight to computing the answers. One comprehensive call is far better than
  incremental exploration across multiple turns.
- **Open-ended request** — the task asks you to explore, investigate, or
  decide yourself what is worth reporting. There, exploration is the
  foundation of the deliverable: inspect structure and coverage first (shape,
  dtypes, key distributions, date/category coverage), let what you find steer
  what you compute, and only then write findings. Do NOT compress this into
  one blind pass — a fast report built on unexamined assumptions is a failed
  report. Batching *within* a step is still good; skipping the looking is not.
  Aim for 2–3 scratchpad calls total: (1) explore structure AND compute
  first-pass analysis together (shape, dtypes, key distributions, initial
  counts/aggregations — these naturally fit one script), (2) deeper analysis
  steered by what you found, (3) any remaining follow-ups. Do not make a
  separate call per analysis dimension — combine them.

**Broad briefs get deepening, not extra calls** — when an open-ended request
spans multiple axes at once (characterize/overview/"key structural findings"
covering a whole dataset or several dimensions together), fold second-order
metrics (enrichment/lift vs baseline, distributions instead of single
aggregates, cross-dimension breakdowns) into the same 2–3 call budget as
scoped requests. Design call 2 to deepen the most promising threads from
call 1 *and* compute any remaining first-pass dimensions together. Do NOT
add a separate deepening pass — a well-designed second call covers both.

Use ordinary Python in the scratchpad to inspect variables, sample data, test
transformations, probe APIs, check imports, and read widget state.

**Plan before calling (directed requests)** — when the task lists specific
variables to define, read every requirement first and write one scratchpad
call that computes all of them. The task description tells you what to
compute; use that to write comprehensive code in a single turn.

```python
print(df.head())

x = 10
print(x)
```

Here `df` comes from notebook globals, while `x` is a scratchpad-local binding.
`x` exists for this call only and WILL NOT be added to notebook globals.

### Verify What You Report

Every number in a final answer or report must come from computation you
actually ran in this session:

- **Count, don't assume.** Dataset constants — weeks per year, row counts,
  distinct categories, date coverage — must be measured from the data
  (`nunique()`, `value_counts()`, min/max), never assumed from the calendar or
  from convention. A 53-week year or a partial year silently corrupts every
  figure derived from it.
- **No uncomputed comparisons.** Never write "roughly 2×" or "nearly double"
  unless you computed that ratio. State the computed value or leave the
  comparison out.
- **Check before you characterize.** Before asserting a pattern (top-N
  ranking, share, trend), print the underlying values and confirm the claim
  matches what you see.

Speed never justifies an unverified claim — but a *separate* verification
call is rarely needed. Print verification values (sanity checks, totals,
cross-tabs) inline at the end of the same script that computes them. A
wrong number in a delivered report is expensive; an extra model turn to
re-print what you already computed is pure waste.

### Persist with `cm`

Top-level scratchpad assignments and rebindings are temporary. To persist work,
including new variables, you MUST submit changes through `marimo._code_mode`
(`cm`).

`marimo._code_mode` is a PRIVATE, UNSTABLE agent API (note the leading
underscore). It exists for tools like this skill to drive a live kernel from
the scratchpad. DO NOT import it from notebook cells, library code, or
anything a user would run — methods can change or disappear across marimo
versions and kernels. Treat every `import marimo._code_mode as cm` as
scratchpad-only.

At session start, inspect what `cm` exposes in the active kernel:

```python
import marimo._code_mode as cm

help(cm)
```

Open a code-mode context to queue notebook changes.

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = df.head()")
    ctx.run_cell(cid)
```

The scratchpad supports top-level async code. Use `async with` directly;
wrapping it in `asyncio.run(...)` is unnecessary and can conflict with the
kernel's event loop.

After this block exits and the new cell runs, `x` is notebook state. Later
scratchpad calls can read `x` by name. Code later in the same scratchpad call
should read `ctx.globals["x"]`, because the scratchpad namespace was copied
before the cell ran.

Inside the context, queued mutation methods are synchronous. Call them
directly; do not `await` them. Each call queues an operation for marimo to
apply when the context exits normally. If the block raises, the queue is
discarded.

On clean exit, marimo applies packages, validates and applies structural cell
changes, runs queued cells, then may run dependents. Validation is only
structural since queued cell runs can still error. `create_cell` and
`edit_cell` change notebook structure only. Use `run_cell` to execute. 

`create_cell` currently defaults to `hide_code=True`, which collapses the code
editor in the UI. Pass `hide_code=False` if the user wants created cells to
be visible without manually expanding them.


## Marimo Rules

marimo imposes a small contract on notebook code so it can keep the notebook as
a directed acyclic graph (DAG):

- **No cycles** - cells cannot depend on each other in a cycle.
- **No public redefinitions across cells** - each name has one owning cell.
- **No wildcard imports** - `import *` prevents static analysis of definitions.

These rules keep the kernel, UI, and saved artifact consistent.

When `cm` submits a cell body, marimo parses its top-level definitions and
references. A top-level name enters the graph unless it is private with a
leading underscore.

```python
# Public definitions: values, total, i, value, mean
values = np.array([1, 2, 3])
total = 0
for i, value in enumerate(values):
    total += value
mean = total / len(values)
mean
```

```python
# Public definition: mean
_values = np.array([1, 2, 3])
_total = 0
for _i, _value in enumerate(_values):
    _total += _value
mean = _total / len(_values)
mean
```

Use private names for intermediates that no other cell should read. Public
names define the notebook-level dataflow. If a `cm` edit violates the contract,
marimo rejects the structural change and returns the validation error.

## The Notebook's Shape

A notebook is an ordered collection of cells. `ctx.cells` is the document view
and `ctx.graph` is the dataflow view.

```python
for cell in ctx.cells:
    cell  # .id, .code, .name, .config, .status, .errors

ctx.cells["setup"]         # by name
ctx.cells[0]               # by position
list(ctx.cells.keys())     # all IDs, in notebook order
```

Cell IDs are opaque strings which can be queried from the notebook or captured
from `cm` return values:

```python
cid = ctx.create_cell("df = pd.read_csv('data.csv')")
print(cid)   # e.g. 'Hbol'
```

Alternatively, cells can be assigned and referenced by `name`. The graph can be
used to understand its role in the dataflow.

```python
for cid, impl in ctx.graph.cells.items():
    impl  # .defs, .refs   (sets of public names)

ctx.graph.descendants(cid)   # cells that re-run when this one changes
ctx.graph.ancestors(cid)     # cells this one depends on
```

In marimo, deletes are *destructive* so it can be useful to query the
descendants prior to deleting to understand it's impact.

## Writing Notebook Changes

The graph contract keeps marimo able to run and save the notebook. Passing
those checks alone does not guarantee a useful artifact. Committed cells should
still be readable, rerunnable, and editable.

Make durable edits that reuse the notebook's existing names, imports,
dependencies, and UI model. Don't be lazy. Avoid one-off workarounds that pass
`cm` validation but leave a brittle notebook.

### Cell Bodies

**Batch cell operations** — create all cells in a single `execute-code`
call with one `async with cm.get_context()` block. Multiple `create_cell` and
`run_cell` calls can be queued in the same block. Do NOT spread cell creation
across multiple turns.

```python
async with cm.get_context() as ctx:
    c1 = ctx.create_cell("n_nodes = len(nodes)", hide_code=False)
    c2 = ctx.create_cell("n_edges = len(edges)", hide_code=False)
    ctx.run_cell(c1)
    ctx.run_cell(c2)
```

Submit the code that belongs in the cell.

- **Submit cell contents** - `create_cell` and `edit_cell` take cell contents,
  not saved-file `@app.cell` wrappers.
- **Read before replacing** - for now, another editor may change a cell between
  scratchpad calls. Before `edit_cell`, read the current body from
  `ctx.cells[...]` and submit the full replacement.
- **Reuse notebook imports** - if `np` already exists, use it or edit the owning
  import cell. DO NOT add `import numpy as _np` just to bypass the graph.
- **Define public names intentionally** - use public names for values later
  cells should reference. Use private `_name` bindings or function locals for
  same-cell intermediates.
- **Define each public name once** - a public name has one owning cell.
  Reassigning it in another cell fails with `Multiply-defined names`; edit the
  owning cell or give the result a new name. See
  [gotchas.md](reference/gotchas.md).
- **Run cells deliberately** - `create_cell` and `edit_cell` change structure
  only. Queue `ctx.run_cell(...)` when the cell should execute.

### Prefer `cm`-Managed Changes

Use `cm` APIs when they exist. Avoid direct file edits, shell package commands,
and scratchpad-only state for changes that should persist.

- **Do not edit the `.py` artifact** - DO NOT use `Edit`, `Write`, or
  `NotebookEdit` on the notebook file during a live session. Use
  `ctx.edit_cell(...)` even for small changes.
- **Manage packages through `cm`** - use `ctx.packages.add()` or
  `ctx.packages.remove()` instead of direct `uv` or `pip`; confirm
  non-obvious dependency changes.
- **Avoid transient paths** - persisted cells should not depend on `/tmp/...`
  unless the work is intentionally transient.
- **Delete deliberately** - deleting a cell removes globals it defines. Reuse
  empty cells when convenient and delete cells left empty after edits.

### UI and Widgets

Inspect the object before changing it. Different UI objects update through
different paths.

- **Set `mo.ui.*` through `cm`** - use `ctx.set_ui_value(element, value)` inside
  `cm.get_context()`.
- **Set anywidget traitlets directly** - synced traitlets are Python
  attributes, for example `widget.value = 5`.

For designing custom visual or interactive output, see
[rich-representations.md](reference/rich-representations.md).

## References

- [execution-context.md](reference/execution-context.md) — scripts, MCP, auth, startup, and shell quoting
- [finding-marimo.md](reference/finding-marimo.md) — choosing the right marimo invocation
- [gotchas.md](reference/gotchas.md) — name redefinition, cached module proxies, and notebook traps
- [rich-representations.md](reference/rich-representations.md) — custom widgets and visualizations
- [notebook-improvements.md](reference/notebook-improvements.md) — improving existing notebooks
