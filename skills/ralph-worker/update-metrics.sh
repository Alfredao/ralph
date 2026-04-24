#!/bin/bash
#
# update-metrics.sh — upsert a per-story entry in .ralph-metrics.json.
# Called by the worker after a successful story commit.
#
# Usage: update-metrics.sh <story_id> <review_cycles> <model_implement> <commit_sha> [metrics_file]
# Metrics file defaults to .ralph-metrics.json in the current directory.
# Deterministic, zero-token. Uncommitted by design — add .ralph-metrics.json
# to .gitignore if you don't want it tracked.

set -o pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <story_id> <review_cycles> <model_implement> <commit_sha> [metrics_file]" >&2
    exit 2
fi

STORY_ID="$1"
REVIEW_CYCLES="$2"
MODEL_IMPLEMENT="$3"
COMMIT_SHA="$4"
METRICS_FILE="${5:-.ralph-metrics.json}"

if ! command -v jq &> /dev/null; then
    echo "update-metrics.sh: jq not found on PATH" >&2
    exit 1
fi

# Pull file + line counts from the commit via numstat.
# Binary diffs show as `- - <path>` and don't contribute to lines_added/removed.
STATS=$(git show --numstat --format= "$COMMIT_SHA" 2>/dev/null || true)
FILES=$(echo "$STATS" | grep -c . || echo 0)
ADDED=$(echo "$STATS" | awk '$1 ~ /^[0-9]+$/ {sum+=$1} END {print sum+0}')
REMOVED=$(echo "$STATS" | awk '$2 ~ /^[0-9]+$/ {sum+=$2} END {print sum+0}')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ ! -f "$METRICS_FILE" ]; then
    echo '{"schema_version":"1","stories":{}}' > "$METRICS_FILE"
fi

TMP="$METRICS_FILE.tmp.$$"
jq \
    --arg id "$STORY_ID" \
    --arg ts "$TS" \
    --argjson cycles "$REVIEW_CYCLES" \
    --arg model "$MODEL_IMPLEMENT" \
    --arg sha "$COMMIT_SHA" \
    --argjson files "$FILES" \
    --argjson added "$ADDED" \
    --argjson removed "$REMOVED" \
    '.stories[$id] = {
        completed_at: $ts,
        review_cycles: $cycles,
        model_used_implement: $model,
        files_touched: $files,
        lines_added: $added,
        lines_removed: $removed,
        commit_sha: $sha
    }' "$METRICS_FILE" > "$TMP" && mv "$TMP" "$METRICS_FILE"

echo "Metrics updated: $STORY_ID (cycles=$REVIEW_CYCLES, model=$MODEL_IMPLEMENT, files=$FILES, +$ADDED/-$REMOVED)" >&2
exit 0
