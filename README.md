<h1>
<p align="center">
  /marimo-pair
</h1>
<p align="center">
  reactive Python notebooks as environments for agents
</p>
</p>

<div align="center">
  <video src="https://github.com/user-attachments/assets/d6d3f57a-e997-423c-bf14-8d9fba75e310" width="600" controls></video>
</div>

The `marimo-pair` skill helps your agent work alongside you in a live
notebook. Try asking it to “open analysis.py and show me the first five
rows of the dataset,” or use the same CLI yourself.

## Open a notebook

Use marimo 0.26 or newer for the notebook and CLI. Open an existing
notebook or create one at that path:

```sh
marimo edit analysis.py --sandbox
```

Leave the notebook open and run the pairing commands in a second terminal.
If you use uv or pixi, run the same commands with your launcher:

```sh
uvx marimo@latest pair --help
# In a pixi project with marimo installed
pixi run marimo pair --help
```

## Find a notebook and inspect its data

Local notebooks authenticate automatically. Copy the ID for your notebook
from the listing. If a cell defines a DataFrame named `df`, you can inspect
it from the terminal:

```sh
marimo pair list
# Listing excerpt: {"notebooks": [{"id": "nb-analysis", "name": "analysis.py"}]}
marimo pair execute --notebook nb-analysis --code 'print(df.head())'
```

For a remote notebook, pass its URL to both commands. This example uses a
token file supplied by the server operator:

```sh
marimo pair list --url https://notebooks.example.org --token-file ./token
# Listing excerpt: {"notebooks": [{"notebook_id": "nb-analysis", "name": "analysis.py"}]}
marimo pair execute --url https://notebooks.example.org --token-file ./token \
  --notebook nb-analysis --code 'print(df.head())'
```

## Show the result in the notebook

The previous command prints the preview in your terminal. To display it in
the notebook too, create and run a cell:

```sh
marimo pair execute --notebook nb-analysis --file - <<'PY'
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("df.head()")
    ctx.run_cell(cid)
PY
```

For examples of editing a cell, updating a widget, and installing a
package in the running notebook, see the [pairing skill](skills/marimo-pair/SKILL.md).

## Install the agent skill

### Agent Skills (any tool)

Works with any agent that supports the [Agent Skills](https://agentskills.io)
open standard:

```bash
npx skills add marimo-team/marimo-pair

# or upgrade an existing install
npx skills upgrade marimo-team/marimo-pair
```

If you don't have `npx` installed but have `uv`:

```bash
uvx deno -A npm:skills add marimo-team/marimo-pair
```

### Claude Code (plugin)

Add the marketplace and install the plugin:

```
/plugin marketplace add marimo-team/marimo-pair
/plugin install marimo-pair@marimo-pair
```

To opt in to auto-updates (recommended), so you always get the latest version:

```
/plugin → Marketplaces → marimo-pair → Enable auto-update
```

## Contributing

We'd love your help in improving this skill. After a marimo pair session,
please run the `/retro-marimo-pair` command to share feedback on how we can
improve the skill. You can also file an issue on the
[GitHub repository](https://github.com/marimo-team/marimo-pair/issues).
