#!/bin/bash
#
# Cancel an active ralph-loop.
#
# Usage:
#   cancel.sh                  # remove state file (hook becomes no-op)
#   cancel.sh --remove-hook    # also unregister hook from settings.local.json

set -euo pipefail

REMOVE_HOOK=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Cancel Ralph Loop

USAGE:
  /cancel-ralph                Remove state file (hook becomes no-op)
  /cancel-ralph --remove-hook  Also unregister hook from settings.local.json
HELP_EOF
      exit 0
      ;;
    --remove-hook)
      REMOVE_HOOK=1
      shift
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

STATE_FILE=".claude/ralph-loop.local.md"
SETTINGS_FILE=".claude/settings.local.json"

CLEARED_STATE=0
if [[ -f "$STATE_FILE" ]]; then
  rm "$STATE_FILE"
  CLEARED_STATE=1
fi

CLEARED_HOOK=0
if [[ $REMOVE_HOOK -eq 1 ]] && [[ -f "$SETTINGS_FILE" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq not found, cannot edit $SETTINGS_FILE. State file removed; hook still registered." >&2
    exit 1
  fi
  TMP="${SETTINGS_FILE}.tmp.$$"
  jq '
    if (.hooks.Stop // []) | length == 0 then .
    else
      .hooks.Stop = (
        .hooks.Stop
        | map(
            .hooks = (.hooks // [] | map(select((.command // "") | endswith("ralph-loop/stop-hook.sh") | not)))
          )
        | map(select((.hooks // []) | length > 0))
      )
    end
    | if (.hooks.Stop // []) | length == 0 then del(.hooks.Stop) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$SETTINGS_FILE" > "$TMP"
  mv "$TMP" "$SETTINGS_FILE"
  CLEARED_HOOK=1
fi

if [[ $CLEARED_STATE -eq 0 ]] && [[ $CLEARED_HOOK -eq 0 ]]; then
  echo "ℹ️  No active ralph-loop found. Nothing to cancel."
  exit 0
fi

echo "🛑 Ralph loop cancelled."
[[ $CLEARED_STATE -eq 1 ]] && echo "   ✓ Removed $STATE_FILE"
[[ $CLEARED_HOOK -eq 1 ]] && echo "   ✓ Unregistered Stop hook from $SETTINGS_FILE"
[[ $REMOVE_HOOK -eq 0 ]] && echo "   ℹ️  Hook is still registered (no-op without state file). Use --remove-hook to fully uninstall."
