#!/bin/bash
#
# Ralph Loop Stop Hook
# Blocks session exit while a ralph-loop is active.
# Reads prd.json, finds the next incomplete story, and re-injects a
# story-specific worker prompt so the orchestrator picks the team back up.
#
# State file: .claude/ralph-loop.local.md (YAML frontmatter + optional notes)

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/ralph-loop.local.md"
PROMISE_TAG="RALPH-COMPLETE"

# No active loop: allow normal exit
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# --- parse YAML frontmatter ----------------------------------------------------

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
PRD_FILE=$(echo "$FRONTMATTER" | grep '^prd_file:' | sed 's/prd_file: *//' | sed 's/^"\(.*\)"$/\1/')
PRD_FILE="${PRD_FILE:-prd.json}"

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: state file corrupted (iteration='$ITERATION' max='$MAX_ITERATIONS'). Stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# --- max iterations safety net ------------------------------------------------

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ralph loop: max iterations ($MAX_ITERATIONS) reached. Stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# --- prd.json must exist ------------------------------------------------------

if [[ ! -f "$PRD_FILE" ]]; then
  echo "⚠️  Ralph loop: $PRD_FILE not found. Run /ralph-prd first. Stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# --- check completion promise in last assistant message -----------------------

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty')
LAST_OUTPUT=""

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1 || true)
  if [[ -n "$LAST_LINE" ]]; then
    LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
      .message.content
      | map(select(.type == "text"))
      | map(.text)
      | join("\n")
    ' 2>/dev/null || echo "")
  fi
fi

if [[ -n "$LAST_OUTPUT" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ "$PROMISE_TEXT" = "$PROMISE_TAG" ]]; then
    echo "✅ Ralph loop: <promise>$PROMISE_TAG</promise> detected. Verifying prd.json..." >&2
    REMAINING=$(jq '[.stories[] | select(.passes == false or .passes == null)] | length' "$PRD_FILE" 2>/dev/null || echo "999")
    if [[ "$REMAINING" -eq 0 ]]; then
      echo "✅ Ralph loop: all stories passing. Loop complete." >&2
      rm "$STATE_FILE"
      exit 0
    fi
    echo "⚠️  Ralph loop: promise asserted but $REMAINING story(s) still incomplete. Continuing." >&2
  fi
fi

# --- find next incomplete story (authoritative completion check) --------------

STORY_JSON=$(jq -c '
  .stories
  | map(select(.passes == false or .passes == null))
  | sort_by(.priority // 999)
  | first // null
' "$PRD_FILE")

if [[ "$STORY_JSON" == "null" ]] || [[ -z "$STORY_JSON" ]]; then
  echo "✅ Ralph loop: all stories in $PRD_FILE have passes: true. Loop complete." >&2
  rm "$STATE_FILE"
  exit 0
fi

STORY_ID=$(echo "$STORY_JSON" | jq -r '.id')
STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title')
STORY_TYPE=$(echo "$STORY_JSON" | jq -r '.type // "backend"')

TOTAL=$(jq '.stories | length' "$PRD_FILE")
DONE=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE")

# --- bump iteration counter atomically ----------------------------------------

NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# --- build the next prompt ----------------------------------------------------

read -r -d '' PROMPT <<EOF || true
You are inside a Ralph loop. Implement the next incomplete story from prd.json using the **ralph-worker** skill.

## Next story
- ID: $STORY_ID
- Title: $STORY_TITLE
- Type: $STORY_TYPE

## Your job
1. Read the ralph-worker skill (skills/ralph-worker/SKILL.md) and follow its full team-based workflow for this story.
2. Read prd.json for the story's full acceptance criteria, team config, and per-phase models.
3. Spawn the appropriate design / implement / review agents per the team config.
4. When the story passes review, set its passes: true in prd.json and commit code + progress.txt + prd.json as ONE commit (subject only, no scope prefix, no story number).

## Loop control
- The Stop hook is active. When you finish this story and try to exit, the hook will pick the NEXT incomplete story from prd.json and re-prompt you automatically.
- Do NOT try to implement multiple stories in one turn. ONE story per iteration is the contract.
- When prd.json shows all stories with passes: true, output exactly: <promise>$PROMISE_TAG</promise>
- Do NOT output that promise unless every story genuinely passes. The hook re-checks prd.json and will reject false promises. Trust the loop.

## Progress
- Iteration: $NEXT_ITERATION$([ $MAX_ITERATIONS -gt 0 ] && echo " / $MAX_ITERATIONS" || echo "")
- Stories: $DONE / $TOTAL passing
EOF

SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION → $STORY_ID: $STORY_TITLE ($DONE/$TOTAL done)"

# --- emit block decision ------------------------------------------------------

jq -n \
  --arg prompt "$PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
