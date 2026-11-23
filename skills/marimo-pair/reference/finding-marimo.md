# Finding and Invoking marimo

Start the notebook with `marimo edit notebook.py`, using the launcher for
its environment as described below. Once the notebook is open, use
`marimo pair list` to find its ID. Local discovery handles authentication
automatically.

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
marimo edit notebook.py --sandbox` still creates the isolated env
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
uv run --group notebooks marimo edit notebook.py
```

Once you know marimo is available, use whatever CLI runner the project uses:

```sh
# uv-managed project
uv run marimo edit notebook.py
# pixi-managed project
pixi run marimo edit notebook.py
```

Use the project environment when it manages the notebook’s dependencies.
For notebooks with inline dependencies, include `--sandbox` as described above.

If `pyproject.toml` exists but marimo is **not** in the deps, treat this as
"outside a project" (see below).

## Outside a Python project

Prefer `--sandbox`. Sandbox mode creates an isolated environment for the
notebook and writes dependencies into the script itself as inline PEP 723
metadata — so the notebook stays self-contained and reproducible.

```sh
# With uv available (preferred)
uvx marimo@latest edit notebook.py --sandbox

# With marimo installed globally
marimo edit notebook.py --sandbox
```

## Global marimo install

Use `marimo --version` to check that the global installation meets the
skill’s marimo 0.26+ requirement.

## Nothing found

If no project marimo, no `uv`/`uvx`, and no global `marimo` on PATH, tell the
user to install `uv` (<https://docs.astral.sh/uv/getting-started/installation/>).

## Legacy shell script discovery

For troubleshooting the older `discover-servers.sh` script, a registering server writes one JSON file per instance and removes it on clean
shutdown: `$XDG_STATE_HOME/marimo/servers` (default `~/.local/state/marimo/servers`)
on Linux and macOS, `%USERPROFILE%\.marimo\servers` on Windows.

Inside WSL, both are in play. A notebook started in the distro registers at the
XDG path; one started on the Windows host registers in the Windows profile,
which `discover-servers.sh` also reads. Windows-host servers show up with
`"origin": "windows-host"`, and reaching them depends on WSL networking: under
the default NAT the distro has its own loopback, so a host notebook bound to
`127.0.0.1` is unreachable and only `--host 0.0.0.0` (or mirrored networking)
lets WSL connect. The `url` in each entry already accounts for this, so use it.

Cross-OS discovery needs WSL interop: `cmd.exe` to locate the Windows profile,
and `tasklist.exe` to tell a live Windows PID from a dead one. With interop
disabled, only servers inside the distro are found.
