---
name: ralph-agent
description: Autonomous coding agent that implements user stories from prd.json iteratively. Spawns specialized agent teams (designers, developers, reviewers) per story type. Works through stories one by one until all pass.
---

# Ralph Agent - Autonomous Story Orchestrator

Loops through incomplete stories in `prd.json` and delegates each one to the `ralph-worker` skill. The worker owns all team-spawning, phase sequencing, review retries, and commit discipline. This skill is only the outer loop.

## Two Ways to Run

| Mode | Command | Best for |
|------|---------|----------|
| Bash loop | `~/.claude/skills/ralph-agent/ralph.sh [max_iterations]` | Long PRDs where context drift matters — each iteration is a fresh Claude CLI session |
| In-session | `/ralph-agent` | Small/mid PRDs you want to watch live in the current session |

For the stop-hook variant that re-prompts at each turn boundary, use `/ralph-loop` instead.

All three modes invoke `ralph-worker` for per-story work. Worker logic lives in one place.

## Orchestrator Workflow

### Step 1 — Verify state

- If `prd.json` doesn't exist → stop, tell user to run `/ralph-prd` first.
- If `progress.txt` doesn't exist → create a minimal scaffold (headers only).
- Note the target branch from `prd.json.branch`. Checkout if not already on it.

### Step 2 — Loop until done

Repeat until all stories have `passes: true` (or a blocker is hit):

1. Read `prd.json`. If every story passes → report completion and exit.
2. Invoke the `ralph-worker` skill.
   - The worker self-selects the highest-priority incomplete story.
   - It reads `type`, `team`, and `models` fields.
   - It runs design → implement → review phases with the right specialists.
   - It handles review retries (max 2).
   - It updates `progress.txt` + `prd.json` and creates ONE commit.
3. After the worker returns, re-read `prd.json`:
   - If the worker's story is now `passes: true` → continue loop.
   - If it's still `passes: false` after 2 review cycles → stop and report the blocker.

### Step 3 — Report completion

When all stories pass:

```
All stories complete!
- US-001: <title> ✓
- US-002: <title> ✓
...
Branch: feature/<name>
```

## What this skill does NOT do

- Does NOT spawn design/implement/review agents directly. That's `ralph-worker`.
- Does NOT write prompts for specialists. That's `ralph-worker`.
- Does NOT enforce commit rules. That's `ralph-worker`.
- Does NOT pick which specialists a story needs. That's `ralph-worker` reading `story.team`.

If you find yourself writing prompt templates here, stop. Add them to `ralph-worker` instead.

## Story schema (reference)

The worker expects each story to carry:

```json
{
  "id": "US-003",
  "title": "...",
  "priority": 3,
  "depends_on": ["US-001", "US-002"],
  "passes": false,
  "type": "frontend",
  "team": {
    "design": ["UX Researcher", "UI Designer"],
    "implement": ["Senior Developer"],
    "review": ["Code Reviewer"]
  },
  "models": {
    "design": "opus",
    "implement": "sonnet",
    "review": "opus"
  }
}
```

- Missing `type` / `team` / `models` → worker applies backend defaults. See `ralph-worker` for the exact mapping table and defaults.
- Missing `depends_on` → treated as `[]` (no prerequisites).
- A story is **runnable** only when every id in its `depends_on` has `passes: true`. The orchestrator filters on this; stories with unmet deps are skipped until their prerequisites finish. If incomplete stories remain but none are runnable, the loop stops with a dependency-deadlock error.

## Error handling

- **Worker reports blocker** → stop the loop, surface the blocker to the user.
- **Same story fails twice in a row** → stop, don't keep retrying the outer loop.
- **prd.json corrupted mid-run** → stop, don't attempt to self-repair.

## File layout

```
project/
├── prd.json                  # Story tracking (source of truth)
├── progress.txt              # Learnings log (worker writes)
├── design-brief-US-XXX-*.md  # Temporary: cleaned up by worker
├── review-US-XXX.md          # Temporary: cleaned up by worker
├── archive/                  # Previous prd.json files
└── AGENTS.md                 # Module patterns (optional)
```

## Example session

```
User: /ralph-agent

Orchestrator: 3 stories, 0 complete. Starting loop.

  [iter 1] Invoking ralph-worker → US-001 (backend)
           → APPROVED. US-001 complete.

  [iter 2] Invoking ralph-worker → US-002 (frontend)
           → NEEDS_CHANGES → retry 1 → APPROVED. US-002 complete.

  [iter 3] Invoking ralph-worker → US-003 (fullstack)
           → APPROVED. US-003 complete.

All stories complete!
Branch: feature/task-status
```

## Key principle

**One orchestrator, one worker, one team model.** The orchestrator never duplicates worker logic. If behavior needs to change for all three execution modes, change `ralph-worker`.
