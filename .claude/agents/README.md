# Bundled Agents

This directory bundles the exact subagent definitions that Ralph's skills (`ralph-agent`, `ralph-worker`, `ralph-loop`) invoke via the Agent tool. These files are copied into `~/.claude/agents/` by the install step in the repo root README, so Ralph works out of the box for any project on your machine after a one-time install.

## Provenance

All agent files in this directory are copied verbatim from **[msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents)** (MIT License), a community-curated library of role-based subagent definitions.

The full library contains many more agents than Ralph needs. Only the eight Ralph actually spawns are bundled here to keep the footprint small.

## Bundled agents

| File | `subagent_type` name | Used by Ralph for |
|------|----------------------|-------------------|
| `engineering/engineering-senior-developer.md` | `Senior Developer` | `team.implement` default |
| `engineering/engineering-backend-architect.md` | `Backend Architect` | backend design + fullstack implement |
| `engineering/engineering-devops-automator.md` | `DevOps Automator` | infra stories |
| `engineering/engineering-frontend-developer.md` | `Frontend Developer` | fullstack implement |
| `design/design-ux-researcher.md` | `UX Researcher` | frontend/fullstack design phase |
| `design/design-ui-designer.md` | `UI Designer` | frontend design phase |
| `testing/testing-api-tester.md` | `API Tester` | API stories |
| `testing/testing-reality-checker.md` | `Reality Checker` | Code Reviewer in every team |

## Refreshing

To pull newer versions from upstream:

```bash
BASE="https://raw.githubusercontent.com/msitarzewski/agency-agents/main"
for f in \
  "engineering/engineering-senior-developer.md" \
  "engineering/engineering-backend-architect.md" \
  "engineering/engineering-devops-automator.md" \
  "engineering/engineering-frontend-developer.md" \
  "design/design-ux-researcher.md" \
  "design/design-ui-designer.md" \
  "testing/testing-api-tester.md" \
  "testing/testing-reality-checker.md" \
  "LICENSE"
do
  curl -sfL "$BASE/$f" -o ".claude/agents/$f"
done
```

## Customizing

The install step uses `cp -rn` (no-clobber), so if you already have an agent with the same filename in `~/.claude/agents/`, the bundled version won't overwrite it. If you want your own version of `Senior Developer` (or any of the bundled roles), put it at `~/.claude/agents/engineering/engineering-senior-developer.md` before running the install command, or simply don't install the corresponding file.

## License

See `LICENSE` in this directory — MIT, copyright AgentLand Contributors. Attribution preserved.