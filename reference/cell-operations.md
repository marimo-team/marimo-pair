# Cell Operations Reference

Cell operations live in `marimo._code_mode`. The module exposes a context
object and an edit system — you apply edits to the notebook through the context.

## Preamble

```python
import marimo._code_mode as cm

ctx = cm.get_context()
```

On first use, discover the API surface:

```python
print([x for x in dir(cm) if not x.startswith('_')])
print([x for x in dir(ctx) if not x.startswith('_')])
```

Drill into classes and methods with `dir()` and `help()`. They are the source
of truth, not this file.

## Common edits

- **Insert cells** at a position
- **Edit a cell's** code or config (supports drafts for user review)
- **Delete cells** by index range
- **Move a cell** — delete + insert (no dedicated primitive)

## Other operations

The context also provides ways to:

- **Execute stale cells**
- **Install packages** (confirm with user first)
- **Notify the user** (toast, banner, focus a cell)

## Escape Hatch

The context exposes methods for raw kernel commands and notifications —
use these for anything the edit API doesn't cover. See
[kernel-api.md](kernel-api.md) for how to enumerate available commands
and notifications.

## Pitfalls

- **Must `await` edit calls** — forgetting `await` silently does nothing.
- **Cell handles come from the context** — you can't construct one manually.
- **Don't write to the `.py` file directly** — the kernel owns it.
