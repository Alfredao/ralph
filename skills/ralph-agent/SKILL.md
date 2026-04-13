---
name: ralph-agent
description: Autonomous coding agent that implements user stories from prd.json iteratively. Spawns specialized agent teams (designers, developers, reviewers) per story type. Works through stories one by one until all pass.
---

# Ralph Agent - Multi-Agent Team Orchestrator

Autonomous agent that implements PRD stories by spawning **specialized teams** of agents per story. Each story gets the right experts based on its type.

## Two Ways to Run

### Option 1: Bash Loop (Recommended - True Isolation)

```bash
~/.claude/skills/ralph-agent/ralph.sh [max_iterations]
```

Each iteration spawns a completely fresh Claude CLI session.

### Option 2: In-Session Subagents

Use `/ralph-agent` skill to orchestrate within your current session using subagents.

---

## Core Concept: Team-Based Story Implementation

Instead of one generic worker per story, Ralph now spawns **the right team** based on the story's `type` field in prd.json.

```
Orchestrator picks US-003 (type: "frontend")
  │
  ├── Phase 1 - DESIGN (parallel agents)
  │   ├── UX Researcher → analyzes patterns, accessibility, best approach
  │   └── UI Designer → proposes component structure, visual specs
  │   └── Output: design-brief.md
  │
  ├── Phase 2 - IMPLEMENT (sequential)
  │   └── Senior Developer → implements using design brief + acceptance criteria
  │   └── Output: code changes committed
  │
  └── Phase 3 - REVIEW (sequential)
      └── Code Reviewer → reviews against criteria + design brief
      └── Output: approved OR feedback → retry implement (max 2 cycles)
```

## Agent Type Mapping

These map to Claude Code's built-in `subagent_type` values:

| Role in Team | subagent_type | Purpose |
|-------------|---------------|---------|
| UX Researcher | `UX Researcher` | Analyzes best UX approach, accessibility, interaction patterns |
| UI Designer | `UI Designer` | Proposes component structure, visual hierarchy, design tokens |
| Senior Developer | `Senior Developer` | Implements the story following design brief and patterns |
| Frontend Developer | `Frontend Developer` | Implements frontend-specific code |
| Backend Architect | `Backend Architect` | Implements backend architecture, APIs, DB changes |
| Code Reviewer | `Reality Checker` | Reviews implementation against acceptance criteria |
| DevOps Automator | `DevOps Automator` | Handles infrastructure, CI/CD, deployment config |
| API Tester | `API Tester` | Tests API integrations, validates contracts |

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

### Step 3: Read Story Team Config

For the highest-priority incomplete story, read its `type`, `team`, and `models` fields:

```json
{
  "id": "US-003",
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

If `models` is absent or a key is missing, apply defaults: `design: "opus"`, `implement: "sonnet"`, `review: "opus"`.

### Step 4: Execute Phases

Run each phase sequentially. Within a phase, spawn agents in **parallel** when possible.

#### Phase 1: DESIGN (if team.design is non-empty)

Spawn all design agents in parallel. Each writes findings to `design-brief-[STORY_ID].md`.

**Design agent prompt template:**
```
You are a [ROLE] analyzing story [STORY_ID]: [TITLE]

## Your Task
Analyze this story and provide your expert recommendations.

## Story Details
- Description: [description]
- Acceptance Criteria: [criteria]
- Story Type: [type]

## Context
1. Read `progress.txt` for codebase patterns and previous learnings
2. Read `AGENTS.md` if it exists for module-specific patterns
3. Explore the existing codebase to understand current patterns

## Output
Write your analysis to `design-brief-[STORY_ID].md`:

### [Your Role] Recommendations
- **Approach**: [recommended implementation approach]
- **Patterns to follow**: [existing patterns in codebase to reuse]
- **Accessibility**: [a11y considerations if applicable]
- **Component structure**: [proposed structure if UI]
- **Risks**: [potential issues to watch for]

Keep it concise and actionable. The developer will read this before implementing.
```

**Merge design briefs:** If multiple design agents ran, their outputs are appended to the same file. The orchestrator does NOT need to merge -- each agent appends its section.

#### Phase 2: IMPLEMENT

Spawn implementation agents. For most stories this is a single Senior Developer. For fullstack stories, spawn Backend Architect + Frontend Developer sequentially (backend first, then frontend).

**Implementation agent prompt template:**
```
You are a Ralph Worker ([ROLE]) implementing story [STORY_ID]: [TITLE]

## Your Task
Implement this story following the design brief and acceptance criteria.

## Context Files
1. Read `prd.json` - find your story's acceptance criteria
2. Read `progress.txt` - check Codebase Patterns and previous learnings
3. Read `design-brief-[STORY_ID].md` if it exists - follow design recommendations
4. Read `AGENTS.md` if it exists - module-specific patterns

## Acceptance Criteria
[LIST CRITERIA FROM prd.json]

## Workflow
1. Explore relevant code files
2. If design brief exists, follow its recommendations
3. Implement the story (minimal, focused changes)
4. Run quality checks:
   - Typecheck (npm run typecheck or equivalent)
   - Lint (npm run lint or equivalent)
   - Tests (npm test or equivalent)
5. For UI changes: verify visually in browser
6. Update progress.txt with learnings
7. Commit changes: "feat: [Brief description]"
8. Do NOT update prd.json yet (reviewer will confirm first)

## Rules
- Make ONLY changes needed for this story
- Follow existing code patterns
- Follow design brief recommendations when available
- All quality checks must pass
- Document learnings in progress.txt

## Output
Report back:
- What was implemented
- Files changed
- Quality check results
- Any issues encountered
```

#### Phase 3: REVIEW

Spawn the review agent(s) to verify the implementation.

**Review agent prompt template:**
```
You are a Code Reviewer for story [STORY_ID]: [TITLE]

## Your Task
Review the implementation against acceptance criteria and design brief.

## Context
1. Read `prd.json` - check acceptance criteria for this story
2. Read `design-brief-[STORY_ID].md` if it exists - verify design was followed
3. Run `git diff HEAD~1` to see what changed
4. Read the modified files
5. Run quality checks (typecheck, lint, tests)

## Review Checklist
- [ ] All acceptance criteria are met
- [ ] Code follows existing patterns
- [ ] Design brief recommendations were followed (if applicable)
- [ ] No unnecessary changes beyond the story scope
- [ ] Quality checks pass (typecheck, lint, tests)
- [ ] For UI: visually verified in browser

## Output
Write your review to `review-[STORY_ID].md`:

### Review Result: APPROVED / NEEDS_CHANGES

**Criteria Check:**
- [criterion 1]: PASS/FAIL - [reason]
- [criterion 2]: PASS/FAIL - [reason]

**Issues Found:**
- [issue description and how to fix]

**Summary:**
[overall assessment]
```

### Step 5: Handle Review Result

After review:

- **APPROVED**: Update `prd.json` to set `passes: true`, clean up design/review files
- **NEEDS_CHANGES**: Re-spawn implementation agent with review feedback (max 2 retry cycles)
  - Include the review file content in the implementation prompt
  - After 2 failed review cycles, stop and report blocker to user

### Step 6: Loop or Complete

If more incomplete stories exist → return to Step 3.

If all stories pass → report completion and clean up temporary files:
```
All stories complete!

Summary:
- US-001: [Title] ✓ (backend - Senior Developer + Code Reviewer)
- US-002: [Title] ✓ (backend - Senior Developer + Code Reviewer)
- US-003: [Title] ✓ (frontend - UX Researcher + UI Designer + Senior Developer + Code Reviewer)
...

Total: X stories implemented
Branch: feature/branch-name
```

## Orchestrator Responsibilities

The orchestrator (you) handles:
- Reading prd.json to determine next story and its team
- Spawning the right agents for each phase
- Passing design briefs to implementation agents
- Passing review feedback for retry cycles
- Tracking overall progress
- Handling failures (retry, skip, or stop)
- Cleaning up temporary files (design-brief-*.md, review-*.md)
- Reporting final completion

The orchestrator does NOT:
- Implement stories directly
- Make code changes
- Skip the review phase

## Spawning Teams

Use the Agent tool for each team member. Always include the `model` parameter from the story's `models` field:

```
Agent tool call:
  model: "opus"                       # story.models.design (or default)
  subagent_type: "UX Researcher"      # or "UI Designer", "Senior Developer", etc.
  description: "Design US-003"        # or "Implement US-003", "Review US-003"
  prompt: |
    [Use the appropriate prompt template from above]
```

Model by phase:
- Design agents: `story.models.design` (default: `"opus"`)
- Implement agents: `story.models.implement` (default: `"sonnet"`)
- Review agents: `story.models.review` (default: `"opus"`)

**Parallel spawning:** When multiple agents are in the same phase (e.g., design phase with UX Researcher + UI Designer), spawn them in parallel using multiple Agent calls in the same message.

**Sequential phases:** Always wait for one phase to complete before starting the next.

## Backward Compatibility

If `prd.json` stories don't have `type` or `team` fields (old format), fall back to the default behavior:
- Treat as `type: "backend"`
- Team: `{ "design": [], "implement": ["Senior Developer"], "review": ["Code Reviewer"] }`

If stories don't have a `models` field (or it's partial), apply model defaults:
- `design: "opus"`, `implement: "sonnet"`, `review: "opus"`

This ensures old prd.json files still work unchanged.

## Error Handling

**If a design agent fails:**
- Skip design phase, proceed to implement without design brief
- Log the skip in progress.txt

**If an implementation agent fails:**
1. Check what went wrong (read progress.txt, git status)
2. Retry with additional context (max 2 retries)
3. If still failing, stop and report blocker

**If a review agent rejects:**
1. Pass review feedback to implementation agent
2. Re-implement with feedback
3. Re-review (max 2 cycles total)
4. If still failing, stop and report blocker

**If stuck in a loop:**
- After 3 failed attempts on same story, stop
- Report the issue to user for manual intervention

## File Structure

```
project/
├── prd.json              # Story tracking with type + team fields
├── progress.txt          # Learnings log (written by workers)
├── design-brief-US-XXX.md  # Temporary: design phase output
├── review-US-XXX.md        # Temporary: review phase output
├── archive/              # Previous prd.json files
└── AGENTS.md             # Module patterns (optional)
```

Temporary files (`design-brief-*.md`, `review-*.md`) are cleaned up after each story is approved.

## Example Session

```
User: /ralph-agent

Orchestrator: Reading prd.json... Found 3 stories, 0 complete.

              US-001: Add status column [backend]
              Team: Senior Developer + Code Reviewer

              [Phase: IMPLEMENT - Spawning Senior Developer]
              [Phase: REVIEW - Spawning Code Reviewer]
              → APPROVED. US-001 complete.

              US-002: Create StatusBadge component [frontend]
              Team: UX Researcher + UI Designer + Senior Developer + Code Reviewer

              [Phase: DESIGN - Spawning UX Researcher + UI Designer in parallel]
              → Design brief ready.
              [Phase: IMPLEMENT - Spawning Senior Developer with design brief]
              [Phase: REVIEW - Spawning Code Reviewer]
              → NEEDS_CHANGES: "Missing aria-label on badge"
              [Phase: IMPLEMENT (retry 1) - Spawning Senior Developer with review feedback]
              [Phase: REVIEW (retry 1) - Spawning Code Reviewer]
              → APPROVED. US-002 complete.

              US-003: Add status filter [fullstack]
              Team: UX Researcher + Backend Architect + Frontend Developer + Code Reviewer

              [Phase: DESIGN - Spawning UX Researcher]
              → Design brief ready.
              [Phase: IMPLEMENT - Spawning Backend Architect, then Frontend Developer]
              [Phase: REVIEW - Spawning Code Reviewer]
              → APPROVED. US-003 complete.

              All stories complete!
              - US-001: Add status column ✓
              - US-002: Create StatusBadge ✓
              - US-003: Add status filter ✓

              Branch: feature/task-status
```

## Key Principle

**The right team for the right story.**

A backend migration doesn't need UX research. A complex UI component shouldn't be built without design thinking. By matching expertise to story type, each implementation gets the specialized attention it deserves.
