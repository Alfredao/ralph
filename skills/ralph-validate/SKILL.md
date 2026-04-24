---
name: ralph-validate
description: Static validator for prd.json. Checks structure, required fields, dependency consistency, acceptance criteria coverage, and detects cycles. Run before /ralph-agent or /ralph-loop to catch planning-time issues that would otherwise crash the loop mid-iteration.
---

# Ralph Validate - PRD Linter

Runs a static pass over `prd.json` and reports everything wrong in one go. Meant to be invoked before starting the loop, or after hand-editing the PRD.

## Usage

```
/ralph-validate
/ralph-validate path/to/prd.json
```

Invokes `skills/ralph-validate/validate.sh`. Exit `0` on success, `1` on any error. Warnings don't fail the run.

## What it checks

### Structure
- `prd.json` exists and is valid JSON
- Top-level fields present: `name`, `branch`, `stories`
- `.stories` is a non-empty array
- Every story has: `id`, `title`, `description`, `priority`, `acceptance_criteria`, `passes`, `type`, `team`, `models`
- Story ids are unique

### Content
- `type` is one of `backend` / `frontend` / `fullstack` / `infra` / `data`
- `team.implement` and `team.review` each have at least one agent
- `models.{design,implement,review}` values are `opus` / `sonnet` / `haiku` (when present)
- `acceptance_criteria` is a non-empty array
- Every story's acceptance criteria includes "Typecheck passes"
- `frontend` and `fullstack` stories also include "Verify in browser"

### Dependencies
- Every `depends_on` id references an existing story (no dangling refs)
- No self-loops (A depends on A)
- No dependency cycles (A → B → A, or longer)

### Warnings (do not fail)
- `branch` doesn't start with `feature/`, `fix/`, `hotfix/`, or `chore/`

## Why run it

The three execution modes (`ralph.sh`, `/ralph-agent`, `/ralph-loop`) all assume `prd.json` is well-formed. A dangling `depends_on` or a missing `team.implement` array would otherwise surface as a cryptic failure on iteration 12 after you've already burned tokens. Validation up front is cheap.

## Output shape

```
Validating prd.json...

Warnings:
  ⚠ Branch 'main' doesn't start with feature/, fix/, hotfix/, or chore/

Errors:
  ✗ Story US-003: acceptance_criteria must include 'Typecheck passes'
  ✗ Story US-007: depends_on 'US-999' references unknown story
  ✗ Dependency cycle or unreachable nodes: US-004 US-005

✗ Validation failed with 3 error(s)
```

## Requirements

- `jq` on PATH
- Bash 3.2+ (macOS default bash works)
