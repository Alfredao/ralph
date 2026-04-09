---
name: ralph-convert
description: Converts markdown PRDs into structured prd.json format for autonomous agent execution. Ensures stories are properly sized and ordered by dependencies.
---

# PRD to JSON Converter (Ralph Style)

Convert markdown PRDs into `prd.json` format for ralph-agent execution.

## Purpose

Transform PRD documents into structured JSON that ralph-agent can execute iteratively, with each user story sized to complete in a single focused session.

## Output Format

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

## Conversion Rules

### 1. Story Sizing (Critical)

**The fundamental rule:** Each story must be completable in ONE focused session.

**Right-sized examples:**
- Add a database column with migration
- Create a single UI component
- Update server endpoint logic
- Add a utility function with tests

**Too large (must split):**
- "Build entire dashboard"
- "Implement full authentication"
- "Create complete CRUD operations"

**Splitting guidance:**
- If you can't describe it in 2-3 sentences, it's too big
- If it touches more than 2-3 files, consider splitting
- Each story = one logical unit of work

### 2. Story Type Classification & Team Assignment

Auto-classify each story and assign the appropriate agent team. If the PRD already has `[type]` tags, use those. Otherwise, infer from keywords and scope.

**Classification rules:**

| Type | Signals | Team |
|------|---------|------|
| `backend` | DB, migration, API, endpoint, service, model, controller, queue, cron | design: [] / implement: ["Senior Developer"] / review: ["Code Reviewer"] |
| `frontend` | component, page, UI, form, modal, layout, styling, animation, UX | design: ["UX Researcher", "UI Designer"] / implement: ["Senior Developer"] / review: ["Code Reviewer"] |
| `fullstack` | touches both API + UI, form submission with API, CRUD with views | design: ["UX Researcher"] / implement: ["Backend Architect", "Frontend Developer"] / review: ["Code Reviewer"] |
| `infra` | CI/CD, Docker, deploy, config, env, pipeline, monitoring | design: [] / implement: ["DevOps Automator", "Senior Developer"] / review: ["Code Reviewer"] |
| `data` | integration, external API, webhook, import/export, pipeline, ETL | design: [] / implement: ["Backend Architect"] / review: ["API Tester", "Code Reviewer"] |

**Phase rules:**
- `design` phase is **only** for `frontend` and `fullstack` types. Skip for backend/infra/data.
- `implement` phase is **always** present.
- `review` phase is **always** present.

**Team can be customized:** The user may override team assignments in the PRD. Respect any explicit overrides.

### 3. Dependency Ordering

Stories execute sequentially by priority number. Earlier stories CANNOT depend on later ones.

**Recommended ordering:**
1. Schema/database changes first
2. Backend/API logic second
3. UI components third
4. Integration/summary views last

**Example:**
```
Priority 1: Add status column to database
Priority 2: Add status to API response
Priority 3: Create StatusBadge component
Priority 4: Display StatusBadge in task list
```

### 3. Acceptance Criteria

Every criterion must be **verifiable**, not vague.

**Good criteria:**
- "Add `status` column with default value 'pending'"
- "API returns 404 when resource not found"
- "Component renders loading state while fetching"
- "Typecheck passes"
- "Tests pass"

**Bad criteria (avoid):**
- "Works correctly"
- "Has good UX"
- "Properly handles errors"
- "Is performant"

### 4. Required Criteria

Every story MUST include:
- "Typecheck passes"

UI-changing stories MUST also include:
- "Verify in browser"

## Workflow

1. **Read the PRD** from `tasks/prd-[feature].md`
2. **Extract user stories** and acceptance criteria
3. **Validate sizing** - split any stories that are too large
4. **Order by dependencies** - assign priority numbers
5. **Generate prd.json** in the project root
6. **Archive previous prd.json** if it exists (move to `archive/` with timestamp)

## Example Conversion

**Input PRD excerpt:**
```markdown
### US-001: Add Task Status
As a user, I want tasks to have a status so I can track progress.

Acceptance Criteria:
- Tasks have status field (pending, in_progress, completed)
- Status displays in task list
- Can filter by status
```

**Output (split into right-sized stories with team assignments):**
```json
{
  "name": "Task Status Feature",
  "branch": "feature/task-status",
  "stories": [
    {
      "id": "US-001",
      "title": "Add status column to tasks table",
      "description": "As a developer, I want a status column in the database so that tasks can track their state.",
      "priority": 1,
      "type": "backend",
      "team": {
        "design": [],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "acceptance_criteria": [
        "Add `status` column to tasks table",
        "Default value is 'pending'",
        "Valid values: pending, in_progress, completed",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Return status in task API",
      "description": "As a frontend developer, I want the API to include status so I can display it.",
      "priority": 2,
      "type": "backend",
      "team": {
        "design": [],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "acceptance_criteria": [
        "GET /tasks returns status field",
        "GET /tasks/:id returns status field",
        "Typecheck passes",
        "Tests pass"
      ],
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Create TaskStatusBadge component",
      "description": "As a user, I want to see task status visually so I can quickly identify state.",
      "priority": 3,
      "type": "frontend",
      "team": {
        "design": ["UX Researcher", "UI Designer"],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "acceptance_criteria": [
        "Component shows colored badge for each status",
        "pending: gray, in_progress: blue, completed: green",
        "Typecheck passes",
        "Verify in browser"
      ],
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "Display status in task list",
      "description": "As a user, I want to see status badges in the task list.",
      "priority": 4,
      "type": "frontend",
      "team": {
        "design": ["UX Researcher", "UI Designer"],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "acceptance_criteria": [
        "TaskStatusBadge displays next to each task",
        "Status updates when task changes",
        "Typecheck passes",
        "Verify in browser"
      ],
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-005",
      "title": "Add status filter to task list",
      "description": "As a user, I want to filter tasks by status so I can focus on specific items.",
      "priority": 5,
      "type": "frontend",
      "team": {
        "design": ["UX Researcher", "UI Designer"],
        "implement": ["Senior Developer"],
        "review": ["Code Reviewer"]
      },
      "acceptance_criteria": [
        "Filter dropdown with status options",
        "Selecting filter shows only matching tasks",
        "Can clear filter to show all",
        "Typecheck passes",
        "Verify in browser"
      ],
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Archive Management

Before creating a new prd.json:
1. Check if prd.json exists
2. If yes, move to `archive/prd-[branch]-[timestamp].json`
3. Create new prd.json

## Validation Checklist

Before saving prd.json:
- [ ] All stories are right-sized (one session each)
- [ ] Dependencies flow from low to high priority
- [ ] Every story has "Typecheck passes"
- [ ] UI stories have "Verify in browser"
- [ ] No vague acceptance criteria
- [ ] Branch name follows convention
- [ ] Every story has a valid `type` (backend/frontend/fullstack/infra/data)
- [ ] Every story has a `team` object with design/implement/review arrays
- [ ] Frontend/fullstack stories have design agents; backend/infra/data do not
