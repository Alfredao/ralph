#!/bin/bash
#
# Compact progress.txt when it grows past a size threshold.
# Keeps the Codebase Patterns header (everything before the first `---`)
# intact; archives a full copy and truncates the iteration log tail.
#
# Usage: compact-progress.sh [progress.txt] [archive/]
# Deterministic, zero-token — no AI involved. Safe to run every iteration.

set -o pipefail

PROGRESS_FILE="${1:-progress.txt}"
ARCHIVE_DIR="${2:-archive}"
SIZE_THRESHOLD=$((50 * 1024))    # 50 KB
TAIL_KB=20                        # keep last 20 KB of iteration log

if [ ! -f "$PROGRESS_FILE" ]; then
    exit 0
fi

SIZE=$(wc -c < "$PROGRESS_FILE" | tr -d ' ')
if [ "$SIZE" -le "$SIZE_THRESHOLD" ]; then
    exit 0
fi

TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$ARCHIVE_DIR"
ARCHIVE_PATH="$ARCHIVE_DIR/progress-$TS.txt"
cp "$PROGRESS_FILE" "$ARCHIVE_PATH"

SEPARATOR_LINE=$(grep -n '^---$' "$PROGRESS_FILE" | head -1 | cut -d: -f1)

TMP="${PROGRESS_FILE}.compact.tmp.$$"

if [ -z "$SEPARATOR_LINE" ]; then
    # No separator — can't split safely. Keep the tail only.
    {
        echo "# Progress Log"
        echo ""
        echo "(Full previous log archived to $ARCHIVE_PATH — only the tail is kept below.)"
        echo ""
        tail -c "${TAIL_KB}k" "$PROGRESS_FILE"
    } > "$TMP"
else
    {
        sed -n "1,${SEPARATOR_LINE}p" "$PROGRESS_FILE"
        echo ""
        echo "(Older iterations archived to $ARCHIVE_PATH)"
        echo ""
        sed -n "$((SEPARATOR_LINE+1)),\$p" "$PROGRESS_FILE" | tail -c "${TAIL_KB}k"
    } > "$TMP"
fi

mv "$TMP" "$PROGRESS_FILE"

echo "Compacted $PROGRESS_FILE: $SIZE bytes → full copy at $ARCHIVE_PATH" >&2
exit 0
