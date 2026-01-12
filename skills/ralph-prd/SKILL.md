---
name: ralph-prd
description: Generates detailed Product Requirements Documents (PRDs) through clarifying questions. Creates structured PRDs with user stories, acceptance criteria, and technical requirements suitable for autonomous implementation.
---

# PRD Generator (Ralph Style)

Generate comprehensive Product Requirements Documents optimized for autonomous agent implementation.

## Workflow

### Step 1: Clarification Questions

Ask 3-5 essential clarifying questions to understand the feature. Use a lettered response format for quick answers:

```
1. What is the core problem/goal?
   A) Option 1
   B) Option 2
   C) Custom answer

2. What functionality is essential?
   A) Option 1
   B) Option 2

(User responds: "1A, 2C: my custom answer")
```

Focus questions on:
- Core problem/goal
- Essential functionality (MVP scope)
- Target users/personas
- Success criteria
- Technical constraints

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

### Step 3: Save Output

Save the PRD to: `tasks/prd-[feature-name].md`

## User Story Requirements

**Every user story MUST have:**
- A descriptive title
- "As a [user], I want [feature] so that [benefit]" format
- 3-5 **verifiable** acceptance criteria
- "Typecheck passes" as a criterion
- For UI changes: "Verify in browser" criterion

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
- [ ] Asked clarifying questions first
- [ ] Incorporated user answers into PRD
- [ ] Each story is appropriately scoped (not too large)
- [ ] All requirements are numbered
- [ ] Non-goals clearly define boundaries
- [ ] PRD saved to tasks/ directory

## Example Sizing

**Right-sized stories:**
- Add `status` column to tasks table
- Create TaskStatusBadge component
- Add status filter to task list API
- Display status badge in task list

**Too large (needs splitting):**
- Implement task status feature (includes all of the above)

## Notes

- This skill creates PRDs only - no implementation
- PRDs are designed for use with ralph-agent skill
- Convert to prd.json using ralph-convert skill before running ralph-agent
