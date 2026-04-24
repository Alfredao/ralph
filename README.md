# Ralph for Claude Code

Autonomous multi-agent system that turns a feature description into a structured PRD, then implements it story by story with specialized agent teams. Designed for Claude Code; port of [snarktank/ralph](https://github.com/snarktank/ralph) (originally for AMP) with team-based implementation, dependency enforcement, and stop-hook-driven persistence added.

## Table of contents

- [How it works](#how-it-works)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Skills reference](#skills-reference)
- [Execution modes](#execution-modes)
- [prd.json schema](#prdjson-schema)
- [Runtime files](#runtime-files)
- [Commit discipline](#commit-discipline)
- [Bundled subagents](#bundled-subagents)
- [Typical workflows](#typical-workflows)
- [Troubleshooting](#troubleshooting)
- [Credits and license](#credits-and-license)

## How it works

```
┌─ /ralph-prd ──────────┐     ┌─ /ralph-validate ──┐     ┌─ /ralph-review-prd ┐
│ interactive questions │  →  │ structural linter  │  →  │ opus architect     │
│ generates PRD +       │     │ (no tokens)        │     │ (one-pass critique)│
│ prd.json + branch     │     └────────────────────┘     └────────────────────┘
└───────────────────────┘                                           │
                                                                    ▼
                                              ┌─ pick a loop mode ───────────┐
                                              │   ralph.sh (unattended)      │
                                              │   /ralph-agent (in-session)  │
                                              │   /ralph-loop (stop hook)    │
                                              └──────────────┬───────────────┘
                                                             ▼
                                             ┌─ per-story ralph-worker ──────┐
                                             │  design (parallel agents)     │
                                             │  implement (team per type)    │
                                             │  review (regression + design) │
                                             │  ↳ retry up to 2x, opus on #2 │
                                             │  ↳ blocker file on failure    │
                                             └──────────────┬────────────────┘
                                                            ▼
                                                     all stories pass
                                                            ▼
                                              ┌─ gh pr create suggestion ────┐
                                              └──────────────────────────────┘
```

Each iteration starts with **clean context**. State lives in files (`prd.json`, `progress.txt`, design briefs, review files, blocker files, metrics), not in the conversation — so a bash loop can run overnight and a stop-hook loop survives pauses.

## Installation

Two copy steps: the skills, and the bundled subagents.

```bash
# Clone
git clone https://github.com/Alfredao/ralph.git ~/ralph
cd ~/ralph

# Skills → ~/.claude/skills/
cp -r skills/* ~/.claude/skills/

# Bundled subagents → ~/.claude/agents/
# -n prevents overwriting agents you already have installed
mkdir -p ~/.claude/agents
cp -rn .claude/agents/* ~/.claude/agents/
```

### Prerequisites

| Tool | Required for | Install (macOS) |
|------|-------------|-----------------|
| `jq` | Every skill uses it for prd.json parsing | `brew install jq` |
| `perl` | `/ralph-loop` stop hook (promise extraction) | Ships with macOS |
| `claude` CLI | `ralph.sh` bash loop | Installed with Claude Code |
| `gh` (optional) | PR-creation suggestion on completion | `brew install gh` |
| `bash` 3.2+ | All shell scripts — macOS default works | — |

### What gets installed

Skills (each has its own slash command):

- `ralph-prd`, `ralph-convert`, `ralph-validate`, `ralph-review-prd`
- `ralph-agent`, `ralph-loop`, `ralph-worker`, `ralph-status`, `cancel-ralph`

Bundled subagents (from [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents), MIT):

- `Senior Developer`, `Backend Architect`, `DevOps Automator`, `Frontend Developer`
- `UX Researcher`, `UI Designer`
- `API Tester`, `Reality Checker`

See `.claude/agents/README.md` for provenance, the role-to-file mapping, and instructions for refreshing from upstream.

## Quick start

```bash
cd your-project
/ralph-prd                 # interactive — generates tasks/prd-*.md + prd.json + branch
/ralph-validate            # structural lint (optional but cheap)
/ralph-review-prd          # AI architectural pre-flight (optional, recommended)
/ralph-loop                # activate stop-hook loop and press enter to run
```

When all stories pass, the loop prints a `gh pr create --draft` command you can copy-paste.

## Core concepts

### PRDs and stories

A PRD (Product Requirements Document) is a markdown file describing a feature. `/ralph-prd` generates one interactively, then converts it to `prd.json` — a structured representation the loop can execute. Each story inside is:

- Right-sized for one focused session (split anything touching more than 2–3 files)
- Typed as `backend` / `frontend` / `fullstack` / `infra` / `data`
- Assigned a team of specialist subagents appropriate to the type
- Ordered by `priority` and (optionally) gated by explicit `depends_on`
- Verifiable — includes "Typecheck passes" and, for UI, "Verify in browser"

### Teams and the right-role-for-the-job principle

Instead of a generic developer implementing every story, Ralph spawns **the right team** based on the story's `type` field:

| Story type | Design phase | Implement phase | Review phase |
|-----------|-------------|-----------------|-------------|
| `backend` | — | Senior Developer | Reality Checker |
| `frontend` | UX Researcher + UI Designer | Senior Developer | Reality Checker |
| `fullstack` | UX Researcher | Backend Architect → Frontend Developer | Reality Checker |
| `infra` | — | DevOps Automator + Senior Developer | Reality Checker |
| `data` | — | Backend Architect + Senior Developer | Reality Checker |

A backend migration doesn't need UX research. A complex UI component shouldn't be built without design thinking. Matching expertise to story type produces better output per iteration.

### Three phases per story

1. **Design** (skip for backend/infra/data). Each design agent writes to its own file: `design-brief-US-XXX-<role>.md`. Parallel-safe.
2. **Implement**. Reads every `design-brief-US-XXX-*.md`, acceptance criteria, `progress.txt`, optional `AGENTS.md`. Produces one commit containing code + updated `progress.txt` + updated `prd.json`.
3. **Review**. Reads the commit via `.ralph-commit-US-XXX` handoff (not `git diff HEAD~1` — fragile). Runs the **full project test suite** to catch regressions in prior stories. Writes `APPROVED` or `NEEDS_CHANGES` to `review-US-XXX.md`.

### Model selection per phase

Each story carries a `models` object:

```json
"models": { "design": "opus", "implement": "sonnet", "review": "opus" }
```

Defaults: **opus** for reasoning-heavy work (design, review), **sonnet** for code generation (implement). Haiku is available for cost-sensitive work. Users override per story.

### Review retries with rejected-diff context + model escalation

| Attempt | Model | What changes |
|---------|-------|-------------|
| 1 | `story.models.implement` (usually `sonnet`) | Initial implementation |
| 2 (retry #1) | Same | Retry with `review-*.md` AND the rejected diff in `retry-diff-*.md`; implementer amends the prior commit |
| 3 (retry #2, last) | **`opus`** unless already opus | Escalated model — the implementer needs more reasoning capacity; still amends |

The worker preserves the rejected commit and passes its diff to the retry — without it the retry agent re-derives from scratch and reproduces the same mistake class.

### Dependencies

Two mechanisms, used together:

- **`priority`** (integer, low → high): coarse ordering hint.
- **`depends_on`** (array of story ids): hard prerequisite. The loop will NOT pick a story until every id in its `depends_on` array has `passes: true`.

The loop enforces `depends_on`. Pick up stories in the wrong order, and you'd get nonsense — this is how you prevent that. If every remaining incomplete story has at least one unmet dependency, that's a **dependency deadlock** and all loop modes halt with an explicit error.

### Blockers and manual recovery

After 3 failed implementation attempts on one story (initial + 2 retries), the worker writes `.ralph-blocker.md` instead of marking the story passed. The file contains:

- Story id, title, timestamp
- Full last review verdict (inline)
- Full rejected diff (inline)
- Four explicit unblock paths: rewrite / split / fix manually / skip

All three loop entry points refuse to iterate while `.ralph-blocker.md` exists. If you resolve it manually (e.g., mark the story `passes: true` in `prd.json`), the loop **auto-cleans** the blocker on its next start and resumes.

### File-based memory

Ralph deliberately does NOT rely on conversation context for memory. Everything that needs to persist lives in a file:

- `prd.json` — story state (passing / failing / deps)
- `progress.txt` — accumulated learnings, auto-compacted past 50 KB
- `.ralph-metrics.json` — per-story outcomes (cycles, model, files touched)
- Git commit history — what was actually done
- `AGENTS.md` (optional) — module-specific patterns

Every fresh iteration starts from files. That's what makes `ralph.sh` (one fresh Claude CLI per story) and `/ralph-loop` (one fresh user turn per story) work reliably on long PRDs.

## Skills reference

| Skill | Command | Purpose |
|-------|---------|---------|
| **ralph-prd** | `/ralph-prd` | Interactive PRD generation + `prd.json` conversion in one command. Asks clarifying questions via selectable option cards. |
| **ralph-convert** | `/ralph-convert` | Standalone PRD-to-JSON converter. Use when re-converting a hand-edited markdown PRD. |
| **ralph-validate** | `/ralph-validate` | Static linter: structure, required fields, `depends_on` cycles, missing "Typecheck passes". Zero tokens. Run before the loop. |
| **ralph-review-prd** | `/ralph-review-prd` | AI architectural pre-flight. One opus Backend Architect reads the whole PRD and flags sizing/ordering/missing stories/architectural risks. Writes `prd-review.md`. |
| **ralph-agent** | `/ralph-agent` | Multi-story orchestrator (in-session). Loops through incomplete stories, invokes `ralph-worker` per story. |
| **ralph-loop** | `/ralph-loop` | Stop-hook driven loop. Registers a hook that re-prompts you per incomplete story at every turn boundary. Survives pauses. |
| **ralph-worker** | `/ralph-worker` | Single-story team lead. Spawns design → implement → review agents for ONE story. Called by the other loop modes; usable directly for ad-hoc single-story work. |
| **ralph-status** | `/ralph-status` | Read-only state snapshot: counts, next runnable, dep-blocked list, active blocker, loop state, metrics summary. No side effects, ~100ms. |
| **cancel-ralph** | `/cancel-ralph` | Stop an active `/ralph-loop`. Removes the state file; add `--remove-hook` to also unregister the Stop hook from `.claude/settings.local.json`. |

Each skill's `SKILL.md` has the detailed contract; the table above is the index.

## Execution modes

Three ways to drive the loop. They all call the same `ralph-worker` per story — the only thing that varies is how the outer loop is driven.

### 1. Bash loop — `ralph.sh`

```bash
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]
```

Each iteration spawns a fresh `claude --print` subprocess. Full context reset between stories — the strongest isolation available.

- **Best for**: long overnight runs on big PRDs where context drift would otherwise degrade output.
- **Downsides**: pays CLI spawn cost per iteration; can't show rich UI. Runs outside Claude Code.

### 2. In-session orchestrator — `/ralph-agent`

All stories implemented in one assistant turn, with the orchestrator spawning specialist Agent calls.

- **Best for**: small PRDs (3–5 stories) you want to watch unfold in a single sitting.
- **Downsides**: context accumulates across stories; interruption loses progress.

### 3. Stop-hook driven — `/ralph-loop`

Registers a Stop hook that fires when the assistant tries to end its turn. The hook picks the next runnable story from `prd.json` and emits a `{"decision": "block", "reason": "<prompt>"}` response, re-prompting Claude as if the user had sent a new message. Each story gets a clean turn boundary within the same session.

- **Best for**: mid-sized PRDs, daily driver. Live visibility, reduced context buildup, no CLI spawn cost, survives pauses across the same session.
- **Downsides**: state persists in `.claude/settings.local.json` + `.claude/ralph-loop.local.md`; remember to `/cancel-ralph` when done.

### Which to use

| You want... | Mode |
|---|---|
| Leave a 30-story PRD running overnight | `ralph.sh` |
| Watch a small PRD finish in one session | `/ralph-agent` |
| Daily work, mid-sized PRDs, survives pauses | `/ralph-loop` |

All three preflight-check for `.ralph-blocker.md` and refuse to iterate on an unresolved blocker.

## prd.json schema

```json
{
  "name": "Feature Name",
  "branch": "feature/feature-name",
  "stories": [
    {
      "id": "US-001",
      "title": "Short descriptive title",
      "description": "As a [user], I want [action] so that [benefit].",
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
        "Specific criterion 1",
        "Specific criterion 2",
        "Typecheck passes"
      ],
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Field reference

**Top level**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `name` | string | yes | Used for PR title suggestion |
| `branch` | string | yes | `feature/...`, `fix/...`, `hotfix/...`, or `chore/...` |
| `stories` | array | yes | Non-empty |

**Per story**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | yes | `US-XXX` convention; must be unique |
| `title` | string | yes | |
| `description` | string | yes | User-story format preferred |
| `priority` | integer | yes | Coarse ordering hint, low → high |
| `depends_on` | string[] | no (default `[]`) | Every id must reference an existing story; no cycles; no self-loops |
| `type` | enum | yes | `backend` \| `frontend` \| `fullstack` \| `infra` \| `data` |
| `team.design` | string[] | yes | Empty for backend/infra/data |
| `team.implement` | string[] | yes | At least one agent |
| `team.review` | string[] | yes | At least one agent |
| `models.design` | enum | recommended | `opus` \| `sonnet` \| `haiku` (default `opus`) |
| `models.implement` | enum | recommended | Default `sonnet`; auto-escalates to `opus` on retry #2 |
| `models.review` | enum | recommended | Default `opus` |
| `acceptance_criteria` | string[] | yes | Must include "Typecheck passes"; UI stories must include "Verify in browser" |
| `passes` | boolean | yes | Loop updates on success; `false` on write, `true` when story passes review |
| `notes` | string | no | Free-form per-story notes |

Run `/ralph-validate` to statically verify all of the above.

## Runtime files

Files Ralph reads from or writes to at runtime. Kept in the working directory unless noted.

### Persistent state (git-tracked)

| File | Lifecycle | Purpose |
|------|-----------|---------|
| `prd.json` | Written by `/ralph-prd`, updated by every worker | Source of truth for story state |
| `progress.txt` | Updated every successful story; auto-compacted past 50 KB | Carries learnings across iterations |
| `tasks/prd-<feature>.md` | Written by `/ralph-prd` | Human-readable PRD |
| `archive/prd-<branch>-<ts>.json` | On branch change | Archived PRDs |
| `archive/progress-<ts>.txt` | On `progress.txt` compaction | Archived iteration logs |
| `AGENTS.md` | Optional, hand-written | Module-specific patterns; read by workers if present |

### Temporary state (cleaned up after success)

| File | Lifecycle | Purpose |
|------|-----------|---------|
| `design-brief-US-XXX-<role>.md` | Per design agent per story | Design output; one file per parallel agent |
| `review-US-XXX.md` | Written by reviewer | APPROVED or NEEDS_CHANGES verdict |
| `retry-diff-US-XXX.md` | Written before each retry | Snapshot of the rejected commit diff |
| `.ralph-commit-US-XXX` | Written by implementer | Commit SHA handoff for reviewer (`git show $(cat …)`) |
| `prd-review.md` | Written by `/ralph-review-prd` | Architectural pre-flight findings |

### Intervention / analytics (not auto-deleted)

| File | Lifecycle | Purpose |
|------|-----------|---------|
| `.ralph-blocker.md` | Written on retry cap; deleted manually or auto-cleaned when the story is `passes: true` | Blocker state — loop halts until resolved |
| `.ralph-metrics.json` | Updated per successful story | Per-story metrics; surfaced in `/ralph-status`. Add to `.gitignore` to keep it out of commits |

### Loop mode state (in `.claude/`)

| File | Lifecycle | Purpose |
|------|-----------|---------|
| `.claude/ralph-loop.local.md` | Written by `/ralph-loop`, removed by `/cancel-ralph` or hook on completion | Current iteration, max, started_at |
| `.claude/settings.local.json` | Updated by `/ralph-loop`, hook stays registered until `/cancel-ralph --remove-hook` | Claude Code Stop hook registration |
| `.ralph_branch` | Updated by `ralph.sh` | Last branch seen, triggers archive on branch change |

### Recommended `.gitignore` additions

```
.ralph-metrics.json
.ralph-blocker.md
.ralph-commit-*
retry-diff-*.md
review-*.md
design-brief-*.md
prd-review.md
```

(Or don't — it's fine to commit them if you want per-story history. The worker cleans them up on the success commit anyway.)

## Commit discipline

Every story lands as **one commit** bundling code + `progress.txt` + `prd.json` (+ any `archive/` entries created by the compactor that iteration). The rules, enforced in every mode's worker prompt:

- **Subject only**, no body. Format: `feat: <imperative>` or `fix: <imperative>`.
- **No story numbers**: never `feat: US-011 ...`, never `feat(US-011): ...`.
- **No scope prefixes**: never `feat(api): ...`, `feat(auth): ...`.
- **One commit per story** — never a separate `chore:` commit for `prd.json` or `progress.txt`.
- **No Claude as author/co-author.**
- **On retry, amend** — don't create a second commit for review feedback.
- **Temporary files deleted before staging** — no `review-*.md`, `design-brief-*.md`, or `retry-diff-*.md` in the commit.

This keeps `git log --oneline` readable as "one line per feature increment" and makes the history useful for bisecting.

## Bundled subagents

The repo ships the eight subagent definitions Ralph spawns — a subset of [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) (MIT License). Installing Ralph via `cp -rn` gives you a fully working system with no separate agent install.

| Role in team | `subagent_type` | File |
|-------------|----------------|------|
| Senior Developer | `Senior Developer` | `engineering/engineering-senior-developer.md` |
| Backend Architect | `Backend Architect` | `engineering/engineering-backend-architect.md` |
| Frontend Developer | `Frontend Developer` | `engineering/engineering-frontend-developer.md` |
| DevOps Automator | `DevOps Automator` | `engineering/engineering-devops-automator.md` |
| UX Researcher | `UX Researcher` | `design/design-ux-researcher.md` |
| UI Designer | `UI Designer` | `design/design-ui-designer.md` |
| API Tester | `API Tester` | `testing/testing-api-tester.md` |
| Code Reviewer | `Reality Checker` | `testing/testing-reality-checker.md` |

See `.claude/agents/README.md` for the upstream refresh command and customization guidance.

## Typical workflows

### Starting a new feature

```bash
cd your-project
/ralph-prd                 # generates prd.json + branch + markdown PRD
/ralph-validate            # structural check (fast, no tokens)
/ralph-review-prd          # architectural critique (one opus pass)
# read prd-review.md, edit prd.json if needed
/ralph-loop                # activate stop hook; your next turn kicks off iteration 1
```

### Running unattended overnight

```bash
cd your-project
~/.claude/skills/ralph-agent/ralph.sh 30   # 30-iteration ceiling
# Wake up, check git log on the feature branch.
# If all stories pass, the script prints a `gh pr create` suggestion you can copy.
```

### Checking on progress mid-run

```bash
/ralph-status
# Ralph Status — Task Status (feature/task-status)
# ────────────────────────────────────────────────────────────
#
# Stories: 7 passing / 12 total (5 incomplete)
# Next runnable: US-008 — Return status in API (backend)
#
# Blocked by dependencies:
#   US-012 — Summary view (waiting on: US-008, US-010)
#
# Metrics (7 stories recorded)
#   Avg review cycles: 1.3
#   Lines changed: +1240 / -310
#   Most-used implement model: sonnet
#
# /ralph-loop active: iteration 7 / 20 (started 2026-04-23T20:00:00Z)
```

### Resolving a blocker

1. Loop halts; `.ralph-blocker.md` is written.
2. Read the file — it has the review verdict and rejected diff inline, plus four unblock options.
3. Pick one:
   - **Rewrite** the story in `prd.json` (clearer criteria, split, different team), delete `.ralph-blocker.md`, re-run the loop.
   - **Fix manually** — implement it yourself, commit, set `passes: true` for the story in `prd.json`. Re-run the loop; it auto-cleans the blocker on startup.
   - **Skip** — set `passes: true` without implementing, delete the blocker, re-run.
4. The loop picks up at the next incomplete story.

### Finishing and opening a PR

When all stories pass, the loop prints (only if `gh` is on PATH):

```
Ready to open a PR? Push the branch and run:
  git push -u origin feature/task-status
  gh pr create --draft --title "Task Status Feature" --body "See prd.json for the full story breakdown."
```

Copy, run manually. Ralph won't push or create the PR itself — those are shared-state operations you should confirm.

### Stopping an active `/ralph-loop`

```bash
/cancel-ralph                # removes state file; hook becomes a no-op
/cancel-ralph --remove-hook  # also unregisters the hook from settings.local.json
```

## Troubleshooting

### "Dependency deadlock" on startup

Incomplete stories exist but none are runnable — at least one `depends_on` array blocks the graph. Run `/ralph-validate` to see which story is unresolvable, then fix the `depends_on` fields (or mark an upstream story `passes: true` if it's genuinely done).

### The loop keeps picking the same story

It's probably hitting the review retry cap and writing `.ralph-blocker.md`. Check for the file. If it's there, follow the resolve-a-blocker workflow above. If it's NOT there and the loop still re-picks the same story, the worker isn't setting `passes: true` — usually a test-suite that fails for environmental reasons (wrong node version, missing env var).

### Reviewer flags a regression

Expected: since commit `8c4dd82`, the reviewer runs the full test suite. If a test from an earlier story breaks, the review is NEEDS_CHANGES pointing at which prior story owns the broken behavior. Fix or amend in the retry; don't silence the test.

### "progress.txt is huge"

Not a problem — it auto-compacts past 50 KB. Older entries land in `archive/progress-<timestamp>.txt`, committed alongside the story that triggered the compaction.

### "Unknown subagent_type: Senior Developer"

The bundled agents weren't copied into `~/.claude/agents/`. Re-run:

```bash
cd ~/ralph
cp -rn .claude/agents/* ~/.claude/agents/
```

### Stop hook fires repeatedly after I'm done

`/cancel-ralph` only removes the state file. The hook stays registered in `.claude/settings.local.json` as a no-op. Use `/cancel-ralph --remove-hook` to fully unregister it.

### I want to test this on a small project first

Create a minimal `prd.json` with one or two stories by hand, run `/ralph-validate`, then `/ralph-loop`. The validator catches almost any hand-editing mistakes; everything else is the same as a full PRD.

## Credits and license

Ralph (the core loop concept) is based on [snarktank/ralph](https://github.com/snarktank/ralph), originally written for AMP.

The `/ralph-loop` Stop hook mechanism is inspired by Anthropic's [`ralph-wiggum` plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code.

The bundled subagents are verbatim from [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents), MIT License — attribution preserved in `.claude/agents/LICENSE`.

This repository's own code and skills are provided as-is. Use, modify, and redistribute at will; no warranty.
