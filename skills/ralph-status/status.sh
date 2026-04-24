#!/bin/bash
#
# Ralph status — read-only summary of the current project's Ralph state.
# Reads prd.json, .ralph-blocker.md, and .claude/ralph-loop.local.md.
#
# Usage: status.sh [prd.json]

set -o pipefail

PRD_FILE="${1:-prd.json}"
BLOCKER_FILE=".ralph-blocker.md"
LOOP_STATE=".claude/ralph-loop.local.md"
METRICS_FILE=".ralph-metrics.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

if [ ! -f "$PRD_FILE" ]; then
    echo -e "${RED}✗${NC} $PRD_FILE not found in current directory."
    echo -e "  Run ${BLUE}/ralph-prd${NC} first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq not found on PATH${NC}"
    exit 1
fi

# --- basic counts -------------------------------------------------------------

NAME=$(jq -r '.name // "(unnamed)"' "$PRD_FILE")
BRANCH=$(jq -r '.branch // "(no branch)"' "$PRD_FILE")
TOTAL=$(jq '.stories | length' "$PRD_FILE")
PASSING=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE")
INCOMPLETE=$(jq '[.stories[] | select(.passes == false or .passes == null)] | length' "$PRD_FILE")

echo -e "${BLUE}Ralph Status${NC} — $NAME ($BRANCH)"
echo -e "${DIM}$(printf '%.0s─' $(seq 1 60))${NC}"
echo ""
echo -e "Stories: ${GREEN}$PASSING passing${NC} / $TOTAL total ($INCOMPLETE incomplete)"

# --- next runnable story ------------------------------------------------------

NEXT_JSON=$(jq -c '
  .stories as $all
  | $all
  | map(select(
      (.passes == false or .passes == null)
      and (
        (.depends_on // [])
        | all(. as $d | $all | any(.id == $d and .passes == true))
      )
    ))
  | sort_by(.priority // 999)
  | first // null
' "$PRD_FILE")

if [ "$NEXT_JSON" != "null" ] && [ -n "$NEXT_JSON" ]; then
    NEXT_ID=$(echo "$NEXT_JSON" | jq -r '.id')
    NEXT_TITLE=$(echo "$NEXT_JSON" | jq -r '.title')
    NEXT_TYPE=$(echo "$NEXT_JSON" | jq -r '.type // "backend"')
    echo -e "Next runnable: ${GREEN}$NEXT_ID${NC} — $NEXT_TITLE ${DIM}($NEXT_TYPE)${NC}"
else
    if [ "$INCOMPLETE" -eq 0 ]; then
        echo -e "Next runnable: ${GREEN}none — all stories passing${NC}"
    else
        echo -e "Next runnable: ${RED}none${NC} — dependency deadlock or blocker"
    fi
fi

# --- blocked-by-deps listing --------------------------------------------------

BLOCKED=$(jq -r '
  .stories as $all
  | $all
  | map(select(
      (.passes == false or .passes == null)
      and (
        (.depends_on // [])
        | any(. as $d | $all | any(.id == $d and (.passes == false or .passes == null)))
      )
    ))
  | .[]
  | "  \(.id) — \(.title) (waiting on: \((.depends_on // []) | join(", ")))"
' "$PRD_FILE")

if [ -n "$BLOCKED" ]; then
    echo ""
    echo -e "${YELLOW}Blocked by dependencies:${NC}"
    echo "$BLOCKED"
fi

# --- blocker state ------------------------------------------------------------

if [ -f "$BLOCKER_FILE" ]; then
    BLOCKER_STORY=$(sed -n 's/^story_id: *//p' "$BLOCKER_FILE" | head -1 | tr -d '[:space:]')
    BLOCKER_AT=$(sed -n 's/^blocked_at: *//p' "$BLOCKER_FILE" | head -1 | tr -d '[:space:]')
    echo ""
    echo -e "${RED}⛔ Blocker active${NC}: ${BLOCKER_STORY:-unknown} (since ${BLOCKER_AT:-unknown})"
    echo -e "   Read $BLOCKER_FILE for the review verdict and unblock options."
fi

# --- metrics summary ----------------------------------------------------------

if [ -f "$METRICS_FILE" ] && command -v jq &> /dev/null; then
    METRICS_COUNT=$(jq '.stories | length' "$METRICS_FILE" 2>/dev/null || echo 0)
    if [ "$METRICS_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${BLUE}Metrics${NC} ($METRICS_COUNT stories recorded)"
        SUMMARY=$(jq -r '
            (.stories | to_entries) as $entries
            | ($entries | map(.value.review_cycles) | add / length) as $avg_cycles
            | ($entries | map(.value.lines_added) | add) as $total_added
            | ($entries | map(.value.lines_removed) | add) as $total_removed
            | ($entries | map(.value.model_used_implement) | group_by(.)
                | map({k: .[0], v: length}) | sort_by(.v) | reverse | .[0].k) as $top_model
            | "  Avg review cycles: \($avg_cycles | (.*10 | round)/10)\n  Lines changed: +\($total_added) / -\($total_removed)\n  Most-used implement model: \($top_model)"
        ' "$METRICS_FILE" 2>/dev/null)
        echo "$SUMMARY"

        # Flag painful stories (cycles >= 2)
        PAINFUL=$(jq -r '
            .stories
            | to_entries
            | map(select(.value.review_cycles >= 2))
            | .[]
            | "  \(.key): \(.value.review_cycles) cycles on \(.value.model_used_implement)"
        ' "$METRICS_FILE" 2>/dev/null)
        if [ -n "$PAINFUL" ]; then
            echo ""
            echo -e "  ${YELLOW}Needed retries:${NC}"
            echo "$PAINFUL"
        fi
    fi
fi

# --- loop state ---------------------------------------------------------------

if [ -f "$LOOP_STATE" ]; then
    ITER=$(grep '^iteration:' "$LOOP_STATE" | head -1 | sed 's/iteration: *//' | tr -d '[:space:]')
    MAX=$(grep '^max_iterations:' "$LOOP_STATE" | head -1 | sed 's/max_iterations: *//' | tr -d '[:space:]')
    STARTED=$(grep '^started_at:' "$LOOP_STATE" | head -1 | sed 's/started_at: *//' | tr -d '"[:space:]')
    echo ""
    if [ "${MAX:-0}" -gt 0 ]; then
        echo -e "${BLUE}/ralph-loop active${NC}: iteration $ITER / $MAX (started $STARTED)"
    else
        echo -e "${BLUE}/ralph-loop active${NC}: iteration $ITER / ∞ (started $STARTED)"
    fi
fi

exit 0
