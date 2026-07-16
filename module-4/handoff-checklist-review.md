# Handoff Checklist Review

Applied the "a new developer found these files cold" checklist to every committed artifact.
Failures fixed before this doc was written.

## Command file — module-1/pr-code-review.md

- [x] Comment header: what it does, when to use, input format, where the test file lives
  — **FIXED** (added HTML comment header this pass; it had none before)
- [x] Promptfoo config committed in the same directory — yes (`module-1/`)
- [x] Every instruction load-bearing (audit documented) — yes, audit in `pr-code-review-tests.md`,
  4 instructions removed; header now points to it
- [x] Test file exists and is referenced in the header — yes, header names
  `pr-code-review-tests.md`

## Promptfoo config — module-1/pr-code-review-promptfoo.yaml

- [x] Committed alongside the command it tests — yes
- [x] Comment describing product domain + constraints being tested — **FIXED** (added a header
  comment block describing the code-review domain and the recall/precision/depth constraints)

## Skill file — module-3/SKILL.md

- [x] Invocation description specific enough to know when it should/should not trigger — yes;
  `inclusion: manual` + description; boundary analysis in `skill-readiness-assessment.md`
- [x] Invocation test cases (positive + negative) committed alongside — yes,
  `pr-code-review-skill-tests.md` (3 positive, 3 negative, 3 quality)

## Sentinel schema — module-3/findings-sentinel-schema.md

- [x] Schema documented in a separate schema file — yes
- [x] Relationship between schema and promptfoo assertions documented — yes; the
  "What This Does NOT Validate" section states hook = structure, promptfoo = quality

## Hook script — module-3/validate-findings.sh

- [x] Comments explain trigger events and the decision made — yes (header comment: runs on
  findings-file write, returns pass/halt)
- [x] Failure messages clear enough to fix without reading the code — yes; each halt names the
  missing field or condition (e.g. "missing 'verdict' header", "Findings count mismatch")

## Result

Two failures found and fixed this pass: (1) the command file had no header, (2) the promptfoo
config had no domain comment. All other items already passed. Fixes are in the same commit as
this review doc.
