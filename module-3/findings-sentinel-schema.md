# Findings Sentinel File Schema

## Purpose

The findings file is written by pr-code-review at Phase 3.5 — BEFORE any comments are
posted. It serves as:
1. A structured record of what the skill found (source of truth for gap-analyzer)
2. A sentinel file a hook can validate before downstream steps proceed
3. A decision log (which findings were posted vs skipped, and why)

The hook validates the file's structure after it's written, ensuring downstream consumers
(gap-analyzer, retrospective) can parse it reliably.

## Schema

```json
{
  "pr_url": "https://github.com/owner/repo/pull/123",
  "repo": "owner/repo",
  "pr_number": 123,
  "review_date": "2026-07-16",
  "head_sha": "abc1234",
  "reviewer": "pr-code-review",
  "verdict": "pending | REQUEST_CHANGES | COMMENT | APPROVE",
  "tickets": ["https://github.com/owner/repo/issues/456"],
  "findings_count": 5,
  "findings": [
    {
      "number": 1,
      "title": "SQL injection via f-string",
      "file": "app/db/queries.py",
      "line": 3,
      "category": "Security",
      "severity": "CRITICAL",
      "evidence": "query = f\"SELECT * FROM users WHERE id = {user_id}\"",
      "fix": "Use parameterized queries: db.execute(\"SELECT ... WHERE id = ?\", (user_id,))",
      "decision": "proposed | posted | skipped",
      "skip_reason": null
    }
  ]
}
```

## Required Properties

| Property | Type | Required Value | On Failure |
|---|---|---|---|
| pr_url | string | valid GitHub PR URL | halt — cannot proceed without PR identity |
| repo | string | "owner/repo" format | halt — downstream cannot find the PR |
| pr_number | number | > 0 | halt |
| review_date | string | YYYY-MM-DD format | warn — non-critical but needed for indexing |
| head_sha | string | 7+ char hex | warn — needed for gap-analyzer to match commits |
| verdict | string | one of the 4 valid values | halt — downstream relies on this |
| findings_count | number | matches findings array length | halt — inconsistency signals corruption |
| findings | array | each item has: number, title, file, line, category, decision | halt on missing required fields |

## What This Does NOT Validate

- **Quality of findings** — the hook cannot judge whether a finding is real or fabricated.
  That's what the eval's false-positive-avoidance tests measure.
- **Completeness** — the hook cannot know what bugs the skill MISSED.
  That's what gap-analyzer measures by comparing against human reviewers.
- **Fix correctness** — the hook cannot verify that the suggested fix is right.
  That's what the graded rubric's "actionable fix" criterion scores.

The hook enforces STRUCTURE. Promptfoo enforces QUALITY. They complement each other.

## Hook Behavior

The hook runs after the findings file is written (tool-call: file write to `<config>/reviews/*`).

```
IF file missing or empty:
    → HALT: "Findings file not written. Review did not complete."
IF required fields missing:
    → HALT: "Findings file malformed: missing [field]. Cannot proceed to gap analysis."
IF findings_count != len(findings):
    → HALT: "Findings count mismatch. File may be corrupted."
IF verdict == "pending" AND all decisions are "proposed":
    → PASS: normal state before user approval walk-through
IF verdict != "pending" AND any decision is still "proposed":
    → WARN: "Review submitted but some findings have no decision recorded."
ELSE:
    → PASS: file is well-formed, downstream can consume it
```
