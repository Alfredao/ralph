---
name: ralph-review-prd
description: AI-powered architectural critique of an entire prd.json before the loop runs. Spawns one Backend Architect agent on the full PRD to flag ordering issues, sizing problems, missing stories, and dependency gaps that would otherwise surface as wasted retries mid-iteration. Complements `/ralph-validate` (which is static/structural) with judgment.
---

# Ralph Review PRD — Architectural Pre-flight

Static validation (`/ralph-validate`) catches structural errors: dangling `depends_on`, missing fields, cycles. It does **not** catch architectural problems — a story that's too big to pass review, an ordering that will force rework, a missing migration step, or two stories that should share a design brief but don't.

This skill is the opinionated second pass: one senior architect reads the entire PRD and tells you what they'd flag in a planning review.

## When to run it

- After `/ralph-prd` (right after PRD generation) — catches planning flaws before any code is written.
- After major PRD edits — if you hand-edited stories or reordered them, re-run.
- Before a long unattended `ralph.sh` run — the review cost (one opus pass) is a fraction of what a bad plan will cost in retries.

Not useful mid-loop — by then, stories are landing and the critique is stale.

## Usage

```
/ralph-review-prd
/ralph-review-prd path/to/prd.json
```

## What the skill does

1. Reads the target `prd.json` (default `./prd.json`) end-to-end.
2. Spawns a single Agent with:
   - `subagent_type: "Backend Architect"`
   - `model: "opus"`
   - Prompt: the full PRD contents, acceptance criteria, team config, dependencies — plus the critique rubric below.
3. The agent writes its findings to `prd-review.md` in the working directory and also prints a one-screen summary.
4. You read the review and decide whether to edit `prd.json` before starting the loop.

**The skill does NOT modify `prd.json`.** Review-only. Any PRD edits are your call.

## Critique rubric (given to the agent)

```
You are doing an architectural pre-flight review of a prd.json that a Ralph
autonomous loop is about to execute. Your job is to catch planning problems
that would surface as wasted retries, blocker files, or incoherent output.

Read the entire PRD below, then write your findings to `prd-review.md` using
this shape:

## Overall assessment
ONE sentence: is this PRD ready to run, needs light edits, or needs a rethink?

## Story sizing
- Stories that look too big to land in one session (multiple files, multiple
  concerns, multiple layers). Name them. Propose splits.
- Stories that look trivially small and could be merged with a neighbor.

## Ordering & dependencies
- `depends_on` arrays that are missing an obvious prerequisite.
- Priority numbers that imply an order the dependencies contradict.
- Stories that should share a design phase (e.g., multiple UI components that
  need a common visual vocabulary) but currently design in isolation.

## Missing stories
- Work that's implicit in the acceptance criteria but not a story yet
  (migrations, seed data, feature flags, rollback paths, observability).
- Stories the PRD assumes but hasn't captured.

## Architectural risks
- Story combinations that will produce brittle integration (e.g., backend
  contract designed in US-003, frontend consumes it in US-008, but nothing
  between them catches drift).
- Places where the team composition looks wrong for the work (e.g., a story
  labeled `backend` that's really a design-heavy cross-cutting change).

## Readiness verdict
- READY — run the loop as-is.
- LIGHT EDITS — small tweaks recommended; the list of specific changes.
- RETHINK — the plan needs restructuring before the loop will produce good
  output. Explain why.

Be blunt, specific, and short. Every finding must reference a story id.
Do not suggest speculative features. Do not rewrite the PRD for the user;
flag what's wrong and let them decide.
```

## Output summary (printed to user)

After the agent finishes, print:

```
PRD review: [READY | LIGHT EDITS | RETHINK]
Findings written to prd-review.md ([N] items)

Top items:
  1. [first finding, one line]
  2. [second finding]
  3. [third finding]
```

## Cost

One opus pass over the PRD. For a 15-story PRD that's typically a few cents of tokens — cheap compared to the cost of a bad 15-story run (one or two avoided retry cycles pays for it).

## Non-goals

- Not a substitute for `/ralph-validate`. Run the static validator first; it's free and deterministic.
- Not a refactor tool. Findings are advisory.
- Not per-story review. That's what Phase 3 in `ralph-worker` does, per story, after implementation. This is whole-PRD, before any implementation.
