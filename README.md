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
- `design-brief-US-XXX.md` — Temporary design phase output (cleaned up after approval)
- `review-US-XXX.md` — Temporary review phase output (cleaned up after approval)
- Git commit history

Each iteration starts with clean context, forcing proper documentation.

## Installation

Copy the skills to your Claude Code skills directory:

```bash
cp -r skills/* ~/.claude/skills/
```

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

**Option A: Bash loop (recommended — true process isolation)**

```bash
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]
```

Spawns completely fresh Claude CLI sessions per iteration. Best for long-running implementations where context buildup matters.

**Option B: In-session subagents**

```
/ralph-agent
```

Orchestrates within your current session using subagents. Convenient for smaller PRDs.

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
  +-- Phase 1: DESIGN (parallel agents)
  |   +-- UX Researcher -> interaction patterns, accessibility
  |   +-- UI Designer -> component structure, visual specs
  |   +-- Output: design-brief-US-003.md
  |
  +-- Phase 2: IMPLEMENT (sequential)
  |   +-- Senior Developer -> implements using design brief
  |   +-- Output: code changes committed
  |
  +-- Phase 3: REVIEW
      +-- Code Reviewer -> verifies against criteria + design brief
      +-- Output: APPROVED or NEEDS_CHANGES (max 2 retry cycles)
```

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
| **ralph-worker** | `/ralph-worker` | Single-story team lead (spawns design/implement/review agents) |

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
      "type": "backend",
      "team": {
        "design": [],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
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
├── design-brief-US-XXX.md    # Temporary: design phase output
├── review-US-XXX.md          # Temporary: review phase output
├── archive/                  # Previous prd.json files
└── AGENTS.md                 # Module-specific patterns (optional)
```

## Key Principles

1. **Right team for the right story** — A backend migration doesn't need UX research. A complex UI component shouldn't be built without design thinking.
2. **Right-sized stories** — Each story completable in one focused session. Split anything that touches more than 2-3 files.
3. **Dependency ordering** — Database first, APIs second, UI third, integrations last.
4. **Verifiable criteria** — No vague language. "Returns 404 when not found", not "handles errors properly".
5. **Fresh context** — Each iteration starts clean, relies on files for state.
6. **Document learnings** — `progress.txt` carries knowledge forward across iterations.

## Error Handling

- **Design agent fails** — Skip design phase, proceed to implement without brief
- **Implementation fails** — Retry with additional context (max 2 retries), then stop and report blocker
- **Review rejects** — Re-implement with review feedback (max 2 cycles), then stop and report blocker
- **Stuck in loop** — After 3 failed attempts on same story, stop for manual intervention

## Credits

Based on [snarktank/ralph](https://github.com/snarktank/ralph) for AMP.
