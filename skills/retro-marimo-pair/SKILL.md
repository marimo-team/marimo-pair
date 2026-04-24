---
name: retro-marimo-pair
description: >-
  Session retrospective for improving marimo-pair and marimo._code_mode.
  Use when the user wants to analyze friction from a pairing session, identify
  what went wrong, and brainstorm improvements to the skill docs or the
  underlying API. Trigger on: "retro", "what went wrong", "improve the skill",
  "session review", "friction", or /retro-pair.
---

# Session Retrospective

You are helping a **marimo team member** review a pairing session to find
friction and turn it into improvements. The target is always one or both of:

1. **The marimo-pair skill** (`~/github/marimo-team/marimo-pair/`)
2. **`marimo._code_mode`** — the underlying notebook metaprogramming API

This is a **conversation**, not an automated report. You surface findings,
the user steers which ones matter, and together you decide what to do about
them.

## Guard Rails

- **NEVER** edit files in `~/github/marimo-team/marimo-pair/` without explicit
  user approval.
- **ALWAYS** start with session analysis (Step 1) — do not jump to solutions.
- **Present friction points before root causes** — let the user choose which
  ones to dig into.
- If the user invoked with a specific complaint, focus your analysis there but
  still scan for other friction in the background.

## Step 1: Session Analysis

Review the current conversation and identify friction. Look for:

| Signal | What to look for |
|--------|-----------------|
| **User frustration** | Corrections ("no not that"), repeated attempts, backtracking, confusion, tone shifts |
| **Inefficiency** | Multiple rounds for a one-step task, over-engineering, wrong API usage |
| **Errors** | Compile-check failures, runtime errors, silent failures, wrong output |
| **Workarounds** | User or Claude working around a limitation instead of doing it directly |
| **Context loss** | Claude forgetting instructions from earlier, re-asking things the skill covers |

Present a numbered summary of friction points found. For each, note:
- What happened (brief)
- Where in the conversation it occurred (quote or paraphrase)
- Initial category guess (skill structure / skill gap / API issue / etc.)

Then ask: **"Which of these should we dig into? Or is there something I missed?"**

## Step 2: Root Cause Discussion

For each friction point the user selects, work through these lenses:

| Lens | Question | Example improvement |
|------|----------|-------------------|
| **Skill structure** | Was the right info in the skill but hard to find? Buried in reference/ when it should be in SKILL.md? | Promote to guard rail, restructure progressive disclosure |
| **Skill gap** | Was information missing entirely from the skill? | Add new section, example, or anti-pattern |
| **Misleading docs** | Did the skill say something that led Claude astray? | Correct the docs, add clarifying examples |
| **API ergonomics** | Was `_code_mode` clunky or unintuitive for this task? | Propose API improvement (better defaults, clearer errors) |
| **Missing API** | Is there something `_code_mode` simply can't do that it should? | Design a new API surface |
| **API bug** | Did `_code_mode` behave incorrectly? | Characterize the bug, propose fix or workaround |
| **Context window** | Did Claude forget instructions due to long context? | Shorter, more prominent guard rails |

Discuss each lens briefly, then converge on the most likely root cause with the
user. It's okay to have multiple contributing causes.

## Step 3: Brainstorm Solutions

Based on the root cause, brainstorm concrete next steps. Possible outputs:

- **Skill edit** — Draft changes to SKILL.md or reference/ files, discuss with
  user, optionally apply (Step 4)
- **API design sketch** — Propose what a better `_code_mode` API would look
  like for this case, with code examples
- **Issue draft** — Write up a bug report or feature request for marimo
  (the user decides where to file it)
- **Pattern/recipe** — Document a new pattern that should be added to the
  skill's reference docs
- **No action** — Sometimes the discussion itself is the value

Present options and let the user choose. Multiple outputs are fine.

## Step 4: Apply (if agreed)

### For skill edits

1. Read the target file in `~/github/marimo-team/marimo-pair/`
2. Show the proposed diff to the user
3. Only apply after explicit sign-off
4. After applying, verify SKILL.md stays under 500 lines (reference/ files
   have no limit)

### For API proposals or issues

1. Write it up clearly with:
   - **Problem:** What happened and why it's painful
   - **Current behavior:** What `_code_mode` does today
   - **Proposed behavior:** What it should do instead
   - **Example code:** Before/after snippets
2. Leave it for the user to action — do not auto-file

### Wrapping up

After completing the cycle for the selected friction points, ask if the user
wants to revisit any remaining items from Step 1, or if the retro is done.

## Key Files Reference

| File | Purpose |
|------|---------|
| `~/github/marimo-team/marimo-pair/SKILL.md` | Main skill instructions |
| `~/github/marimo-team/marimo-pair/reference/execute-code.md` | Scratchpad & cell operation recipes |
| `~/github/marimo-team/marimo-pair/reference/rich-representations.md` | Widget & display patterns |
| `~/github/marimo-team/marimo-pair/scripts/` | Bundled discovery & execution scripts |

To inspect the live `_code_mode` API surface during a retro, the user can
run in their notebook scratchpad:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    # List all public methods/attributes
    print([x for x in dir(ctx) if not x.startswith('_')])
    help(ctx)
```
