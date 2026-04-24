---
name: ralph-status
description: Read-only snapshot of the current project's Ralph state. Shows story completion, the next runnable story, dependency blocks, active blockers, and /ralph-loop state. Runs in a fraction of a second; safe to invoke at any time — it touches nothing.
---

# Ralph Status

One-shot read of `prd.json`, `.ralph-blocker.md`, and the `/ralph-loop` state file. Answers "where am I?" in ~100ms without running the loop or spawning agents.

## Usage

```
/ralph-status
/ralph-status path/to/prd.json
```

Invokes `skills/ralph-status/status.sh`. Exits 0 if `prd.json` is readable, 1 otherwise. Produces no side effects.

## What it shows

- **PRD name and branch** — the feature this PRD owns
- **Story counts** — passing / total / incomplete
- **Next runnable story** — highest-priority incomplete story with all `depends_on` satisfied
- **Blocked by dependencies** — stories waiting on prerequisites (with the ids they're waiting for)
- **Active blocker** — if `.ralph-blocker.md` exists, which story, when it was blocked, and where to read the verdict
- **Loop state** — if `/ralph-loop` is active, current iteration and max

## Example output

```
Ralph Status — Task Status (feature/task-status)
────────────────────────────────────────────────────────────

Stories: 1 passing / 4 total (3 incomplete)
Next runnable: US-002 — Return status in API (backend)

Blocked by dependencies:
  US-004 — Status filter (waiting on: US-002, US-003)

⛔ Blocker active: US-002 (since 2026-04-23T22:45:00Z)
   Read .ralph-blocker.md for the review verdict and unblock options.

/ralph-loop active: iteration 7 / 20 (started 2026-04-23T20:00:00Z)
```

## Requirements

- `jq` on PATH
- `prd.json` in the working directory (or passed as the first argument)
