# Personas

A **persona** is a small companion skill that layers a *role* on top of
`marimo-pair`. The core skill teaches Claude how to work inside a running
marimo kernel (discover servers, execute code, use `code_mode`, respect guard
rails). A persona adds the *what* — the goal, workflow, cell conventions, and
library defaults that fit a specific way of using the notebook.

Users invoke a persona with a slash command, e.g. `/persona-eda`, at the start
of a session: "let's pair on this notebook with /persona-eda".

## Personas shipped in this repo

- [`persona-eda`](./eda/SKILL.md) — exploratory data analysis.
- [`persona-app-builder`](./app-builder/SKILL.md) — turn a notebook into a
  small, interactive app.

More personas (ml-experiment, …) are planned. Third parties are welcome to
publish their own.

## What a persona is — and isn't

A persona **is**:
- A role description — who Claude is playing this session.
- A workflow loop — the steps Claude follows without being re-prompted.
- A set of conventions — preferred libraries, cell patterns, hand-back points.

A persona **is not**:
- A replacement for `marimo-pair`. It always layers on top.
- A place to re-document `code_mode`, server discovery, or reactivity gotchas.
  Link to `../../SKILL.md` and `../../reference/` instead.
- A dumping ground for preferences that apply to every role — those belong in
  the core skill.

Keeping personas thin means the core skill can evolve without having to update
every persona in lockstep.

## Naming

- Skill `name:` field is `persona-<slug>`, kebab-case.
- Slash invocation is `/persona-<slug>` and must appear verbatim in the
  skill's `description` so the matcher picks it up.
- The slug should name the *role*, not the library (`persona-eda`, not
  `persona-polars`).

## Template

Copy this into `personas/<slug>/SKILL.md` and fill it in. Sections are fixed;
content varies.

```markdown
---
name: persona-<slug>
description: >-
  <One sentence: what role Claude plays and when to activate.>
  Invoke explicitly with /persona-<slug>. Layers on top of the marimo-pair
  skill — assumes the user has a running marimo notebook.
---

# Persona: <Human-Readable Name>

> Layers on top of `marimo-pair`. See `../../SKILL.md` for notebook mechanics
> (server discovery, `code_mode`, guard rails). This file only defines the
> *role* — the goals, loop, and conventions.

## Role
Who Claude is playing. Tone. What the user is trying to get out of this
session. One short paragraph.

## Workflow
The loop for this role, as numbered steps. Each step should name a concrete
action in the notebook (usually a cell or small group of cells).

## Cell patterns
Conventions specific to this role: what goes in `setup`, how cells are
grouped, what a typical cell looks like. Keep to 3–6 bullets.

## Defaults
Preferred libraries and rich outputs for this role. One line each; prefix
with "prefer" or "avoid".

## When to hand back to the user
Checkpoints where Claude pauses for human judgment.

## Anti-patterns
Short list of things *not* to do in this role. Tie each to a reason.
```

## Registering your persona

### Inside this repo

Add the directory to the `skills` array in
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json):

```json
"skills": [
  "./",
  "./personas/eda",
  "./personas/app-builder",
  "./personas/your-slug"
]
```

### As a standalone plugin

Personas can also ship as their own plugin — useful if you want to publish
a persona from a different repo. Your plugin's `marketplace.json` just needs
to list one skill (the persona directory), and users install it alongside
`marimo-pair`. The slash invocation still works: Claude Code exposes every
installed skill whose name matches `persona-*`.

## Composition

One persona per session. If the user wants to switch roles, they invoke a
different persona; it replaces the active one. Stacking personas is not
supported — conflicting conventions would make behavior hard to predict.
