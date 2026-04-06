# marimo-pair

> [!WARNING]
> Experimental agent skill for pair programming in [marimo](https://marimo.io)
> notebooks. Expect rough edges.

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
