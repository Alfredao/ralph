#!/bin/bash
#
# Ralph PRD validator
# Static checks over prd.json before running the loop.
#
# Usage: ./validate.sh [prd.json]
# Exit: 0 on success, 1 on errors. Warnings don't fail the run.

set -o pipefail

PRD_FILE="${1:-prd.json}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=()
WARNINGS=()

err()  { ERRORS+=("$1"); }
warn() { WARNINGS+=("$1"); }

# --- prerequisite checks ------------------------------------------------------

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq not found on PATH${NC}"
    exit 1
fi

if [ ! -f "$PRD_FILE" ]; then
    echo -e "${RED}✗ $PRD_FILE not found${NC}"
    exit 1
fi

if ! jq empty "$PRD_FILE" 2>/dev/null; then
    echo -e "${RED}✗ $PRD_FILE is not valid JSON${NC}"
    exit 1
fi

echo -e "${BLUE}Validating $PRD_FILE...${NC}"

# --- top-level structure ------------------------------------------------------

for field in name branch stories; do
    if [ "$(jq -r ".$field // \"__MISSING__\"" "$PRD_FILE")" = "__MISSING__" ]; then
        err "Missing top-level field: .$field"
    fi
done

branch=$(jq -r '.branch // ""' "$PRD_FILE")
if [ -n "$branch" ] && [[ ! "$branch" =~ ^(feature|fix|hotfix|chore)/ ]]; then
    warn "Branch '$branch' doesn't start with feature/, fix/, hotfix/, or chore/"
fi

stories_type=$(jq -r '.stories | type' "$PRD_FILE" 2>/dev/null || echo "null")
if [ "$stories_type" != "array" ]; then
    err ".stories must be an array (got: $stories_type)"
    print_and_exit() {
        echo ""
        for e in "${ERRORS[@]}"; do echo -e "  ${RED}✗${NC} $e"; done
        echo -e "${RED}✗ Validation failed${NC}"
        exit 1
    }
    print_and_exit
fi

story_count=$(jq '.stories | length' "$PRD_FILE")
if [ "$story_count" -eq 0 ]; then
    err ".stories array is empty"
fi

# --- collect story ids --------------------------------------------------------

STORY_IDS=()
while IFS= read -r line; do
    STORY_IDS+=("$line")
done < <(jq -r '.stories[].id // "__NO_ID__"' "$PRD_FILE")

if [ "${#STORY_IDS[@]}" -gt 0 ]; then
    dup_ids=$(printf '%s\n' "${STORY_IDS[@]}" | grep -v '^__NO_ID__$' | sort | uniq -d)
else
    dup_ids=""
fi
if [ -n "$dup_ids" ]; then
    err "Duplicate story ids: $(echo "$dup_ids" | tr '\n' ' ')"
fi

# --- per-story checks ---------------------------------------------------------

VALID_TYPES="backend frontend fullstack infra data"
VALID_MODELS="opus sonnet haiku"

for idx in $(seq 0 $((story_count - 1))); do
    story=$(jq -c ".stories[$idx]" "$PRD_FILE")
    id=$(echo "$story" | jq -r '.id // "__MISSING__"')
    label="Story $id (index $idx)"

    # Required fields. Use has() rather than `//` because `//` treats
    # literal `false` as missing (which breaks the .passes check).
    for field in id title description priority acceptance_criteria passes type team models; do
        if [ "$(echo "$story" | jq "has(\"$field\")")" != "true" ]; then
            err "$label: missing .$field"
        fi
    done

    # type must be valid
    stype=$(echo "$story" | jq -r '.type // ""')
    if [ -n "$stype" ] && ! echo "$VALID_TYPES" | grep -qw "$stype"; then
        err "$label: .type '$stype' must be one of: $VALID_TYPES"
    fi

    # acceptance_criteria must be array and cover required checks
    ac_type=$(echo "$story" | jq -r '.acceptance_criteria | type' 2>/dev/null || echo "null")
    if [ "$ac_type" = "array" ]; then
        ac_len=$(echo "$story" | jq '.acceptance_criteria | length')
        if [ "$ac_len" -eq 0 ]; then
            err "$label: acceptance_criteria is empty"
        fi

        has_typecheck=$(echo "$story" | jq '[.acceptance_criteria[] | ascii_downcase | contains("typecheck")] | any')
        if [ "$has_typecheck" != "true" ]; then
            err "$label: acceptance_criteria must include 'Typecheck passes'"
        fi

        if [ "$stype" = "frontend" ] || [ "$stype" = "fullstack" ]; then
            has_browser=$(echo "$story" | jq '[.acceptance_criteria[] | ascii_downcase | contains("verify in browser")] | any')
            if [ "$has_browser" != "true" ]; then
                err "$label (type: $stype): acceptance_criteria must include 'Verify in browser'"
            fi
        fi
    elif [ "$ac_type" != "null" ]; then
        err "$label: acceptance_criteria must be an array (got: $ac_type)"
    fi

    # team structure
    for phase in design implement review; do
        phase_type=$(echo "$story" | jq -r ".team.$phase | type" 2>/dev/null || echo "null")
        if [ "$phase_type" != "array" ] && [ "$phase_type" != "null" ]; then
            err "$label: team.$phase must be an array (got: $phase_type)"
        fi
    done
    # implement and review must be non-empty
    impl_len=$(echo "$story" | jq '.team.implement // [] | length')
    if [ "$impl_len" -eq 0 ]; then
        err "$label: team.implement must have at least one agent"
    fi
    rev_len=$(echo "$story" | jq '.team.review // [] | length')
    if [ "$rev_len" -eq 0 ]; then
        err "$label: team.review must have at least one agent"
    fi

    # models values
    for phase in design implement review; do
        model=$(echo "$story" | jq -r ".models.$phase // \"\"")
        if [ -n "$model" ] && ! echo "$VALID_MODELS" | grep -qw "$model"; then
            err "$label: models.$phase '$model' must be one of: $VALID_MODELS"
        fi
    done

    # depends_on validation
    deps_type=$(echo "$story" | jq -r '.depends_on | type' 2>/dev/null || echo "null")
    if [ "$deps_type" != "null" ] && [ "$deps_type" != "array" ]; then
        err "$label: depends_on must be an array (got: $deps_type)"
    fi

    if [ "$deps_type" = "array" ]; then
        deps=$(echo "$story" | jq -r '.depends_on[]?' 2>/dev/null)
        for dep in $deps; do
            if [ "$dep" = "$id" ]; then
                err "$label: depends_on includes self ('$id')"
                continue
            fi
            found=0
            for existing in "${STORY_IDS[@]}"; do
                [ "$dep" = "$existing" ] && { found=1; break; }
            done
            if [ "$found" -eq 0 ]; then
                err "$label: depends_on '$dep' references unknown story"
            fi
        done
    fi
done

# --- dependency cycle detection (Kahn's algorithm) ----------------------------
#
# Build a dep map, then repeatedly remove nodes with all deps in the processed
# set. If any nodes remain, there's a cycle (or a dangling ref — those already
# errored above but we still surface the cycle for clarity).

get_deps_of() {
    jq -r --arg id "$1" \
        '.stories[] | select(.id == $id) | (.depends_on // [])[]' "$PRD_FILE" 2>/dev/null | tr '\n' ' '
}

processed=" "
remaining=""
for id in "${STORY_IDS[@]}"; do
    [ "$id" = "__NO_ID__" ] && continue
    remaining="$remaining $id"
done

progress=1
while [ "$progress" -eq 1 ] && [ -n "$remaining" ]; do
    progress=0
    next_remaining=""
    for id in $remaining; do
        all_met=1
        for dep in $(get_deps_of "$id"); do
            if [[ "$processed" != *" $dep "* ]]; then
                all_met=0
                break
            fi
        done
        if [ "$all_met" -eq 1 ]; then
            processed="$processed$id "
            progress=1
        else
            next_remaining="$next_remaining $id"
        fi
    done
    remaining="$next_remaining"
done

# Trim leading whitespace
remaining=$(echo "$remaining" | xargs)
if [ -n "$remaining" ]; then
    err "Dependency cycle or unreachable nodes: $remaining"
fi

# --- summary ------------------------------------------------------------------

echo ""
if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo -e "${YELLOW}Warnings:${NC}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $w"
    done
    echo ""
fi

if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo -e "${RED}Errors:${NC}"
    for e in "${ERRORS[@]}"; do
        echo -e "  ${RED}✗${NC} $e"
    done
    echo ""
    echo -e "${RED}✗ Validation failed with ${#ERRORS[@]} error(s)${NC}"
    exit 1
fi

passing=$(jq '[.stories[] | select(.passes == true)] | length' "$PRD_FILE")
echo -e "${GREEN}✓ $PRD_FILE is valid${NC} ($story_count stories, $passing passing)"
exit 0
