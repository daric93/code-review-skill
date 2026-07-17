#!/bin/bash
# Hook script: validates the pr-code-review findings sentinel file
# Runs after the skill writes to <config>/reviews/*.md
# Returns 0 (pass) or 1 (halt) with a descriptive message on stderr

set -euo pipefail

FINDINGS_FILE="${1:-}"

if [ -z "$FINDINGS_FILE" ]; then
    echo "HALT: No findings file path provided." >&2
    exit 1
fi

if [ ! -f "$FINDINGS_FILE" ]; then
    echo "HALT: Findings file not found at $FINDINGS_FILE. Review did not complete." >&2
    exit 1
fi

if [ ! -s "$FINDINGS_FILE" ]; then
    echo "HALT: Findings file is empty. Review did not complete." >&2
    exit 1
fi

# Check required header fields
check_field() {
    local field="$1"
    if ! grep -q "^${field}:" "$FINDINGS_FILE"; then
        echo "HALT: Findings file malformed: missing '$field' header." >&2
        exit 1
    fi
}

check_field "pr_url"
check_field "repo"
check_field "pr_number"
check_field "review_date"
check_field "verdict"

# Check verdict is a valid value
VERDICT=$(grep "^verdict:" "$FINDINGS_FILE" | head -1 | sed 's/verdict: *//')
case "$VERDICT" in
    pending|REQUEST_CHANGES|COMMENT|APPROVE)
        ;;
    *)
        echo "HALT: Invalid verdict '$VERDICT'. Must be: pending, REQUEST_CHANGES, COMMENT, or APPROVE." >&2
        exit 1
        ;;
esac

# Check that at least one finding exists (even if count is 0, the section should be present)
if ! grep -q "^## Finding\|^### #[0-9]" "$FINDINGS_FILE"; then
    echo "WARN: No findings section found. Review may have produced no findings (correct for clean code)." >&2
    # This is a PASS — clean code means no findings, which is valid
fi

# Check for any findings still in 'proposed' state after verdict is final
if [ "$VERDICT" != "pending" ]; then
    PROPOSED_COUNT=$(grep -c "decision: proposed" "$FINDINGS_FILE" 2>/dev/null || echo "0")
    if [ "$PROPOSED_COUNT" -gt 0 ]; then
        echo "WARN: Review submitted but $PROPOSED_COUNT finding(s) still have decision: proposed." >&2
        # Warning only — doesn't halt, but signals incomplete decision recording
    fi
fi

echo "PASS: Findings file is well-formed. Downstream consumers can proceed." >&2
exit 0
