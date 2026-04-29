#!/bin/bash
#
# Ralph Loop Setup
# Creates the state file the Stop hook reads and registers the hook in
# this project's .claude/settings.local.json.
#
# Usage:
#   setup-ralph-loop.sh [--max-iterations N] [--prd-file PATH]
#
# After setup, simply finish your turn — the Stop hook will pick the next
# incomplete story from prd.json and re-prompt you automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/stop-hook.sh"

MAX_ITERATIONS=0
PRD_FILE="prd.json"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Loop - Stop-hook driven story iterator

USAGE:
  /ralph-loop [OPTIONS]

OPTIONS:
  --max-iterations <n>    Stop after N iterations (default: 0 = unlimited)
  --prd-file <path>       Path to prd.json (default: ./prd.json)
  -h, --help              Show this help

DESCRIPTION:
  Activates a Stop hook in this project's .claude/settings.local.json.
  Whenever the assistant tries to end its turn, the hook:
    1. Reads prd.json
    2. Picks the next story where passes: false
    3. Re-injects a ralph-worker prompt scoped to that story

  Each iteration spawns the right team (designers / developers / reviewers)
  per the story's team config. The loop ends when:
    - All stories have passes: true, OR
    - --max-iterations is reached, OR
    - The assistant outputs <promise>RALPH-COMPLETE</promise> AND prd.json
      confirms every story is passing.

  To stop manually: run /cancel-ralph

PREREQUISITES:
  - prd.json must exist (run /ralph-prd first)
  - jq and perl must be installed
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        echo "❌ --max-iterations needs a non-negative integer" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --prd-file)
      if [[ -z "${2:-}" ]]; then
        echo "❌ --prd-file needs a path" >&2
        exit 1
      fi
      PRD_FILE="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      echo "   Try: /ralph-loop --help" >&2
      exit 1
      ;;
  esac
done

# Validate prerequisites
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not found. Install jq first." >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "❌ perl not found. Install perl first." >&2
  exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "❌ $PRD_FILE not found." >&2
  echo "   Run /ralph-prd first to generate it." >&2
  exit 1
fi

if [[ ! -x "$HOOK_PATH" ]]; then
  chmod +x "$HOOK_PATH" 2>/dev/null || true
fi

if [[ ! -f "$HOOK_PATH" ]]; then
  echo "❌ Hook script missing at: $HOOK_PATH" >&2
  exit 1
fi

mkdir -p .claude

# --- write state file ---------------------------------------------------------

STATE_FILE=".claude/ralph-loop.local.md"
INJECTED_FILE=".claude/ralph-loop.last-injected"

# Fresh activation: drop any stale re-injection counter from a previous loop.
rm -f "$INJECTED_FILE"
cat > "$STATE_FILE" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
prd_file: "$PRD_FILE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

Ralph loop is active. The Stop hook reads prd.json and re-prompts the
assistant for each incomplete story until all stories pass or the iteration
cap is hit. To stop early: run /cancel-ralph.
EOF

# --- register hook in project settings.local.json -----------------------------

SETTINGS_FILE=".claude/settings.local.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Idempotent: only add the hook if not already pointing at our script
TMP="${SETTINGS_FILE}.tmp.$$"
jq \
  --arg cmd "$HOOK_PATH" \
  '
    .hooks //= {} |
    .hooks.Stop //= [] |
    if any(.hooks.Stop[]?; (.hooks // [])[]?.command == $cmd)
    then .
    else .hooks.Stop += [{
      "hooks": [{
        "type": "command",
        "command": $cmd
      }]
    }]
    end
  ' "$SETTINGS_FILE" > "$TMP"
mv "$TMP" "$SETTINGS_FILE"

# --- summary ------------------------------------------------------------------

TOTAL=$(jq '.stories | length' "$PRD_FILE")
DONE=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE")
NEXT_STORY=$(jq -r '
  .stories as $all
  | $all
  | map(select(
      (.passes == false or .passes == null)
      and (
        (.depends_on // [])
        | all(. as $id | $all | any(.id == $id and .passes == true))
      )
    ))
  | sort_by(.priority // 999)
  | first
  | if . == null then "(none — all stories already pass or deps blocked)" else "\(.id): \(.title)" end
' "$PRD_FILE" 2>/dev/null || echo "(none — all stories already pass)")

BLOCKER_WARNING=""
if [[ -f ".ralph-blocker.md" ]]; then
  BLOCKER_STORY=$(sed -n 's/^story_id: *//p' ".ralph-blocker.md" | head -1 | tr -d '[:space:]')
  BLOCKER_WARNING="
⚠️  Blocker present: .ralph-blocker.md (story ${BLOCKER_STORY:-unknown})
    The Stop hook will halt on the first iteration until you resolve this.
    See .ralph-blocker.md for the review verdict and unblock instructions."
fi

cat <<EOF
🔄 Ralph loop activated for this project.

State file:    $STATE_FILE
Hook script:   $HOOK_PATH
Settings:      $SETTINGS_FILE
PRD file:      $PRD_FILE
Stories:       $DONE / $TOTAL passing
Next story:    $NEXT_STORY
Max iterations: $([ $MAX_ITERATIONS -gt 0 ] && echo $MAX_ITERATIONS || echo "unlimited")$BLOCKER_WARNING

The Stop hook is now active. When you finish your turn, the hook will
pick the next incomplete story and re-prompt you to handle it via the
ralph-worker skill. The loop ends naturally when prd.json shows all
stories with passes: true.

To stop early: /cancel-ralph
To monitor:   head -10 $STATE_FILE
EOF
