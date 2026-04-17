---
name: ralph-loop
description: Stop-hook driven Ralph loop. Activates a session-level Stop hook that reads prd.json, picks the next incomplete story, and re-prompts the assistant to implement it via the ralph-worker skill. Loop ends when all stories pass or --max-iterations is hit.
---

# Ralph Loop - Stop-Hook Driven Story Iterator

Third execution mode for Ralph. Combines the persistence of `ralph-wiggum`'s Stop hook with this project's `prd.json` story decomposition and multi-agent teams.

## When to use this vs the other modes

| Mode | How it runs | Best for |
|------|-------------|----------|
| `~/.claude/skills/ralph-agent/ralph.sh` | External bash loop, fresh CLI per iteration | Long PRDs where context drift is the main risk |
| `/ralph-agent` | In-session orchestration, all in one turn | Small PRDs you want to watch live |
| `/ralph-loop` | In-session Stop hook, fresh user-message boundary per story | Mid-sized PRDs — live visibility AND reduced context buildup, no CLI spawn cost |

## How it works

1. `/ralph-loop` runs `setup-ralph-loop.sh`, which:
   - Validates `prd.json` exists
   - Writes `.claude/ralph-loop.local.md` (YAML state file)
   - Registers `stop-hook.sh` in `.claude/settings.local.json`
2. You finish your turn. Claude Code fires the Stop hook.
3. The hook reads `prd.json`, finds the next story where `passes: false`, builds a story-specific prompt that says "use the ralph-worker skill on this story", and emits `{"decision": "block", "reason": "<prompt>"}`.
4. Claude receives the new prompt as if the user sent it. Spawns the team for that story per `ralph-worker`.
5. Story completes → `passes: true` → next Stop event → hook picks the next story.
6. Loop ends when:
   - All stories have `passes: true` (hook exits cleanly)
   - `--max-iterations` is hit (hook exits cleanly with warning)
   - Assistant outputs `<promise>RALPH-COMPLETE</promise>` AND `prd.json` confirms all pass

## Usage

```
/ralph-loop
/ralph-loop --max-iterations 30
/ralph-loop --prd-file ./tasks/feature-x/prd.json --max-iterations 50
```

After running, just keep working normally. When you try to end the turn the hook takes over and re-prompts you.

## Stopping the loop

```
/cancel-ralph
```

Removes the state file. The hook becomes a no-op (it bails immediately if the state file doesn't exist) but stays registered in `.claude/settings.local.json` until you remove it manually or run `/cancel-ralph --remove-hook`.

## State file format

`.claude/ralph-loop.local.md`:

```markdown
---
active: true
iteration: 3
max_iterations: 20
prd_file: "prd.json"
started_at: "2026-04-16T12:34:56Z"
---

Free-form notes (ignored by the hook).
```

The hook updates `iteration` atomically each time it fires.

## Hook behaviour summary

The hook (`stop-hook.sh`) on every Stop event:

1. No state file → exit 0 (allow normal exit).
2. State file corrupted → delete it, exit 0.
3. `iteration >= max_iterations` (when max > 0) → cleanup, exit 0.
4. `prd.json` missing → cleanup, warn, exit 0.
5. Last assistant message contains `<promise>RALPH-COMPLETE</promise>` AND `prd.json` confirms all stories pass → cleanup, exit 0.
6. Find next story with `passes: false` (sorted by `priority`):
   - None → cleanup, exit 0.
   - Found → build worker prompt, increment iteration, emit `{"decision": "block", "reason": "<prompt>"}`.

## Anti-lying guard

The injected prompt explicitly tells Claude:

> Do NOT output `<promise>RALPH-COMPLETE</promise>` unless every story genuinely passes. The hook re-checks `prd.json` and will reject false promises.

The hook enforces this — even if Claude emits the promise, the hook re-counts incomplete stories. If any remain, the loop continues.

## Requirements

- `jq` and `perl` on PATH
- `prd.json` exists in the working directory (run `/ralph-prd` first)

## Files installed

- `stop-hook.sh` — the Stop hook script
- `setup-ralph-loop.sh` — invoked by `/ralph-loop`
- This skill markdown — invoked by `/ralph-loop`
