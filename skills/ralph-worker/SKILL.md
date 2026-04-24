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

Spawn design agents **in parallel** using the Agent tool. Each agent writes to its **own** file — never a shared one — so parallel writes can't race or overwrite each other.

**Filename convention:** `design-brief-[STORY_ID]-[ROLE_SLUG].md`, where `ROLE_SLUG` is the role lowercased with spaces replaced by dashes (e.g., `UX Researcher` → `ux-researcher`, `UI Designer` → `ui-designer`, `Backend Architect` → `backend-architect`).

```
For each agent in team.design:
  Compute role_slug = lowercase(role).replace(" ", "-")
  brief_file = "design-brief-[STORY_ID]-[role_slug].md"

  Agent tool:
    model: [story.models.design or "opus"]
    subagent_type: [agent type - see mapping below]
    description: "Design [STORY_ID] ([role])"
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
      Write your recommendations to `[brief_file]` (this is YOUR file — do NOT
      write to any other design-brief-*.md file, and do NOT append to a shared
      file). Use the Write tool to create it fresh:
      - Recommended approach
      - Existing patterns to reuse
      - Accessibility considerations (if UI)
      - Component/architecture structure
      - Risks and gotchas
```

Spawn all design agents in a single Agent-tool call batch so they run concurrently. Because each agent owns a distinct file, parallel execution is safe.

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
  # Attempts 1 and 2 use the configured model. Attempt 3 (second retry) escalates
  # to "opus" — see the model escalation table in section 4 below.
  model: [story.models.implement or "sonnet", or "opus" on retry #2]
  subagent_type: "Senior Developer"  # or appropriate type
  description: "Implement [STORY_ID]"
  prompt: |
    You are implementing story [STORY_ID]: [TITLE]

    ## Context Files
    1. Read `prd.json` for acceptance criteria
    2. Read `progress.txt` for patterns
    3. Read EVERY `design-brief-[STORY_ID]-*.md` file (one per design agent).
       FOLLOW all recommendations across them; reconcile conflicts by picking
       the stricter constraint (e.g., tighter a11y, narrower component scope).
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
    7. Compact progress.txt if it's grown past the threshold — deterministic,
       zero-token. Runs every iteration; no-op unless the file exceeds 50 KB:
       `bash ~/.claude/skills/ralph-worker/compact-progress.sh progress.txt archive`
       If it archived anything, stage both the slimmer `progress.txt` AND the new
       file under `archive/` so the commit reflects the compacted state.
    8. Update prd.json — set this story's passes: true
    9. Delete temporary review-*.md, design-brief-*.md, and retry-diff-*.md files if present
    10. Stage code + progress.txt + prd.json (+ any archived progress file) and create ONE commit
    11. Capture the story commit SHA for the reviewer:
        `git rev-parse HEAD > .ralph-commit-[STORY_ID]`
        This handoff file lets the reviewer use `git show <sha>` instead of the
        fragile `git diff HEAD~1`, which would show the wrong thing if anything
        else landed (a concurrent worktree, a retry amend that half-failed, etc.).


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
    2. Read EVERY `design-brief-[STORY_ID]-*.md` file (one per design agent)
    3. Read the story commit SHA from `.ralph-commit-[STORY_ID]`.
       Inspect the diff with: `git show $(cat .ralph-commit-[STORY_ID])`
       (Do NOT use `git diff HEAD~1` — it can show the wrong diff if anything
       else landed between implementation and review, e.g. a concurrent worktree
       session, a retry amend that half-failed, or manual cleanup.)
       Fallback if the handoff file is missing: use `git show HEAD`.
    4. Read modified files
    5. Run quality checks. Typecheck, lint, and the **FULL project test suite**
       (not just the tests introduced by this story). Examples: `npm test`,
       `pytest`, `go test ./...`, `cargo test`, etc. The point is to catch
       regressions — if this story broke a test added by an earlier story,
       that is NEEDS_CHANGES, not a pre-existing failure to ignore.
    6. If a test that was passing on the prior story commit now fails, note
       which prior story likely owns it (grep for story id in `progress.txt`
       or commit log) and include that in the findings.

    ## Checklist
    - All acceptance criteria met
    - Code follows existing patterns
    - Design brief followed (if applicable)
    - No unnecessary scope creep
    - Typecheck + lint pass
    - Full test suite passes — including tests from prior stories
    - No regressions introduced (prior-story tests still pass)

    ## Output
    Write to `review-[STORY_ID].md`:
    - Result: APPROVED or NEEDS_CHANGES
    - Per-criterion pass/fail
    - Issues found (if any) — distinguish story-local issues from REGRESSIONS
      of prior-story behavior
    - Fix suggestions (if NEEDS_CHANGES)
```

### 4. Handle Review Result

- **APPROVED**: Proceed to finalize.
- **NEEDS_CHANGES**: Re-run Phase 2 with **both** the review feedback AND the rejected diff (max 2 retries). Without the prior diff the retry agent re-derives its previous attempt from scratch and tends to reproduce the same class of mistake.

**Model escalation across attempts:**

| Attempt | Model for `team.implement` |
|---------|----------------------------|
| 1 (initial)  | `story.models.implement` (as configured — typically `sonnet`) |
| 2 (retry #1) | Same as attempt 1 — give the original model a second shot with the review + prior diff in context |
| 3 (retry #2, last) | **Escalate to `opus`** unless `story.models.implement` is already `opus`. Haiku → opus, sonnet → opus, opus → opus. |

Rationale: if retry #1 with the same model and full feedback still failed review, the implementer likely needs more reasoning capacity. The last attempt before declaring a blocker is the right place to spend the extra tokens. Escalating earlier wastes money on cases where the original model would have passed on retry #1.

**Before spawning the retry agent, capture the rejected attempt as a diff file:**

```bash
# Phase 2 produced one commit whose SHA is in .ralph-commit-[STORY_ID].
# Snapshot the rejected diff for the retry implementer.
git show "$(cat .ralph-commit-[STORY_ID])" > retry-diff-[STORY_ID].md
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
   `design-brief-[STORY_ID]-*.md` before staging.
5. Stage your fixes alongside the existing story changes.
6. Amend the existing commit: `git commit --amend --no-edit` (or edit the
   subject only if the story scope genuinely shifted). This keeps the story
   at ONE commit — never create a separate `fix review feedback` commit.
7. Refresh the commit SHA handoff since amend rewrites the commit:
   `git rev-parse HEAD > .ralph-commit-[STORY_ID]`
```

After 2 failed review cycles (3 total implement attempts), stop and write a **blocker state file**. Do not loop indefinitely, and do not spawn a fourth attempt.

### 4b. Write the blocker state file

When the retry cap is reached, write `.ralph-blocker.md` in the working directory. This file is the handoff back to the human — a single place that says what failed and how to unblock it. The outer loop entry points (`ralph.sh`, `/ralph-loop`'s stop hook, `/ralph-agent`) all detect this file on startup and refuse to keep iterating until it's resolved.

**Do NOT delete `review-[STORY_ID].md` or `retry-diff-[STORY_ID].md` in the blocker case.** The user needs them for intervention.

**Format (write verbatim, substituting bracketed fields):**

~~~markdown
---
story_id: [STORY_ID]
story_title: [TITLE]
blocked_at: [ISO 8601 timestamp]
attempts: 3
last_model: [model used on retry #2]
---

# Blocker: [STORY_ID] — [TITLE]

Ralph attempted this story 3 times (initial + 2 retries) and the reviewer rejected each one. The loop has stopped so you can intervene.

## Last review verdict

[paste the full contents of review-[STORY_ID].md here, verbatim, inside a fenced block]

## Rejected diff

[paste the full contents of retry-diff-[STORY_ID].md here, verbatim, inside a fenced block]

## How to unblock

Pick one, then delete this file (`.ralph-blocker.md`) and re-run the loop:

1. **Rewrite the story.** Edit `prd.json` — change the acceptance criteria, description, or team for [STORY_ID] to make the intent clearer. Then delete this file and re-run.
2. **Split the story.** If it's too big, break it into [STORY_ID]a / [STORY_ID]b with proper `depends_on` arrays. Delete this file, run `/ralph-validate` to confirm structure, re-run.
3. **Fix manually.** Implement the story yourself in your editor, run your own quality checks, set `passes: true` for [STORY_ID] in `prd.json`, and commit. The loop will auto-clean this file on the next run once the story shows `passes: true`.
4. **Skip.** Set `passes: true` in `prd.json` without implementing. Delete this file. The loop moves on; nothing else enforces that the story is actually done.

## Reference files left on disk
- `review-[STORY_ID].md` — the last reviewer's full verdict
- `retry-diff-[STORY_ID].md` — the last rejected diff
- `.ralph-commit-[STORY_ID]` — SHA of the last rejected commit (inspect with `git show $(cat .ralph-commit-[STORY_ID])`)
- Any `design-brief-[STORY_ID]-*.md` files from the design phase

These are not deleted automatically so you can re-read them independently.
~~~

After writing `.ralph-blocker.md`, report back to the orchestrator with the blocker status (see section 6) and return. Do not mark the story `passes: true`. Do not attempt a fourth implementation.

### 5. Finalize

```bash
# Update prd.json
# Set passes: true for this story

# Clean up temporary files
rm -f design-brief-[STORY_ID]-*.md review-[STORY_ID].md retry-diff-[STORY_ID].md .ralph-commit-[STORY_ID]

# Record per-story metrics (no-op token cost; updates .ralph-metrics.json).
# Not committed to git by default — this is local analytics. Add .ralph-metrics.json
# to .gitignore if you don't want it surface in git status.
bash ~/.claude/skills/ralph-worker/update-metrics.sh \
  "[STORY_ID]" \
  "[REVIEW_CYCLES: 1, 2, or 3]" \
  "[MODEL_IMPLEMENT: sonnet/opus/haiku, final attempt's model]" \
  "$(cat .ralph-commit-[STORY_ID] 2>/dev/null || git rev-parse HEAD)" 2>&1 || true

# Update progress.txt with learnings
```

### 6. Report Back

On success:

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

On blocker (retry cap reached):

```
## Story [ID] BLOCKED

3 attempts, all rejected by review. Blocker state written to `.ralph-blocker.md`.
The loop will halt until the blocker is resolved. See `.ralph-blocker.md` for
details and intervention options.

### Success: false
### Blocker: true
```

## Rules

### DO
- Read story's `type` and `team` before starting
- Spawn the right specialized agents for each phase
- Run design phase BEFORE implementation for frontend/fullstack
- Always run review phase
- Pass design briefs to implementation agents
- Pass review feedback AND the rejected diff (`retry-diff-[STORY_ID].md`) on retries
- Escalate the implement model to `opus` on the last retry (retry #2) unless it's already `opus`
- Amend the story commit on retry — one commit per story, even after review cycles
- Run the FULL test suite in the review phase — catches regressions from prior stories, not just story-local pass/fail
- Clean up temporary files after success
- Document learnings in progress.txt
- Write `.ralph-blocker.md` and preserve review/retry-diff files when the retry cap is reached

### DON'T
- Implement directly without spawning the team (use agents)
- Skip the review phase
- Retry more than 2 times on review rejection
- Retry an implementer with only the review feedback — always include the prior diff too
- Create a second commit to address review feedback (amend instead)
- Spawn design agents for backend/infra/data stories
- Leave design-brief-*.md, review-*.md, retry-diff-*.md, or .ralph-commit-* files after a successful completion
- Point the reviewer at `git diff HEAD~1` — always pass the SHA via `.ralph-commit-[STORY_ID]`
- Delete `review-[STORY_ID].md` or `retry-diff-[STORY_ID].md` when writing a blocker — the user needs them
- Mark a story `passes: true` when writing a blocker — the whole point is that it did NOT pass
- Let the reviewer run only the new story's tests — regressions in prior stories count as NEEDS_CHANGES

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
- The orchestrator may have already run design phase -- check for `design-brief-[STORY_ID]-*.md` files
- If design brief exists, skip Phase 1 and go straight to Phase 2
- Return success/failure status
- Orchestrator handles what's next
