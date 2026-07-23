# Work with marimo Lens

marimo Lens records the output and location a user points at. An optional note
adds intent. Pair uses that attention to resolve references such as "this
cell", inspect the relevant notebook graph, and report the verified result
back in the notebook.

## Start with one scan

Scan after connecting:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 scan
```

The entrypoint owns Lens availability detection. When `marimo-lens` is
unavailable or the notebook has no live Lens object, it exits successfully
with:

```json
{"action":"scan","result":{"status":"absent"}}
```

Continue with the ordinary Pair workflow and do not retry Lens during the same
request. Scan again after the notebook state changes or the user explicitly
asks.

A `ready` result contains bounded selection data:

```json
{
  "action": "scan",
  "result": {
    "status": "ready",
    "lensToken": "F3n...",
    "revision": 8,
    "lens": {"variable": "lens"},
    "selectionCount": 1,
    "current": {
      "id": "243110...",
      "label": "S1",
      "outputCellId": "BYtC",
      "note": {"text": "Use completed orders", "truncated": false}
    },
    "currentCell": {
      "id": "BYtC",
      "status": "available",
      "defs": ["revenue"],
      "refs": ["orders"]
    }
  }
}
```

Use `current` as the likely referent for "this", "here", or "the selected
cell". The user's current request has priority over an older note. An explicit
cell ID or variable in the request has priority over an inferred referent.

Keep the scan's stable selection ID, revision, and Lens token together. Later
commands use them to avoid acting on selection state that changed during the
task.

## Load context progressively

The selected output cell is the semantic notebook target. Read that cell
through `marimo._code_mode`, then inspect ancestors or descendants only when
the task needs them:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cell = ctx.graph.cells["BYtC"]
    print(cell.code)
    print(ctx.graph.ancestors("BYtC"))
```

The scan, selected cell, note, DOM hint, and dataflow graph are the default
context. Load standalone Lens text when those sources are insufficient:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  text --revision 8 --lens-token 'F3n...'
```

Read the packet from `.result.text`. It can be substantially larger than the
scan, so keep this step lazy.

## Use images when pixels carry evidence

A selection image preserves the pixels and annotation captured when the user
pointed:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  image --selection-id '243110...' \
  --revision 8 --lens-token 'F3n...'
```

Capture the current full output of a cell when visual verification depends on
its latest rendering:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  image --cell BYtC --revision 8 --lens-token 'F3n...'
```

The cell image contains every open Lens point and region on that output in one
current raster. Prefer it when several relevant selections share a cell. Use a
selection image when the pixels captured at the time of one selection are
material to the request.

Both commands return image metadata and a private temporary `path`. The cell
result includes `selectionCount`, which reports how many marks were drawn.
Read the file with the agent client's image tool. The JSON packet contains no
image bytes. Remove the returned directory after the task:

```bash
bash scripts/lens-context.sh cleanup-images \
  '/tmp/marimo-pair-lens.A1b2c3'
```

Use text and graph evidence for text-only models. An unavailable image does
not invalidate its cell-backed selection.

## Show progress in the notebook

Mark the primary cell before focused work:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  activity --cell BYtC --lens-token 'F3n...' \
  --label "On it" \
  --message "Updating the aggregation used by this output"
```

Activity is transient and does not scroll. It stays visible while the cell
rerenders and remains active until another activity or a reveal replaces it.
Choose one short label for the run. The message names the concrete work.

Keep activity visible while applying edits, running explicitly requested
cells, waiting for reactive descendants, and correcting execution errors.
After the mutation call completes, inspect the target and affected cells in a
fresh execution call. A cell is complete when its status is `idle`. Run a
relevant stale downstream cell explicitly when the notebook uses lazy
execution.

## Resolve and reveal completed attention

Resolve a selection after the notebook edit is committed, affected cells have
run, and the requested result is verified:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  resolve '243110...' '8b20f4...' --revision 8 --lens-token 'F3n...' \
  --summary "Updated the aggregation and verified the chart."
```

One resolve command commits every supplied selection together. Use one shared
summary when one verified change addresses several annotations. Issue separate
commands when the selections require distinct explanations.

The summary is a concise receipt for the user. If the user requests changes,
Lens can reopen a selection. A later scan exposes the prior receipt as
`current.previousResolution`.

Reveal the primary result after resolution:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  reveal --cell BYtC --lens-token 'F3n...' \
  --message "Updated the aggregation and verified the output"
```

Reveal scrolls once, highlights the cell, and ends activity. Use one primary
cell. Mention secondary cells in the normal response.

Leave the selection open when work is partial or verification fails. On
`revision-conflict` or an error with code `lens_changed`, scan again and
confirm that the current selection still grounds the completed work before
retrying.

## Result handling

- `ready`: Continue from the returned Lens context.
- `absent`: Continue with the ordinary Pair workflow.
- `ambiguous`: Ask the user to leave one displayed Lens instance, then scan
  again.
- `selection-not-found`: Scan again because the selection changed or was
  removed.
- `image-unavailable`: Continue from text and graph evidence.
- `capture-timeout`: Continue from text or retry once after the output settles.
- `revision-conflict` or error code `lens_changed`: Scan again before acting.
- `error`: Report the returned code and keep unresolved attention open.
