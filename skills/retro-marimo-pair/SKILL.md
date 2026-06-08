---
name: retro-marimo-pair
description: >-
  Session retrospective for improving marimo-pair and marimo._code_mode.
  Use when the user wants to analyze friction from a pairing session, identify
  what went wrong, and brainstorm improvements to the skill docs or the
  underlying API. Trigger on: "retro", "what went wrong", "improve the skill",
  "session review", "friction", or /retro-marimo-pair.
---

# Session Retrospective

You are helping a **marimo team member** review a pairing session to find
friction and turn it into improvements. The target is always one or both of:

1. **The marimo-pair skill** (`github://marimo-team/marimo-pair`)
2. **`marimo._code_mode`** — the underlying notebook metaprogramming API

This is a **conversation**, not an automated report. You surface findings,
the user steers which ones matter, and together you decide what to do about
them.

## Guard Rails

- **NEVER** edit files in `github://marimo-team/marimo-pair` without explicit
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

## Step 3: Diagnose & Capture

The goal of a retro is **diagnosis**, not a contribution. Based on the root
cause, write up a clear diagnosis the team can act on — don't jump to proposing
or authoring a fix.

For each friction point, produce:

- **Diagnosis** — What went wrong and why it was frustrating, in plain terms
- **Contributing factors** — Skill structure, gap, misleading docs, API
  ergonomics, missing API, API bug, context window (from Step 2)
- **Considerations** — Trade-offs, open questions, or things that would need to
  be true for a fix to make sense. Note possible directions here, but frame
  them as considerations rather than committed solutions.

The default next step is to **capture the diagnosis as an issue or discussion**
so the team can weigh it — not to immediately make a contribution. Concrete
code changes (skill edits, API designs) come *after* an issue/discussion
exists and the user explicitly chooses to go further.

Present the diagnosis and ask: **"Want me to draft this as an issue or
discussion?"**

## Step 4: File or Follow Up

### Default: file an issue / discussion

Write it up clearly for the marimo team to triage:

- **Problem:** What happened and why it's painful
- **Current behavior:** What the skill or `_code_mode` does today
- **Considerations:** Trade-offs and open questions (not a committed solution)
- **Example:** A minimal snippet or quote from the session, if helpful

Leave the actual filing to the user — do not auto-file. This is the preferred
outcome: surface friction for the team rather than ship a fix from the retro.

### Only if the user explicitly wants to go further

A skill edit or API change should follow an issue/discussion, not replace it.
If — and only if — the user explicitly asks to draft a change now:

1. Read the target file in `github://marimo-team/marimo-pair`
2. Show the proposed diff to the user
3. Only apply after explicit sign-off
4. After applying, verify SKILL.md stays under 500 lines (reference/ files
   have no limit)

### Wrapping up

After completing the cycle for the selected friction points, ask if the user
wants to revisit any remaining items from Step 1, or if the retro is done.

## Key Files Reference

| File | Purpose |
|------|---------|
| `github://marimo-team/marimo-pair/SKILL.md` | Main skill instructions |
| `github://marimo-team/marimo-pair/reference/execute-code.md` | Scratchpad & cell operation recipes |
| `github://marimo-team/marimo-pair/reference/rich-representations.md` | Widget & display patterns |
| `github://marimo-team/marimo-pair/scripts/` | Bundled discovery & execution scripts |

To inspect the live `_code_mode` API surface during a retro, the user can
run in their notebook scratchpad:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    # List all public methods/attributes
    print([x for x in dir(ctx) if not x.startswith('_')])
    help(ctx)
```
