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
INJECTED_FILE=".claude/ralph-loop.last-injected"
PROMISE_TAG="RALPH-COMPLETE"

# Re-injection threshold: warn loudly when the same story has been injected
# this many times without progress. Indicates the user keeps interjecting and
# the worker prompt never lands.
REINJECT_WARN_THRESHOLD=3

cleanup_state() {
  rm -f "$STATE_FILE" "$INJECTED_FILE"
}

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
  cleanup_state
  exit 0
fi

# --- max iterations safety net ------------------------------------------------

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ralph loop: max iterations ($MAX_ITERATIONS) reached. Stopping." >&2
  cleanup_state
  exit 0
fi

# --- prd.json must exist ------------------------------------------------------

if [[ ! -f "$PRD_FILE" ]]; then
  echo "⚠️  Ralph loop: $PRD_FILE not found. Run /ralph-prd first. Stopping." >&2
  cleanup_state
  exit 0
fi

# --- blocker state check ------------------------------------------------------
#
# If the worker wrote `.ralph-blocker.md` (retry cap reached on some story),
# halt the loop so the user can intervene. Auto-clean if the blocker's story
# is now passes: true — the user resolved it manually.

BLOCKER_FILE=".ralph-blocker.md"
if [[ -f "$BLOCKER_FILE" ]]; then
  BLOCKER_STORY=$(sed -n 's/^story_id: *//p' "$BLOCKER_FILE" | head -1 | tr -d '[:space:]')
  if [[ -n "$BLOCKER_STORY" ]]; then
    BLOCKER_PASSES=$(jq -r --arg id "$BLOCKER_STORY" \
      '.stories[] | select(.id == $id) | .passes' "$PRD_FILE" 2>/dev/null)
    if [[ "$BLOCKER_PASSES" == "true" ]]; then
      echo "✅ Ralph loop: blocker for $BLOCKER_STORY resolved (passes: true). Removing $BLOCKER_FILE and continuing." >&2
      rm -f "$BLOCKER_FILE"
    else
      echo "🛑 Ralph loop: blocked on ${BLOCKER_STORY:-unknown} — see $BLOCKER_FILE for review verdict and unblock instructions. Stopping." >&2
      cleanup_state
      exit 0
    fi
  else
    echo "🛑 Ralph loop: $BLOCKER_FILE exists (story_id unreadable). Inspect it and delete when resolved. Stopping." >&2
    cleanup_state
    exit 0
  fi
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
      # Suggest a PR command if gh is available
      if command -v gh &> /dev/null; then
        PRD_BRANCH=$(jq -r '.branch // empty' "$PRD_FILE")
        PRD_NAME=$(jq -r '.name // empty' "$PRD_FILE")
        if [[ -n "$PRD_BRANCH" ]]; then
          echo "" >&2
          echo "Ready to open a PR? Push and run:" >&2
          if [[ -n "$PRD_NAME" ]]; then
            echo "  git push -u origin \"$PRD_BRANCH\"" >&2
            echo "  gh pr create --draft --title \"$PRD_NAME\" --body \"See prd.json for the full story breakdown.\"" >&2
          else
            echo "  git push -u origin \"$PRD_BRANCH\"" >&2
            echo "  gh pr create --draft" >&2
          fi
        fi
      fi
      cleanup_state
      exit 0
    fi
    echo "⚠️  Ralph loop: promise asserted but $REMAINING story(s) still incomplete. Continuing." >&2
  fi
fi

# --- find next runnable story (respects depends_on) ---------------------------
#
# A story is runnable when it's incomplete AND every id in its depends_on array
# belongs to another story with passes: true. Stories with unmet deps are
# skipped until their prerequisites pass.

STORY_JSON=$(jq -c '
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
  | first // null
' "$PRD_FILE")

if [[ "$STORY_JSON" == "null" ]] || [[ -z "$STORY_JSON" ]]; then
  # Distinguish "all done" from "deadlock"
  INCOMPLETE=$(jq '[.stories[] | select(.passes == false or .passes == null)] | length' "$PRD_FILE")
  if [[ "$INCOMPLETE" -eq 0 ]]; then
    echo "✅ Ralph loop: all stories in $PRD_FILE have passes: true. Loop complete." >&2
  else
    echo "🛑 Ralph loop: $INCOMPLETE incomplete story(s) but none runnable — dependency deadlock. Check depends_on in $PRD_FILE. Stopping." >&2
  fi
  cleanup_state
  exit 0
fi

STORY_ID=$(echo "$STORY_JSON" | jq -r '.id')
STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title')
STORY_TYPE=$(echo "$STORY_JSON" | jq -r '.type // "backend"')

TOTAL=$(jq '.stories | length' "$PRD_FILE")
DONE=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE")

# --- re-injection tracking ----------------------------------------------------
#
# The Stop hook can have its decision-block prompt preempted by a user message
# that arrives between iterations. When that happens, the worker prompt for
# this story never lands and the same story stays passes:false. On the next
# Stop event we'd inject the same prompt — that's already correct behaviour.
#
# What we add here: explicit tracking so we (a) log clearly that a re-injection
# is happening, and (b) escalate the warning if it keeps happening for the
# same story. INJECTED_FILE format: "STORY_ID COUNT" on a single line.

LAST_INJECTED_ID=""
LAST_INJECTED_COUNT=0
if [[ -f "$INJECTED_FILE" ]]; then
  read -r LAST_INJECTED_ID LAST_INJECTED_COUNT < "$INJECTED_FILE" || true
  if [[ ! "$LAST_INJECTED_COUNT" =~ ^[0-9]+$ ]]; then
    LAST_INJECTED_COUNT=0
  fi
fi

REINJECT_NOTE=""
if [[ "$LAST_INJECTED_ID" == "$STORY_ID" ]] && [[ $LAST_INJECTED_COUNT -ge 1 ]]; then
  NEW_COUNT=$((LAST_INJECTED_COUNT + 1))
  REINJECT_NOTE=" (re-injection #$NEW_COUNT)"
  echo "🔁 Ralph loop: $STORY_ID still passes:false on Stop — previous prompt was preempted (likely by a user message). Re-injecting (attempt #$NEW_COUNT)." >&2
  if [[ $NEW_COUNT -ge $REINJECT_WARN_THRESHOLD ]]; then
    echo "⚠️  Ralph loop: $STORY_ID has been re-injected $NEW_COUNT times without progress. If you keep typing between iterations the worker prompt never lands. Stop interjecting OR run /cancel-ralph and switch to /ralph-agent." >&2
  fi
else
  NEW_COUNT=1
fi
echo "$STORY_ID $NEW_COUNT" > "$INJECTED_FILE"

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

SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION → $STORY_ID: $STORY_TITLE ($DONE/$TOTAL done)$REINJECT_NOTE"

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
