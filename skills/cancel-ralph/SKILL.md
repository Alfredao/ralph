---
name: cancel-ralph
description: Cancel an active ralph-loop. Removes the loop state file so the Stop hook becomes a no-op on the next session exit. Optional --remove-hook flag also unregisters the hook from .claude/settings.local.json.
---

# Cancel Ralph Loop

Stops an active `ralph-loop` by removing the state file the Stop hook reads.

## Usage

```
/cancel-ralph
```

Or, to also unregister the hook from `.claude/settings.local.json`:

```
/cancel-ralph --remove-hook
```

## What it does

1. Removes `.claude/ralph-loop.local.md` (the loop state file).
2. With `--remove-hook`: removes the Stop hook entry pointing at `stop-hook.sh` from `.claude/settings.local.json`.

The default (no flag) is the lighter option — the hook stays registered but immediately exits 0 when no state file is present, so it costs nothing. Use `--remove-hook` when you're done with Ralph in this project.

## Implementation

This skill runs `cancel.sh`, which handles both removal modes.
