#!/bin/bash
#
# Ralph - Autonomous agent loop for Claude Code
# Spawns fresh Claude CLI sessions to implement PRD stories iteratively
#
# Usage: ./ralph.sh [max_iterations]
#
# Based on: https://github.com/snarktank/ralph

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ITERATIONS="${1:-10}"
COMPLETION_SIGNAL="<promise>COMPLETE</promise>"

# Files in current working directory
PRD_FILE="prd.json"
PROGRESS_FILE="progress.txt"
ARCHIVE_DIR="archive"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[Ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[Ralph]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[Ralph]${NC} $1"; }
log_error() { echo -e "${RED}[Ralph]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    if ! command -v claude &> /dev/null; then
        log_error "Claude CLI not found. Install it first."
        exit 1
    fi

    if [ ! -f "$PRD_FILE" ]; then
        log_error "prd.json not found. Run /ralph-convert first to create it."
        exit 1
    fi
}

# Initialize progress file if needed
init_progress() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        log_info "Creating progress.txt..."
        cat > "$PROGRESS_FILE" << 'EOF'
# Progress Log

## Codebase Patterns
[Patterns discovered during implementation will be added here]

---
# Iteration Log

EOF
        log_success "Created progress.txt"
    fi
}

# Archive previous prd.json if branch changed
archive_if_needed() {
    if [ ! -f "$PRD_FILE" ]; then
        return
    fi

    local current_branch
    current_branch=$(jq -r '.branch // empty' "$PRD_FILE" 2>/dev/null || echo "")

    if [ -z "$current_branch" ]; then
        return
    fi

    local stored_branch=""
    if [ -f ".ralph_branch" ]; then
        stored_branch=$(cat .ralph_branch)
    fi

    if [ -n "$stored_branch" ] && [ "$stored_branch" != "$current_branch" ]; then
        log_info "Branch changed from $stored_branch to $current_branch"
        mkdir -p "$ARCHIVE_DIR"
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local archive_name="prd-${stored_branch//\//-}-${timestamp}.json"

        if [ -f "$PRD_FILE" ]; then
            cp "$PRD_FILE" "$ARCHIVE_DIR/$archive_name"
            log_info "Archived previous prd.json to $ARCHIVE_DIR/$archive_name"
        fi

        if [ -f "$PROGRESS_FILE" ]; then
            cp "$PROGRESS_FILE" "$ARCHIVE_DIR/progress-${stored_branch//\//-}-${timestamp}.txt"
            log_info "Archived previous progress.txt"
        fi
    fi

    echo "$current_branch" > .ralph_branch
}

# Get the Claude model ID for the next story's implement phase
# Reads models.implement from prd.json, falls back to sonnet
get_next_story_model_id() {
    local short_name
    short_name=$(jq -r '
      .stories
      | map(select(.passes == false))
      | sort_by(.priority)
      | .[0].models.implement
      // "sonnet"
    ' "$PRD_FILE" 2>/dev/null)

    case "$short_name" in
        opus)   echo "claude-opus-4-6" ;;
        haiku)  echo "claude-haiku-4-5-20251001" ;;
        *)      echo "claude-sonnet-4-6" ;;
    esac
}

# Check if all stories are complete
all_stories_complete() {
    local incomplete
    incomplete=$(jq '[.stories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null || echo "999")
    [ "$incomplete" -eq 0 ]
}

# Get next incomplete story info
get_next_story() {
    jq -r '.stories | map(select(.passes == false)) | sort_by(.priority) | .[0] | "\(.id): \(.title)"' "$PRD_FILE" 2>/dev/null
}

# Count stories
count_stories() {
    local total complete
    total=$(jq '.stories | length' "$PRD_FILE" 2>/dev/null || echo "0")
    complete=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
    echo "$complete/$total"
}

# The worker prompt sent to each Claude session
# Delegates the full team-aware workflow to the ralph-worker skill so all three
# execution modes (bash loop, /ralph-agent, /ralph-loop) share the same behavior.
generate_worker_prompt() {
    cat << 'PROMPT'
You are a Ralph iteration. Implement ONE user story from prd.json with fresh context.

## Step 1 — Invoke the ralph-worker skill

Invoke the `ralph-worker` skill immediately. It owns the full workflow:
- Picks the highest-priority incomplete story from prd.json
- Reads `type`, `team`, and `models` fields
- Runs the design → implement → review phases with the right specialists
- Handles review retries (max 2)
- Updates progress.txt and sets `passes: true` on success
- Creates ONE commit bundling code + progress.txt + prd.json

Do NOT implement the story yourself. Do NOT use a flat single-agent workflow.
The skill is the single source of truth for worker behavior across all Ralph modes.

## Step 2 — Signal completion to the loop

After the skill finishes, check prd.json:
- If ALL stories have `passes: true`, output exactly: <promise>COMPLETE</promise>
- Otherwise, print a one-line summary of what was implemented and exit.

## Commit message rules (STRICT — enforced by the skill, restated here)
- Format: `feat: <imperative>` or `fix: <imperative>` — subject only, no body
- NO story numbers (never `feat: US-011 ...`, never `feat(US-011): ...`)
- NO parenthetical scope prefixes (never `feat(api): ...`)
- ONE commit bundling code + progress.txt + prd.json — never a separate `chore:` commit
- No Claude as author/co-author

Begin by invoking the ralph-worker skill.
PROMPT
}

# Main loop
main() {
    log_info "Starting Ralph autonomous agent loop"
    log_info "Max iterations: $MAX_ITERATIONS"
    echo ""

    check_prerequisites
    archive_if_needed
    init_progress

    # Check initial state
    if all_stories_complete; then
        log_success "All stories already complete!"
        exit 0
    fi

    local progress
    progress=$(count_stories)
    log_info "Stories complete: $progress"
    echo ""

    # Main iteration loop
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        local next_story
        next_story=$(get_next_story)

        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Iteration $i/$MAX_ITERATIONS"
        log_info "Next story: $next_story"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Spawn fresh Claude session with the model from prd.json
        local output
        local model_id
        model_id=$(get_next_story_model_id)
        log_info "Model: $model_id"
        output=$(generate_worker_prompt | claude --print --model "$model_id" 2>&1) || true

        # Check for completion signal
        if echo "$output" | grep -q "$COMPLETION_SIGNAL"; then
            echo ""
            log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_success "All stories complete!"
            log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            # Print summary
            echo ""
            log_info "Summary:"
            jq -r '.stories[] | "  - \(.id): \(.title) \(if .passes then "✓" else "✗" end)"' "$PRD_FILE"
            echo ""

            local branch
            branch=$(jq -r '.branch' "$PRD_FILE")
            log_info "Branch: $branch"
            exit 0
        fi

        # Update progress display
        progress=$(count_stories)
        log_info "Progress: $progress stories complete"
        echo ""

        # Check if we're done
        if all_stories_complete; then
            log_success "All stories complete!"
            exit 0
        fi
    done

    log_warn "Reached max iterations ($MAX_ITERATIONS) without completing all stories"
    progress=$(count_stories)
    log_warn "Final progress: $progress"
    exit 1
}

main "$@"
