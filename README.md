# Ralph for Claude Code

Autonomous AI agent loop that implements PRD stories iteratively until completion. Port of [snarktank/ralph](https://github.com/snarktank/ralph) from AMP to Claude Code.

## How It Works

Ralph spawns fresh Claude CLI sessions to implement user stories one at a time. Memory persists through files:
- `prd.json` - Story tracking and completion status
- `progress.txt` - Learnings accumulated across iterations
- Git commit history

Each iteration starts with clean context, forcing proper documentation.

## Installation

Copy the skills to your Claude Code skills directory:

```bash
cp -r skills/* ~/.claude/skills/
```

## Usage

### 1. Generate a PRD

```
/ralph-prd
```

Creates a structured PRD in `tasks/prd-[feature].md` through clarifying questions.

### 2. Convert PRD to JSON

```
/ralph-convert
```

Converts the markdown PRD to `prd.json` with properly sized, dependency-ordered stories.

### 3. Run the Agent Loop

**Option A: Bash loop (recommended)**

```bash
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]
```

Spawns completely fresh Claude CLI sessions for true process isolation.

**Option B: In-session subagents**

```
/ralph-agent
```

Orchestrates within your current session using subagents.

## Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| ralph-prd | `/ralph-prd` | Generate PRDs through clarifying questions |
| ralph-convert | `/ralph-convert` | Convert markdown PRDs to prd.json |
| ralph-agent | `/ralph-agent` | Orchestrator (bash loop or subagents) |
| ralph-worker | `/ralph-worker` | Single story implementation |

## File Structure

```
project/
├── prd.json          # Story tracking
├── progress.txt      # Learnings log
├── archive/          # Previous runs
└── AGENTS.md         # Module patterns (optional)
```

## prd.json Format

```json
{
  "name": "Feature Name",
  "branch": "feature/feature-name",
  "stories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [action] so that [benefit].",
      "priority": 1,
      "acceptance_criteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Key Principles

1. **Right-sized stories** - Each story completable in one focused session
2. **Dependency ordering** - Lower priority numbers execute first
3. **Verifiable criteria** - No vague language, concrete checks only
4. **Fresh context** - Each iteration starts clean, relies on files
5. **Document learnings** - progress.txt carries knowledge forward

## Credits

Based on [snarktank/ralph](https://github.com/snarktank/ralph) for AMP.
