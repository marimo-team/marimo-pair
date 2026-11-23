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

Ask your coding agent to start a marimo notebook or work with you in one you
already have open. The [marimo-pair skill](skills/marimo-pair/SKILL.md) shows
the agent how to use `marimo pair` or MCP to inspect data, edit cells, and run
them. You see the edits and results in your notebook.

## Prerequisites

Install marimo 0.26 or newer, or use uv to run it with `uvx marimo@latest`.

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
