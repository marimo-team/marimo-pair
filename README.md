<h1>
<p align="center">
  marimo-pair
</h1>
<p align="center">
  reactive Python notebooks as environments for agents
</p>
</p>

<div align="center">
  <video src="https://github.com/user-attachments/assets/d6d3f57a-e997-423c-bf14-8d9fba75e310" width="600" controls></video>
</div>

## Prerequisites

- A running [marimo](https://marimo.io) notebook (`--no-token` for
  auto-discovery; `MARIMO_TOKEN` env var for servers with auth)
- `bash`, `curl`, and `jq` available on `PATH`

## Install

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
/plugin install marimo-pair@marimo-team-marimo-pair
```

To opt in to auto-updates (recommended), so you always get the latest version:

```
/plugin → Marketplaces → marimo-team-marimo-pair → Enable auto-update
```

## FAQ

### I keep getting prompted to allow Bash commands

The skill declares its own `allowed-tools`, but Claude Code may still prompt
you to approve each Bash call. To avoid repeated prompts, copy the absolute
paths to the scripts from the installed skill and add them to your
`.claude/settings.json` (project-level) or `~/.claude/settings.json` (global):

```json
{
  "permissions": {
    "allow": [
      "Bash(bash /path/to/skills/marimo-pair/scripts/discover-servers.sh *)",
      "Bash(bash /path/to/skills/marimo-pair/scripts/execute-code.sh *)"
    ]
  }
}
```
