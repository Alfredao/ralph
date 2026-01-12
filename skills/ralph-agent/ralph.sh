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
generate_worker_prompt() {
    cat << 'PROMPT'
You are a Ralph Worker. Implement ONE user story from prd.json with fresh context.

## Workflow

1. **Read context files:**
   - `prd.json` - find the highest-priority story where `passes: false`
   - `progress.txt` - check Codebase Patterns and learnings from previous iterations
   - `AGENTS.md` - if it exists, read module-specific patterns

2. **Implement the story:**
   - Make minimal, focused changes
   - Follow existing code patterns
   - ONLY implement what's needed for acceptance criteria

3. **Run quality checks:**
   - Typecheck (npm run typecheck or equivalent)
   - Lint (npm run lint or equivalent)
   - Tests (npm test or equivalent)
   - All must pass before proceeding

4. **Update progress.txt:**
   - Append implementation details
   - Add "Learnings for future iterations" section
   - Update Codebase Patterns if you discovered reusable patterns

5. **Commit changes:**
   ```
   git add -A
   git commit -m "[STORY_ID]: [brief description]"
   ```

6. **Update prd.json:**
   - Set `passes: true` for your completed story
   - Add notes if helpful

7. **Check completion:**
   - If ALL stories have `passes: true`, output: <promise>COMPLETE</promise>
   - Otherwise, just report what you implemented

## Rules
- Implement exactly ONE story per session
- All quality checks must pass
- Document learnings in progress.txt
- Don't skip steps

Start by reading prd.json and progress.txt, then implement the next incomplete story.
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

        # Spawn fresh Claude session
        local output
        output=$(generate_worker_prompt | claude --print 2>&1) || true

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
