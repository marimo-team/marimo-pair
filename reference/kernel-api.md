# marimo Kernel API Reference

**`marimo._code_mode` is the primary API for cell operations.** This file
covers discovering raw kernel commands and notifications — use these only as an
escape hatch when `_code_mode` doesn't cover your need.

Recipes are split into focused files:

- [scratchpad.md](scratchpad.md) — scratchpad inspection recipes
- [cell-operations.md](cell-operations.md) — cell mutation recipes (uses `_code_mode`)

Each reference file includes its own preamble with the imports you need.

## Discovering the API

If an import fails or you need something not listed in the reference files,
explore from the scratchpad:

```python
import marimo
print(marimo.__file__)       # browse the source with your file tools
print(marimo.__version__)    # import paths change across releases

# List all kernel commands
import marimo._runtime.commands as commands
print([c for c in dir(commands) if c.endswith("Command")])

# List all frontend notifications
import marimo._messaging.notification as notification
print([n for n in dir(notification) if n.endswith("Notification")])
```

Use this to verify import paths and discover new APIs rather than guessing.
