---
name: ralph-worker
description: Implements a single user story from prd.json with fresh context. Team-aware - spawns specialized agents (designers, developers, reviewers) based on story type. Used by ralph-agent orchestrator or manually for single-story implementation.
---

# Ralph Worker - Team-Aware Story Implementer

Implements ONE user story with fresh context. When run standalone, it acts as a **team lead** -- reading the story's team config and spawning the right specialists.

## Purpose

Workers are team-aware implementers. They:
- Start with clean context (no prior conversation history)
- Read all state from files (prd.json, progress.txt)
- Identify the story's type and team configuration
- Spawn specialized agents for design, implementation, and review
- Coordinate the team to deliver the story
- Write learnings back to files
- Commit code + progress.txt + prd.json as ONE commit with `feat: <imperative>` (no story numbers, no scope prefixes)

## Workflow

### 1. Read Context Files

```bash
# Get story requirements + team config
cat prd.json

# Get codebase patterns and previous learnings
cat progress.txt

# Check for module-specific patterns
cat AGENTS.md  # if exists
```

### 2. Identify Your Story & Team

Find your assigned story in `prd.json` by ID. Note:
- Title, description, acceptance criteria
- **type** field (backend/frontend/fullstack/infra/data)
- **team** object with design/implement/review arrays
- **models** object with model names per phase (`"opus"`, `"sonnet"`, or `"haiku"`)
- **depends_on** array (may be empty or absent). The orchestrator/loop filters on this — by the time you receive the story, every id in `depends_on` is guaranteed to have `passes: true`. You don't need to re-check; use it as context for what's already been built.

If no `type` or `team` fields exist (old format), default to:
```json
{
  "type": "backend",
  "team": { "design": [], "implement": ["Senior Developer"], "review": ["Code Reviewer"] },
  "models": { "design": "opus", "implement": "sonnet", "review": "opus" }
}
```

If `models` is absent or partially defined, fill missing keys from defaults: `design: "opus"`, `implement: "sonnet"`, `review: "opus"`.

### 3. Execute Team Phases

Based on the story's team config, run phases sequentially:

#### Phase 1: DESIGN (skip if team.design is empty)

Spawn design agents **in parallel** using the Agent tool:

```
For each agent in team.design:
  Agent tool:
    model: [story.models.design or "opus"]
    subagent_type: [agent type - see mapping below]
    description: "Design [STORY_ID]"
    prompt: |
      You are a [ROLE] analyzing story [STORY_ID]: [TITLE]

      ## Story Details
      - Description: [description]
      - Acceptance Criteria: [criteria]
      - Story Type: [type]

      ## Context
      1. Read `progress.txt` for codebase patterns
      2. Read `AGENTS.md` if exists
      3. Explore existing codebase patterns

      ## Output
      Write your recommendations to `design-brief-[STORY_ID].md`:
      - Recommended approach
      - Existing patterns to reuse
      - Accessibility considerations (if UI)
      - Component/architecture structure
      - Risks and gotchas
```

**Agent type mapping:**

| Team Role | subagent_type |
|-----------|--------------|
| UX Researcher | `UX Researcher` |
| UI Designer | `UI Designer` |
| Senior Developer | `Senior Developer` |
| Frontend Developer | `Frontend Developer` |
| Backend Architect | `Backend Architect` |
| DevOps Automator | `DevOps Automator` |
| API Tester | `API Tester` |
| Code Reviewer | `Reality Checker` |

#### Phase 2: IMPLEMENT

Spawn implementation agents from `team.implement`:

- **Single agent** (most cases): spawn directly
- **Multiple agents** (fullstack): spawn sequentially -- backend first, then frontend

```
Agent tool:
  model: [story.models.implement or "sonnet"]
  subagent_type: "Senior Developer"  # or appropriate type
  description: "Implement [STORY_ID]"
  prompt: |
    You are implementing story [STORY_ID]: [TITLE]

    ## Context Files
    1. Read `prd.json` for acceptance criteria
    2. Read `progress.txt` for patterns
    3. Read `design-brief-[STORY_ID].md` if exists - FOLLOW these recommendations
    4. Read `AGENTS.md` if exists

    ## Acceptance Criteria
    [LIST FROM prd.json]

    ## Workflow
    1. Explore relevant code
    2. Follow design brief if available
    3. Implement (minimal, focused changes)
    4. Run quality checks: typecheck, lint, tests
    5. For UI: verify in browser
    6. Update progress.txt with learnings
    7. Update prd.json — set this story's passes: true
    8. Delete temporary review-*.md, design-brief-*.md, and retry-diff-*.md files if present
    9. Stage code + progress.txt + prd.json and create ONE commit

    ## Commit message rules (STRICT)
    - Format: `feat: <imperative>` or `fix: <imperative>` — subject only, no body
    - NO story numbers (never `feat: US-011 ...`, never `feat(US-011): ...`)
    - NO parenthetical scope prefixes (never `feat(api): ...`)
    - ONE commit bundling code + progress.txt + prd.json — never a separate `chore:` commit for prd.json/progress.txt
    - No Claude as author/co-author

    ## Rules
    - ONLY changes needed for this story
    - Follow existing patterns
    - All quality checks must pass
```

#### Phase 3: REVIEW

Spawn review agent(s) from `team.review`:

```
Agent tool:
  model: [story.models.review or "opus"]
  subagent_type: "Reality Checker"
  description: "Review [STORY_ID]"
  prompt: |
    You are reviewing story [STORY_ID]: [TITLE]

    ## Review Steps
    1. Read `prd.json` for acceptance criteria
    2. Read `design-brief-[STORY_ID].md` if exists
    3. Run `git diff HEAD~1` to see changes
    4. Read modified files
    5. Run quality checks (typecheck, lint, tests)

    ## Checklist
    - All acceptance criteria met
    - Code follows existing patterns
    - Design brief followed (if applicable)
    - No unnecessary scope creep
    - Quality checks pass

    ## Output
    Write to `review-[STORY_ID].md`:
    - Result: APPROVED or NEEDS_CHANGES
    - Per-criterion pass/fail
    - Issues found (if any)
    - Fix suggestions (if NEEDS_CHANGES)
```

### 4. Handle Review Result

- **APPROVED**: Proceed to finalize.
- **NEEDS_CHANGES**: Re-run Phase 2 with **both** the review feedback AND the rejected diff (max 2 retries). Without the prior diff the retry agent re-derives its previous attempt from scratch and tends to reproduce the same class of mistake.

**Before spawning the retry agent, capture the rejected attempt as a diff file:**

```bash
# Phase 2 produced one commit at HEAD. Snapshot it so the retry implementer
# can see what was tried without having to mentally reverse-engineer it.
git show HEAD > retry-diff-[STORY_ID].md
```

Leave the rejected commit in place. The retry implementer will build on top of it and then **amend** the commit so the story still lands as a single commit.

**Retry prompt additions** (append to the normal Phase 2 implementer prompt):

```
## Retry context (attempt [N+1] of 3)

The previous attempt landed as commit HEAD and was reviewed and REJECTED.
Read both files before coding:

1. `review-[STORY_ID].md` — the reviewer's findings. Every NEEDS_CHANGES item
   must be addressed.
2. `retry-diff-[STORY_ID].md` — the rejected diff. Use it to understand what
   the prior attempt tried so you don't repeat the same mistakes. Keep the
   parts the reviewer did NOT flag.

## Retry workflow
1. Read both files above.
2. Make fixes in the working tree (edits, new tests, etc.) — the rejected
   commit is already applied, so you're editing on top of it.
3. Run quality checks: typecheck, lint, tests.
4. Delete `retry-diff-[STORY_ID].md`, `review-[STORY_ID].md`, and any
   `design-brief-*.md` before staging.
5. Stage your fixes alongside the existing story changes.
6. Amend the existing commit: `git commit --amend --no-edit` (or edit the
   subject only if the story scope genuinely shifted). This keeps the story
   at ONE commit — never create a separate `fix review feedback` commit.
```

After 2 failed review cycles (3 total implement attempts), stop and report the blocker to the orchestrator. Do not loop indefinitely.

### 5. Finalize

```bash
# Update prd.json
# Set passes: true for this story

# Clean up temporary files
rm -f design-brief-[STORY_ID].md design-brief-[STORY_ID]-*.md review-[STORY_ID].md retry-diff-[STORY_ID].md

# Update progress.txt with learnings
```

### 6. Report Back

```
## Story [ID] Complete

### Team
- Design: [agents used or "skipped"]
- Implement: [agents used]
- Review: [agents used]
- Review cycles: [1 or 2]

### Implementation Summary
[What was done]

### Files Modified
- file1.ts
- file2.ts

### Quality Checks
- Typecheck: PASS
- Lint: PASS
- Tests: PASS

### Success: true
```

## Rules

### DO
- Read story's `type` and `team` before starting
- Spawn the right specialized agents for each phase
- Run design phase BEFORE implementation for frontend/fullstack
- Always run review phase
- Pass design briefs to implementation agents
- Pass review feedback AND the rejected diff (`retry-diff-[STORY_ID].md`) on retries
- Amend the story commit on retry — one commit per story, even after review cycles
- Clean up temporary files after success
- Document learnings in progress.txt

### DON'T
- Implement directly without spawning the team (use agents)
- Skip the review phase
- Retry more than 2 times on review rejection
- Retry an implementer with only the review feedback — always include the prior diff too
- Create a second commit to address review feedback (amend instead)
- Spawn design agents for backend/infra/data stories
- Leave design-brief-*.md, review-*.md, or retry-diff-*.md files after completion

## Standalone Mode

When run manually (not via ralph-agent):
1. Read prd.json yourself
2. Pick the highest-priority incomplete story
3. Act as team lead: spawn agents per the story's team config
4. Follow the full phase workflow above
5. Update prd.json when done

## Integration with Orchestrator

When spawned by ralph-agent:
- You receive story ID and criteria in the prompt
- The orchestrator may have already run design phase -- check for `design-brief-*.md`
- If design brief exists, skip Phase 1 and go straight to Phase 2
- Return success/failure status
- Orchestrator handles what's next
