---
name: ralph-prd
description: Generates detailed PRDs through interactive questions, then converts to prd.json for autonomous agent execution. Single command that replaces the old ralph-prd + ralph-convert workflow.
---

# PRD Generator (Ralph Style)

Generate comprehensive Product Requirements Documents optimized for autonomous agent implementation.

## Model Recommendation

ralph-prd runs in your current session. For the highest-quality PRD, use `/model opus` before running this skill — Opus is better at reasoning, planning, and structured output. Sonnet works too, just with lighter analysis.

## Workflow

### Step 1: Clarification Questions

Use the `AskUserQuestion` tool to ask interactive clarifying questions. This renders selectable option cards in the CLI UI instead of requiring text-formatted answers.

**Rules:**
- Ask up to 4 questions per `AskUserQuestion` call (tool limit)
- Each question must have 2-4 options (an "Other" free-text option is added automatically)
- If you need more than 4 questions, make a second `AskUserQuestion` call after receiving the first answers
- Use `multiSelect: true` when choices aren't mutually exclusive
- Keep `header` short (max 12 chars) — e.g. "Problem", "Scope", "Users", "Stack"
- Tailor options to the user's specific request — don't use generic placeholders

**Focus questions on:**
- Core problem/goal
- Essential functionality (MVP scope)
- Target users/personas
- Success criteria
- Technical constraints

**Example:**

```
AskUserQuestion({
  questions: [
    {
      question: "What is the core problem this feature solves?",
      header: "Problem",
      multiSelect: false,
      options: [
        { label: "New capability", description: "Users can't do this today" },
        { label: "Performance", description: "Existing flow is too slow" },
        { label: "UX improvement", description: "Current flow is confusing" }
      ]
    },
    {
      question: "Who are the target users?",
      header: "Users",
      multiSelect: true,
      options: [
        { label: "End users", description: "Direct product users" },
        { label: "Admins", description: "Internal admin/ops team" },
        { label: "API consumers", description: "Third-party integrations" }
      ]
    },
    {
      question: "What is the MVP scope?",
      header: "Scope",
      multiSelect: false,
      options: [
        { label: "Minimal", description: "Single core flow, no edge cases" },
        { label: "Standard", description: "Core flow + basic error handling" },
        { label: "Complete", description: "Full feature with all variations" }
      ]
    }
  ]
})
```

### Step 2: Generate PRD

After receiving answers, create a PRD with this structure:

```markdown
# PRD: [Feature Name]

## Introduction
[2-3 sentences: what this feature does and why it matters]

## Goals
1. [Primary goal]
2. [Secondary goal]
...

## User Stories

### US-001: [Title]
**As a** [user type], **I want** [action] **so that** [benefit].

**Acceptance Criteria:**
- [ ] [Specific, verifiable criterion]
- [ ] [Specific, verifiable criterion]
- [ ] Typecheck passes
- [ ] Tests pass

### US-002: [Title]
...

## Functional Requirements
1. [Requirement 1]
2. [Requirement 2]
...

## Non-Goals (Out of Scope)
- [What this feature explicitly does NOT include]

## Design & Technical Considerations
- [Architecture decisions]
- [Dependencies]
- [Migration needs]

## Success Metrics
- [How to measure success]

## Open Questions
- [Unresolved questions for later]
```

### Step 3: Save PRD

Save the markdown PRD to: `tasks/prd-[feature-name].md`

### Step 4: Convert to prd.json

Immediately after saving the markdown PRD, convert it to `prd.json` for ralph-agent execution. Do NOT ask the user to run ralph-convert separately.

**prd.json format:**

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

**Conversion rules:**

1. **Story sizing** — Each story must be completable in ONE focused session. If a story is too large (e.g. "build entire dashboard"), split it into smaller stories.

2. **Team assignment by type:**

| Type | design | implement | review |
|------|--------|-----------|--------|
| `backend` | [] | ["Senior Developer"] | ["Code Reviewer"] |
| `frontend` | ["UX Researcher", "UI Designer"] | ["Senior Developer"] | ["Code Reviewer"] |
| `fullstack` | ["UX Researcher"] | ["Backend Architect", "Frontend Developer"] | ["Code Reviewer"] |
| `infra` | [] | ["DevOps Automator", "Senior Developer"] | ["Code Reviewer"] |
| `data` | [] | ["Backend Architect"] | ["API Tester", "Code Reviewer"] |

3. **Model assignment** — Every story gets a `models` object specifying which Claude model to use per phase. Apply defaults based on story type:

   | Phase | Default Model | Rationale |
   |-------|--------------|-----------|
   | design | `opus` | Reasoning-heavy: UX analysis, architecture decisions |
   | implement | `sonnet` | Code generation: fast and cost-effective |
   | review | `opus` | Reasoning-heavy: evaluating correctness against criteria |

   Backend/infra/data stories have no design phase — omit or leave `design: "opus"` for consistency. Users can override per-story by changing the values to `"opus"`, `"sonnet"`, or `"haiku"`.

4. **Dependency ordering** — Assign priority numbers so dependencies flow low→high:
   - Schema/database changes first
   - Backend/API logic second
   - UI components third
   - Integration/summary views last

4. **Required criteria** — Every story must include "Typecheck passes". UI stories must also include "Verify in browser".

5. **Archive previous prd.json** — If prd.json already exists, move it to `archive/prd-[branch]-[timestamp].json` before creating the new one.

**Validation checklist before saving prd.json:**
- [ ] All stories are right-sized (one session each)
- [ ] Dependencies flow from low to high priority
- [ ] Every story has "Typecheck passes"
- [ ] UI stories have "Verify in browser"
- [ ] No vague acceptance criteria
- [ ] Branch name follows convention
- [ ] Every story has a valid `type` and `team` object
- [ ] Every story has a `models` object with `design`, `implement`, and `review` keys

## User Story Requirements

**Every user story MUST have:**
- A descriptive title
- "As a [user], I want [feature] so that [benefit]" format
- 3-5 **verifiable** acceptance criteria
- "Typecheck passes" as a criterion
- For UI changes: "Verify in browser" criterion
- A **story type** classification (see below)

**Story Type Classification:**

Every story must be tagged with a type that determines which team of agents will work on it:

| Type | When to Use | Team Spawned |
|------|------------|--------------|
| `backend` | DB migrations, API endpoints, server logic, services | Senior Developer + Code Reviewer |
| `frontend` | UI components, pages, styling, interactions | UX Researcher + UI Designer + Senior Developer + Code Reviewer |
| `fullstack` | Stories touching both frontend and backend | Backend Architect + Frontend Developer + Code Reviewer |
| `infra` | CI/CD, config, deployment, environment setup | DevOps Automator + Senior Developer |
| `data` | Data pipelines, integrations, external APIs | Backend Architect + API Tester |

Mark the type in each story heading:

```markdown
### US-001: Add status column to tasks table [backend]
...

### US-003: Create TaskStatusBadge component [frontend]
...
```

**Acceptance Criteria Rules:**
- Be explicit and unambiguous
- Avoid vague language: "works correctly", "good UX", "properly handles"
- Use concrete statements: "Returns 404 when resource not found"
- Write for a junior developer or AI agent to implement

**Story Sizing:**
- Each story should be completable in ONE focused session
- If a story feels large, split it
- Good size: add a column, create a component, update an endpoint
- Too large: "build entire dashboard", "implement full auth system"

## Quality Checklist

Before finalizing, verify:
- [ ] Asked clarifying questions using AskUserQuestion tool
- [ ] Incorporated user answers into PRD
- [ ] Each story is appropriately scoped (not too large)
- [ ] All requirements are numbered
- [ ] Non-goals clearly define boundaries
- [ ] PRD saved to tasks/ directory
- [ ] prd.json generated with correct team assignments and dependency ordering
- [ ] Previous prd.json archived if it existed

## Example Sizing

**Right-sized stories (with types):**
- Add `status` column to tasks table → `[backend]`
- Create TaskStatusBadge component → `[frontend]`
- Add status filter to task list API → `[backend]`
- Display status badge in task list → `[frontend]`
- Add status endpoint + UI toggle → `[fullstack]`

**Too large (needs splitting):**
- Implement task status feature (includes all of the above)

## Notes

- This skill generates the PRD and converts to prd.json in one step — no need to run ralph-convert separately
- ralph-convert still exists standalone for re-converting manually edited PRDs
- PRDs are designed for use with ralph-agent skill
- Story types enable multi-agent teams: each type spawns specialized agents for design, implementation, and review
