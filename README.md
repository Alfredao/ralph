# Ralph for Claude Code

Autonomous multi-agent system that turns a feature description into a structured PRD, then implements it story by story with specialized agent teams. Port of [snarktank/ralph](https://github.com/snarktank/ralph) from AMP to Claude Code.

## How It Works

1. You describe a feature
2. Ralph asks interactive clarifying questions (rendered as selectable cards in the CLI)
3. Generates a structured PRD with right-sized user stories
4. Converts it to `prd.json` with team assignments and dependency ordering
5. Spawns specialized agent teams per story type (designers, developers, reviewers)
6. Implements stories iteratively until all pass

Memory persists through files, not conversation context:
- `prd.json` — Story tracking, team config, and completion status
- `progress.txt` — Learnings accumulated across iterations
- `design-brief-US-XXX-<role>.md` — Temporary design phase output, one file per design agent (e.g. `-ux-researcher.md`, `-ui-designer.md`). Cleaned up after approval.
- `review-US-XXX.md` — Temporary review phase output (cleaned up after approval)
- `retry-diff-US-XXX.md` — Temporary snapshot of a rejected implementation attempt, passed to the retry agent alongside the review feedback (cleaned up after approval)
- `.ralph-commit-US-XXX` — Commit SHA of the story's implementation, handed to the reviewer so it can use `git show` instead of the fragile `git diff HEAD~1` (cleaned up after approval)
- `.ralph-blocker.md` — Written when a story hits the retry cap (3 failed attempts). Contains the review verdict, the rejected diff, and instructions for unblocking. The loop refuses to iterate while this file exists; auto-cleaned when the referenced story is marked `passes: true`.
- `archive/progress-<timestamp>.txt` — Older iteration logs. The worker auto-archives `progress.txt` when it exceeds 50 KB and keeps only the Codebase Patterns header plus the last 20 KB of iteration log. Archives are committed alongside the story so history is preserved in git.
- `.claude/ralph-loop.local.md` — Loop state (only while `/ralph-loop` is active)
- Git commit history

Each iteration starts with clean context, forcing proper documentation.

## Installation

Copy the skills and the bundled subagents into your Claude Code config:

```bash
# Skills (ralph-prd, ralph-agent, ralph-worker, ralph-loop, ralph-validate, ralph-convert, cancel-ralph)
cp -r skills/* ~/.claude/skills/

# Subagents Ralph spawns (Senior Developer, Backend Architect, UX Researcher, etc.)
# The -n flag prevents overwriting agents you already have installed.
mkdir -p ~/.claude/agents
cp -rn .claude/agents/* ~/.claude/agents/
```

The agents are a verbatim subset of [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) (MIT). See `.claude/agents/README.md` for the full list and refresh instructions.

### Prerequisites

- `jq` — required by `ralph-agent`'s bash loop and by the `/ralph-loop` Stop hook
- `perl` — required by the `/ralph-loop` Stop hook (used to extract `<promise>` tags from the transcript)
- `claude` CLI on `PATH` — required by `ralph-agent/ralph.sh`

On macOS: `brew install jq` (perl ships with the OS).

## Usage

### 1. Generate PRD + prd.json (single command)

```
/ralph-prd
```

This runs the full pipeline:
1. Asks interactive clarifying questions via selectable option cards
2. Generates a markdown PRD saved to `tasks/prd-[feature].md`
3. Converts it to `prd.json` with team assignments and dependency ordering

No need to run `/ralph-convert` separately (it still exists for re-converting manually edited PRDs).

### 2. Run the Agent Loop

Pick one of three execution modes depending on PRD size and how much context drift you want to tolerate.

**Option A: Bash loop (true process isolation)**

```bash
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]
```

Spawns completely fresh Claude CLI sessions per iteration. Best for long-running implementations where context buildup matters.

**Option B: In-session subagents (single turn orchestration)**

```
/ralph-agent
```

Orchestrates within your current session using subagents. Convenient for smaller PRDs.

**Option C: Stop-hook loop (in-session, fresh prompt boundary per story)**

```
/ralph-loop
/ralph-loop --max-iterations 30
```

Activates a project-local Stop hook that reads `prd.json`, picks the next incomplete story, and re-prompts you to handle it via `ralph-worker`. Each story gets a fresh user-message boundary inside the same session — no CLI spawn cost, but less context buildup than Option B.

To stop early:

```
/cancel-ralph
/cancel-ralph --remove-hook   # also unregister the hook from .claude/settings.local.json
```

The loop ends naturally when every story has `passes: true` or `--max-iterations` is hit. The hook re-checks `prd.json` on every Stop event, so a falsely asserted `<promise>RALPH-COMPLETE</promise>` is rejected if any story is still incomplete.

| Option | Process model | Spawn cost | Context drift | Live visibility |
|--------|--------------|-----------|---------------|-----------------|
| A — bash loop | New CLI per iteration | High | Lowest | Terminal only |
| B — `/ralph-agent` | One turn, subagents | None | Highest | Full |
| C — `/ralph-loop` | Same session, hook re-prompts | None | Medium | Full |

### 3. Run a Single Story (optional)

```
/ralph-worker
```

Picks the highest-priority incomplete story and acts as team lead — spawning the right agents for design, implementation, and review.

## Multi-Agent Teams

Each story gets the right team based on its `type` field. The orchestrator spawns specialized agents per phase:

```
Orchestrator picks US-003 (type: "frontend")
  |
  +-- Phase 1: DESIGN (parallel agents, one file per agent)
  |   +-- UX Researcher -> design-brief-US-003-ux-researcher.md
  |   +-- UI Designer   -> design-brief-US-003-ui-designer.md
  |
  +-- Phase 2: IMPLEMENT (sequential)
  |   +-- Senior Developer -> implements using design brief
  |   +-- Output: code changes committed
  |
  +-- Phase 3: REVIEW
      +-- Code Reviewer -> verifies against criteria + design brief
      +-- Output: APPROVED or NEEDS_CHANGES (max 2 retry cycles)
```

### Stop-Hook Loop Flow (`/ralph-loop`)

```
You run /ralph-loop
  |
  v
Setup: write .claude/ralph-loop.local.md + register hook in settings.local.json
  |
  v
+------------------------------------------+
|  You finish your turn                    |
|  v                                       |
|  Claude Code fires Stop hook             |
|  v                                       |
|  Hook reads prd.json, finds next story   |
|     where passes: false                  |
|  |                                       |
|  +- All stories pass? -- yes --> exit, cleanup
|  |                                       |
|  +- Iteration >= max?  -- yes --> exit, cleanup
|  |                                       |
|  +- <promise>RALPH-COMPLETE</promise>    |
|  |   AND prd.json confirms? -- yes --> exit, cleanup
|  |                                       |
|  v no                                    |
|  Hook emits {"decision":"block",         |
|              "reason":"<story prompt>"}  |
|  |                                       |
|  v                                       |
|  Claude receives prompt, spawns the team |
|  for that story via ralph-worker         |
|  (UX Researcher, UI Designer, Senior Dev,|
|   Code Reviewer ...)                     |
|  |                                       |
|  v                                       |
|  Story passes review -> passes: true     |
|  committed to prd.json                   |
+------------------------------------------+
   ^                                     |
   +-------- next Stop event ------------+
```

The hook re-queries `prd.json` every iteration, so a falsely asserted `<promise>RALPH-COMPLETE</promise>` is rejected if any story is still incomplete — Claude can't lie its way out of the loop.

### Team Assignment by Story Type

| Type | Design Phase | Implement Phase | Review Phase |
|------|-------------|-----------------|--------------|
| `backend` | _skipped_ | Senior Developer | Code Reviewer |
| `frontend` | UX Researcher + UI Designer | Senior Developer | Code Reviewer |
| `fullstack` | UX Researcher | Backend Architect + Frontend Developer | Code Reviewer |
| `infra` | _skipped_ | DevOps Automator + Senior Developer | Code Reviewer |
| `data` | _skipped_ | Backend Architect | API Tester + Code Reviewer |

## Skills Reference

| Skill | Command | Purpose |
|-------|---------|---------|
| **ralph-prd** | `/ralph-prd` | Interactive PRD generation + prd.json conversion (single command) |
| **ralph-convert** | `/ralph-convert` | Standalone PRD-to-JSON converter (for re-converting edited PRDs) |
| **ralph-agent** | `/ralph-agent` | Multi-story orchestrator (bash loop or in-session subagents) |
| **ralph-loop** | `/ralph-loop` | Stop-hook driven loop — re-prompts you per incomplete story until prd.json fully passes |
| **cancel-ralph** | `/cancel-ralph` | Stop an active ralph-loop (use `--remove-hook` to also unregister the hook) |
| **ralph-worker** | `/ralph-worker` | Single-story team lead (spawns design/implement/review agents) |
| **ralph-validate** | `/ralph-validate` | Static linter for prd.json (structure, required fields, depends_on cycles) |
| **ralph-review-prd** | `/ralph-review-prd` | AI architectural pre-flight on the whole PRD — sizing, ordering, missing stories, risks |
| **ralph-status** | `/ralph-status` | Read-only status snapshot (counts, next runnable, blockers, loop state) |

## Model Selection

Ralph uses different models per phase to balance quality and cost:

| Phase | Default Model | Rationale |
|-------|--------------|-----------|
| Design | Opus | Reasoning-heavy: UX analysis, architecture decisions |
| Implement | Sonnet | Code generation: fast and cost-effective |
| Review | Opus | Reasoning-heavy: evaluating correctness against criteria |

These defaults are set automatically when generating prd.json via `/ralph-prd` or `/ralph-convert`. You can override them per-story by editing the `models` field in prd.json:

```json
"models": {
  "design": "opus",
  "implement": "sonnet",
  "review": "opus"
}
```

Valid values: `"opus"`, `"sonnet"`, `"haiku"`. Old prd.json files without `models` fall back to the defaults above.

**PRD generation tip:** Since `/ralph-prd` runs in your current session (no subagents), use `/model opus` before running it for the best PRD quality.

## prd.json Format

```json
{
  "name": "Feature Name",
  "branch": "feature/feature-name",
  "stories": [
    {
      "id": "US-001",
      "title": "Add status column to tasks table",
      "description": "As a developer, I want a status column so that tasks can track their state.",
      "priority": 1,
      "depends_on": [],
      "type": "backend",
      "team": {
        "design": [],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "models": {
        "design": "opus",
        "implement": "sonnet",
        "review": "opus"
      },
      "acceptance_criteria": [
        "Add status column with default 'pending'",
        "Valid values: pending, in_progress, completed",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "passes": false,
      "notes": ""
    }
  ]
}
```

## File Structure

```
project/
├── prd.json                  # Story tracking with type + team fields
├── progress.txt              # Learnings log (carried across iterations)
├── tasks/
│   └── prd-[feature].md      # Human-readable PRD
├── design-brief-US-XXX-*.md  # Temporary: one file per design agent
├── review-US-XXX.md          # Temporary: review phase output
├── retry-diff-US-XXX.md      # Temporary: rejected-attempt snapshot (retries only)
├── .ralph-blocker.md         # Written on retry cap; halts the loop until resolved
├── archive/                  # Previous prd.json files
├── .claude/
│   ├── ralph-loop.local.md   # Loop state (only while /ralph-loop is active)
│   └── settings.local.json   # Stop hook registration (added by /ralph-loop)
└── AGENTS.md                 # Module-specific patterns (optional)
```

## Key Principles

1. **Right team for the right story** — A backend migration doesn't need UX research. A complex UI component shouldn't be built without design thinking.
2. **Right-sized stories** — Each story completable in one focused session. Split anything that touches more than 2-3 files.
3. **Dependency ordering** — Use `priority` (integer) as a hint and `depends_on: ["US-XXX"]` for hard prerequisites. The loop will not pick a story until every id in `depends_on` has `passes: true`. Typical flow: database → APIs → UI → integrations.
4. **Verifiable criteria** — No vague language. "Returns 404 when not found", not "handles errors properly".
5. **Fresh context** — Each iteration starts clean, relies on files for state.
6. **Document learnings** — `progress.txt` carries knowledge forward across iterations.

## Error Handling

- **Design agent fails** — Skip design phase, proceed to implement without brief
- **Implementation fails** — Retry with additional context (max 2 retries), then stop and write a blocker
- **Review rejects** — Re-implement with review feedback (max 2 cycles, model escalates to `opus` on the last one), then stop and write a blocker
- **Stuck in loop** — After 3 failed attempts on the same story, the worker writes `.ralph-blocker.md` and all loop entry points refuse to iterate until it's resolved

## Blockers

When a story's review cycle fails 3 times (initial + 2 retries), the worker writes `.ralph-blocker.md` instead of marking it passed. The file contains the full review verdict, the last rejected diff, and explicit unblock options:

1. **Rewrite the story** — clarify acceptance criteria in `prd.json`, delete the blocker, re-run.
2. **Split the story** — break it into smaller stories with `depends_on`, run `/ralph-validate`, delete the blocker, re-run.
3. **Fix manually** — implement it yourself, mark `passes: true` in `prd.json`, and commit. The loop auto-cleans the blocker on the next run.
4. **Skip** — mark `passes: true` without implementing, delete the blocker, re-run.

All three loop modes (`ralph.sh`, `/ralph-agent`, `/ralph-loop`) check for this file at startup and refuse to keep iterating while it's unresolved — no more accidentally re-running the same failing story and burning tokens on it.

## Credits

Based on [snarktank/ralph](https://github.com/snarktank/ralph) for AMP. The `/ralph-loop` Stop-hook mechanism is inspired by Anthropic's [`ralph-wiggum` plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum).
