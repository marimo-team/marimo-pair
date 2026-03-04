# marimo-pair

> [!WARNING]
> This is an early-stage, experimental skill for use with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Expect rough edges — feedback and contributions welcome.

A [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) for pair programming in [marimo](https://marimo.io) notebooks via MCP.

## What it does

When you're working in a marimo notebook, this skill gives Claude Code a structured protocol for collaborating with you — creating cells, investigating data, building visualizations, and showing its work in the notebook as it goes.

Key behaviors:
- **Visible collaboration** — Claude shows up in the notebook with a working cell before doing any investigation
- **Turn-based** — one step at a time, waiting for your input before proceeding
- **Auto-formatting** — all code is formatted with ruff before being pushed to cells
- **Guardrails** — never deletes your cells, restarts kernels, or installs packages without asking

## Prerequisites

- A running [marimo](https://marimo.io) notebook
- The marimo MCP server connected to Claude Code (provides `get_active_notebooks` and `execute_code` tools)

## Install

Clone into your Claude Code skills directory:

```bash
# Personal (available across all projects)
git clone https://github.com/marimo-team/marimo-pair ~/.claude/skills/marimo-pair

# Or project-level (this project only)
git clone https://github.com/marimo-team/marimo-pair .claude/skills/marimo-pair
```

Claude Code automatically discovers skills from these directories — no further configuration needed.

## Quick start

```bash
# Add the marimo MCP server to Claude Code
claude mcp add --transport http marimo "http://localhost:2718/mcp/server"

# Start marimo in headless code-mode with MCP enabled
uvx --with="marimo[mcp,recommended]" \
  marimo edit notebook.py \
  --mcp="code-mode" \
  --no-token \
  --headless \
  --port 2718
```

## Usage

Start a marimo notebook, then talk to Claude Code. The skill activates automatically when it detects an active marimo session.

```
> let's explore this dataframe
> make a scatter plot of height vs weight
> add a dropdown to filter by sport
```

## Files

- `SKILL.md` — The collaboration protocol (philosophy, turn-based workflow, guardrails)
- `REFERENCE.md` — Tiered API recipes for interacting with the marimo kernel
