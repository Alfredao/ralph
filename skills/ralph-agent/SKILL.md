---
name: ralph-agent
description: Autonomous coding agent that implements user stories from prd.json iteratively. Works through stories one by one, running quality checks, updating progress, and committing changes until all stories pass.
---

# Ralph Agent

Autonomous agent that implements PRD stories iteratively until completion.

## Two Ways to Run

### Option 1: Bash Loop (Recommended - True Isolation)

Run the bash script for **true process isolation** - each iteration spawns a completely fresh Claude CLI session:

```bash
# From your project directory
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]

# Examples
~/.claude/skills/ralph-agent/ralph.sh      # Default: 10 iterations
~/.claude/skills/ralph-agent/ralph.sh 20   # Up to 20 iterations
```

This matches the original Ralph design from AMP.

### Option 2: In-Session Subagents

Use `/ralph-agent` skill to orchestrate within your current session using subagents. Lighter weight but shares parent context.

---

## Architecture (Bash Loop)

```
ralph.sh (Bash Loop)
    │
    ├── Check prd.json for incomplete stories
    │
    ├── Spawn Claude CLI → US-001 → Fresh process, implements, commits
    │   └── Exits
    │
    ├── Spawn Claude CLI → US-002 → Fresh process, implements, commits
    │   └── Exits
    │
    └── Continue until all stories pass or max iterations
```

## Architecture (In-Session Subagents)

```
Orchestrator (current session)
    │
    ├── Spawn Subagent → US-001 → Fresh context, implements, commits
    │   └── Returns: success/failure
    │
    ├── Spawn Subagent → US-002 → Fresh context, implements, commits
    │   └── Returns: success/failure
    │
    └── Continue until all stories pass
```

**Why subagents?** Each worker starts with clean context, just like the original Ralph. This:
- Prevents context pollution across stories
- Forces proper documentation in progress.txt
- Matches Ralph's design philosophy

## Orchestrator Workflow

### Step 1: Initialize

```bash
# Verify prd.json exists
cat prd.json

# Create progress.txt if needed
# Create/checkout feature branch
```

If `prd.json` doesn't exist, stop and tell user to run `/ralph-convert` first.

### Step 2: Check for Incomplete Stories

Read `prd.json` and find stories where `passes: false`.

If none remain → all done, report completion.

### Step 3: Spawn Worker Subagent

For the highest-priority incomplete story, spawn a subagent using the Task tool:

```
Use Task tool with:
- subagent_type: "general-purpose"
- prompt: [Ralph Worker Instructions - see below]
```

**Worker prompt template:**
```
You are a Ralph Worker implementing a single user story.

## Your Task
Implement story [STORY_ID]: [STORY_TITLE]

## Context Files
1. Read `prd.json` - find your story's acceptance criteria
2. Read `progress.txt` - check Codebase Patterns and previous learnings
3. Read `AGENTS.md` if it exists - module-specific patterns

## Acceptance Criteria
[LIST CRITERIA FROM prd.json]

## Workflow
1. Explore relevant code files
2. Implement the story (minimal, focused changes)
3. Run quality checks:
   - npm run typecheck (or equivalent)
   - npm run lint (or equivalent)
   - npm test (or equivalent)
4. If UI changes: verify in browser
5. Update progress.txt with learnings
6. Commit changes with message: "[STORY_ID]: [title]"
7. Update prd.json: set passes: true for this story

## Rules
- Make ONLY changes needed for this story
- Follow existing code patterns
- All quality checks must pass
- Document learnings in progress.txt

## Output
Report back:
- What was implemented
- Files changed
- Any issues encountered
- Whether story passes (true/false)
```

### Step 4: Check Result

After subagent returns:
- Read `prd.json` to verify story marked as complete
- If failed, log the issue and decide whether to retry or skip

### Step 5: Loop or Complete

If more incomplete stories exist → return to Step 3

If all stories pass → report completion:
```
All stories complete!

Summary:
- US-001: [Title] ✓
- US-002: [Title] ✓
...

Total: X stories implemented
Branch: feature/branch-name
```

## Orchestrator Responsibilities

The orchestrator (you) handles:
- Reading prd.json to determine next story
- Spawning subagents with proper context
- Tracking overall progress
- Handling failures (retry, skip, or stop)
- Reporting final completion

The orchestrator does NOT:
- Implement stories directly
- Accumulate implementation context
- Make code changes

## Spawning Workers

Use the Task tool like this for each story:

```
Task tool call:
  subagent_type: "general-purpose"
  description: "Implement US-XXX"
  prompt: |
    You are a Ralph Worker. Your job is to implement ONE user story with fresh context.

    ## Story to Implement
    ID: US-XXX
    Title: [title]
    Priority: X

    ## Acceptance Criteria
    - [criterion 1]
    - [criterion 2]
    - Typecheck passes

    ## Instructions
    1. Read progress.txt for codebase patterns and learnings
    2. Explore the codebase to understand current implementation
    3. Make minimal, focused changes to implement the story
    4. Run ALL quality checks (typecheck, lint, test)
    5. For UI changes, verify in browser
    6. Append learnings to progress.txt
    7. Commit with message "US-XXX: [brief description]"
    8. Update prd.json to set passes: true for US-XXX

    ## Output
    Report:
    - Implementation summary
    - Files modified
    - Quality check results
    - Success: true/false
```

## Error Handling

**If a worker fails:**
1. Check what went wrong (read progress.txt, git status)
2. Options:
   - Retry with additional context
   - Skip and move to next story
   - Stop and report blocker to user

**If stuck in a loop:**
- After 3 failed attempts on same story, stop
- Report the issue to user for manual intervention

## File Structure

```
project/
├── prd.json          # Story tracking (read by orchestrator + workers)
├── progress.txt      # Learnings log (written by workers)
├── archive/          # Previous prd.json files
└── AGENTS.md         # Module patterns (optional, read by workers)
```

## Initialization Checklist

Before starting the loop:
- [ ] `prd.json` exists with stories
- [ ] On correct git branch (from prd.json)
- [ ] `progress.txt` exists (create if not)

## Example Session

```
User: /ralph-agent

Orchestrator: Reading prd.json... Found 4 stories, 0 complete.
              Starting with US-001: Add status column to tasks table

              [Spawns subagent for US-001]

Subagent:     [Works with fresh context]
              [Implements, tests, commits]
              [Updates prd.json and progress.txt]
              [Returns: Success]

Orchestrator: US-001 complete. Moving to US-002: Return status in task API

              [Spawns subagent for US-002]

              ... continues until all pass ...

Orchestrator: All stories complete!
              - US-001: Add status column ✓
              - US-002: Return status in API ✓
              - US-003: Create StatusBadge component ✓
              - US-004: Display status in task list ✓

              Branch: feature/task-status
```

## Key Principle

**Fresh context per story is the feature.**

Each worker starts clean and must rely on:
- `prd.json` for requirements
- `progress.txt` for learned patterns
- Git history for what's been done

This forces proper documentation and prevents the context pollution that happens when one agent tries to do everything.
