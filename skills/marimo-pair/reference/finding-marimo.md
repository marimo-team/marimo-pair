# Finding and Invoking marimo

Only servers started with `--no-token` register in the local server registry
and are auto-discoverable — starting without a token makes discovery easier.
If a server has a token, set the `MARIMO_TOKEN` environment variable before
calling the execute script (avoids leaking the token in process listings).

```sh
marimo edit notebook.py --no-token [--sandbox]
```

Start marimo in edit mode without `--headless` unless the user asks for a
headless server. The notebook UI must be open in a browser before marimo has an
active session for `execute-code` to target. If running headless, give the user
the local URL and wait for them to open it before executing code.

How you invoke `marimo` depends on context — find the right way to run it.

## Notebooks with PEP 723 metadata require `--sandbox`

Before picking a runner, check the notebook file for a PEP 723 header:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "marimo",
#     "polars",
# ]
# ///
```

If the block is present, the notebook was authored as a self-contained
sandboxed script and **SHOULD be opened with `--sandbox`**. Without the flag
marimo runs in the ambient environment and silently ignores the inline
dependencies. Imports will fail or, worse, resolve to a different version than
the author pinned.

`--sandbox` works regardless of project context: inside a uv project, `uv run
marimo edit notebook.py --no-token --sandbox` still creates the isolated env
from the PEP 723 block rather than the project's `.venv`.

## Inside a Python project

If there's a `pyproject.toml` in cwd or a parent directory, check that marimo
is actually in the dependencies before using the project's runner. Look for
`marimo` in:

- `[project.dependencies]`
- `[project.optional-dependencies]` or `[dependency-groups]` (dev deps)
- `[tool.pixi.dependencies]`
- The project's `.venv` (`uv pip show marimo` or check `.venv/bin/marimo`)

If marimo is in a named dependency group (not the default), you need to
specify it:

```sh
# marimo is in [dependency-groups] → "notebooks" group
uv run --group notebooks marimo edit notebook.py --no-token
```

Once you know marimo is available, use whatever CLI runner the project uses:

```sh
# uv-managed project
uv run marimo edit notebook.py --no-token
# pixi-managed project
pixi run marimo edit notebook.py --no-token
```

Skip `--sandbox` here — the project already manages dependencies.

If `pyproject.toml` exists but marimo is **not** in the deps, treat this as
"outside a project" (see below).

## Outside a Python project

Prefer `--sandbox`. Sandbox mode creates an isolated environment for the
notebook and writes dependencies into the script itself as inline PEP 723
metadata — so the notebook stays self-contained and reproducible.

```sh
# With uv available (preferred)
uvx marimo@latest edit notebook.py --no-token --sandbox

# With marimo installed globally
marimo edit notebook.py --no-token --sandbox
```

## Global marimo install

If marimo is installed globally, check the version — code mode shipped in
v0.21.1. If the installed version is older, prompt the user to upgrade before
proceeding.

## Nothing found

If no project marimo, no `uv`/`uvx`, and no global `marimo` on PATH, tell the
user to install `uv` (<https://docs.astral.sh/uv/getting-started/installation/>).
