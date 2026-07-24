# Work with marimo Lens

marimo Lens records the output and location a user points at. An optional note
adds intent. Pair uses that attention to resolve references such as "this
cell", inspect the relevant notebook graph, and report a verified result in the
notebook.

Resolve every helper path from the directory containing the loaded
`SKILL.md`. Run the examples from that directory or replace `scripts/` with its
absolute path.

## Ground one request

When the user delegates intent to current Lens selections and the client can
read images, use one grouped cell image in the connection probe:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  scan --image cell
```

This is the efficient default when the prompt does not repeat the Lens notes.
It loads one current output with every open point and region on that cell.

Use a plain scan for an explicitly semantic request or a text-only client:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 scan
```

The URL is the target. Do not run server discovery first.

When the request needs the pixels captured at selection time, request the
selection image instead:

```bash
# Pixels captured when the current selection was created
bash scripts/lens-context.sh --url http://localhost:2718 \
  scan --image selection
```

The entrypoint owns Lens availability detection. An unavailable package or a
notebook with no live Lens object returns:

```json
{"action":"scan","result":{"status":"absent"}}
```

Continue with the ordinary Pair workflow and skip Lens calls for the rest of
the request. Start a new scan for a later user request.

A ready scan contains bounded selection data:

```json
{
  "action": "scan",
  "result": {
    "status": "ready",
    "lensToken": "F3n...",
    "revision": 8,
    "selectionCount": 2,
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
    },
    "image": {
      "status": "available",
      "source": "cell",
      "path": "/tmp/marimo-pair-lens.A1b2c3/image.png",
      "imageDir": "/tmp/marimo-pair-lens.A1b2c3",
      "selectionCount": 2
    }
  }
}
```

The `image` field appears for `scan --image`. The command can return a ready
scan with an image substatus such as `image-unavailable`,
`revision-conflict`, or `capture-timeout`. Inspect the scan's semantic context
and follow the image recovery rule for that substatus.

Use `current` as the likely referent for "this", "here", or "the selected
cell". The explicit user request has priority over an older note. An explicit
cell ID or variable has priority over an inferred referent.

Keep the scan's selection IDs, revision, and Lens token together. Later
commands use them to prevent actions against changed human attention.

## Choose evidence before planning

Choose both evidence lanes before the first notebook mutation:

| Request signal | Evidence |
| --- | --- |
| Cell identity, error, calculation, variable, upstream cause | Scan, selected cell code, bounded graph metadata |
| Color, position, spacing, overlap, size, alignment, legibility, chart mark | Selection image |
| Several relevant selections on one output | One current cell image containing every mark |
| Compare the original view with current output | Selection image, plus a current cell image when `outdated` is true |
| Verify a visual change | Fresh cell image after execution |
| Text-only client | Scan, code, graph, DOM hint, and Lens text as needed |

An image command materializes a private temporary file. Open the returned
`path` with the client application's local-image reader before reasoning about
pixels. An image command is incomplete until that read occurs.

The JSON response contains image metadata and the path. It does not place PNG
bytes in the model's text context. A text-only client skips image commands and
must not claim pixel verification.

After a plain scan, fetch one selection image with the stable scan identity:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  image --selection-id '243110...' \
  --revision 8 --lens-token 'F3n...'
```

Fetch the current full output for one cell:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  image --cell BYtC --revision 8 --lens-token 'F3n...'
```

The cell image contains every open Lens point and region on that output. Its
`selectionCount` reports how many marks were drawn. Use one cell image for
several relevant selections that share the output.

When those marks are legible, continue from that grouped image. Fetch a
selection image when the original captured pixels are part of the request or
one mark remains ambiguous.

A selection image preserves the pixels captured when the user pointed. When
its metadata reports `outdated: true`, use it as historical evidence and
inspect a current cell image before editing or verifying current output.

Track each returned `imageDir`. Remove it after the last image read:

```bash
bash scripts/lens-context.sh cleanup-images \
  '/tmp/marimo-pair-lens.A1b2c3' \
  '/tmp/marimo-pair-lens.D4e5f6'
```

## Resolve the semantic workset

Read the selected output cell, required graph neighbors, and bounded runtime
values in one scratchpad call:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cell = ctx.graph.cells["BYtC"]
    print(cell.code)
    print(ctx.graph.ancestors("BYtC"))
```

Form the workset from the explicit request and current selection. Add older
selections when their note describes the same concrete change. Group the
workset by `outputCellId` before loading code or images.

Load standalone Lens text when a relevant note was truncated, when a secondary
`notePreview` was truncated, or when the bounded scan omits detail needed for
the request:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  text --revision 8 --lens-token 'F3n...'
```

Read the packet from `.result.text`. It is larger than the scan, so keep this
step tied to a specific missing detail.

Pair's cell edits and reruns preserve the scan identity. Rescan when:

- The user starts a new request or changes human attention.
- A command returns `revision-conflict`.
- A command returns `selection-not-found`.
- A command returns error code `lens_changed`.

A Pair-triggered cell rerun is not a reason to rescan.

## Show activity and apply one coherent mutation

Start activity after grounding is complete and the edit plan is known. Choose
a short activity label from the user's intent. The label is conversational
display copy, while the message states the concrete action. Submit the
activity command and one code-mode mutation call as one shell command joined
by `&&`:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  activity --cell BYtC --lens-token 'F3n...' \
  --label "Checking this now..." \
  --message "Using completed orders in the selected output" &&
bash scripts/execute-code.sh --url http://localhost:2718 <<'PY'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    ctx.edit_cell(
        "BYtC",
        'revenue = orders.query("status == \'completed\'")\nrevenue',
    )
    ctx.run_cell("BYtC")
PY
```

Queue related `edit_cell`, `create_cell`, `delete_cell`, package, UI, and
`run_cell` operations inside the same `cm.get_context()` block when they form
one coherent change. Read every replaced cell body before submitting its full
replacement.

Activity remains visible through edits, execution, reactive descendants, and
verification. Do not submit the mutation when the activity command fails.
Vary the label naturally across runs. Suitable shapes include acknowledgments
such as `On it...`, `Got it...`, and `Taking a look...`, investigations such
as `Checking this now...` and `Tracing the mismatch...`, and concrete work
such as `Fixing those bars...`, `Cleaning this up...`, and
`Tuning the chart...`. Treat this vocabulary as inspiration and select by
intent. Keep the chosen label stable through one activity. Avoid a mechanical
label such as `Updating` when a clearer phrase fits. When a blocker requires
user input after activity starts, update the same cell with a `Needs input`
label and a concrete message. Leave its selections open.

## Verify, resolve, and reveal

Verification is a fresh scratchpad call after the mutation call completes.
Inspect the target and every cell needed to support the final claim:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    for cell_id in ("BYtC",):
        cell = ctx.cells[cell_id]
        print(cell_id, cell.status, cell.errors)
```

Every claimed cell must be `idle` with no relevant errors. Run a stale
downstream cell explicitly when the notebook uses lazy execution. For visual
work, fetch and open a fresh cell image after execution using the original
scan identity:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  image --cell BYtC --revision 8 --lens-token 'F3n...'
```

This image read verifies current pixels. It does not replace the fresh runtime
status and error check. Pair's own edit does not require another scan.

After verification, resolve selections that share one change and rationale,
then reveal the primary result in the same shell turn:

```bash
bash scripts/lens-context.sh --url http://localhost:2718 \
  resolve '243110...' '8b20f4...' \
  --revision 8 --lens-token 'F3n...' \
  --summary "Updated the aggregation and verified the chart." &&
bash scripts/lens-context.sh --url http://localhost:2718 \
  reveal --cell BYtC --lens-token 'F3n...' \
  --message "Updated the aggregation and verified the output"
```

One resolve command commits every supplied selection together. Use one shared
summary when one verified result addresses them. Issue separate resolve
commands for distinct changes or rationales.

Reveal scrolls to one primary cell, highlights it, and ends activity. Mention
secondary cells in the normal response. Resolution is premature until the
fresh runtime check passes. Remove every tracked image directory after the
last image read, including when resolution or reveal fails:

```bash
bash scripts/lens-context.sh cleanup-images \
  '/tmp/marimo-pair-lens.A1b2c3' \
  '/tmp/marimo-pair-lens.D4e5f6'
```

Pass all returned `imageDir` values to the same command.

A reopened selection exposes the prior receipt as
`current.previousResolution`. Treat the new user request as the current intent
and use the receipt as history.

## Handle results

- `ready`: Continue from the returned Lens context.
- `absent`: Continue with the ordinary Pair workflow for this request.
- `ambiguous`: Ask the user to leave one displayed Lens instance, then scan.
- `selection-not-found`: Scan and confirm the new selection before acting.
- `image-unavailable`: Continue from text and graph evidence.
- `capture-timeout`: Continue from text or retry once after the output settles.
- `revision-conflict`: Scan and confirm the workset before acting.
- Error code `lens_changed`: Scan because the displayed Lens instance changed.
- `error`: Report the returned code and keep unresolved attention open.

Do not cross the two observation boundaries. Ground the request before the
first mutation. Verify current runtime output before resolution.
