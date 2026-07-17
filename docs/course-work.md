# Course Work — how this skill was built

This repo is organized **by function**, not by course module: the skill is in `skills/`, its
eval in `evals/`, supporting explanation and self-assessment in `docs/`. But it was *built* by
following the AI Self-Directed Learning course module by module, test-first, with each step in
the git history. This doc maps the course's required deliverables to where they now live and
what the commit timeline shows.

The evidence of the EDD discipline is the **commit history** — test files committed before the
prompt files they test, iterations with documented hypotheses and measured deltas. Reorganizing
into a skill-centric layout did not change that history; `git log` still reads in course order.

## Module 1 — EDD & RTCC foundations

**Required:** write test cases before any prompt; build an RTCC-structured command; set up a
promptfoo eval with two providers and a baseline; do a load-bearing audit.

| Deliverable | Now lives in |
|---|---|
| Test cases (written first) | [`evals/pr-code-review/pr-code-review-tests.md`](../evals/pr-code-review/pr-code-review-tests.md) |
| RTCC command form (the eval fixture) | [`evals/pr-code-review/pr-code-review.md`](../evals/pr-code-review/pr-code-review.md) |
| Promptfoo eval (2 providers, graded 1–5) | [`evals/pr-code-review/promptfooconfig.yaml`](../evals/pr-code-review/promptfooconfig.yaml) |
| Load-bearing audit + iteration log | in the tests file (audit + iteration sections) |

The tests file records the full progression: 5 seed cases → 27 → 40, with each prompt change
made only after a failing test justified it, and the Model Ladder baseline (Sonnet vs Haiku).

## Module 3 — Skills, hooks, governed flows

**Required:** assess skill-readiness / invocation boundaries; convert the command into a skill;
define a sentinel file schema; write a hook; test a governed flow.

| Deliverable | Now lives in |
|---|---|
| Skill-readiness + invocation-boundary analysis | [`docs/governance/skill-readiness-assessment.md`](governance/skill-readiness-assessment.md) |
| Skill mechanism notes | [`docs/governance/skill-mechanism-notes.md`](governance/skill-mechanism-notes.md) |
| Invocation tests (positive/negative/quality) | [`docs/governance/pr-code-review-skill-tests.md`](governance/pr-code-review-skill-tests.md) |
| The skill itself (canonical) | [`skills/pr-code-review/SKILL.md`](../skills/pr-code-review/SKILL.md) |
| Sentinel file schema | [`docs/governance/findings-sentinel-schema.md`](governance/findings-sentinel-schema.md) |
| Hook script | [`docs/governance/validate-findings.sh`](governance/validate-findings.sh) |
| Governed-flow test results | [`docs/governance/governed-flow-test-results.md`](governance/governed-flow-test-results.md) |

The module-3 exercise produced its own rebuild of the skill from a minimal start; that snapshot
is kept at [`docs/governance/skill-rebuild-module3-snapshot.md`](governance/skill-rebuild-module3-snapshot.md)
as a record of the exercise. The **canonical** skill used in production is
[`skills/pr-code-review/SKILL.md`](../skills/pr-code-review/SKILL.md) — the two are equivalent in
behavior; the canonical one is the fuller superset.

## Module 4 — Completion & self-assessment

**Required:** apply a handoff checklist; reflect on behavior change; self-assess against the four
DLP criteria (Craft / Evaluate / Iterate / Adopt); complete the AI Adoption Stage evaluation.

| Deliverable | Now lives in |
|---|---|
| Handoff checklist review | [`docs/self-assessment/handoff-checklist-review.md`](self-assessment/handoff-checklist-review.md) |
| Behavior-change reflection | [`docs/self-assessment/behavior-change-reflection.md`](self-assessment/behavior-change-reflection.md) |
| Completion self-assessment (4 criteria) | [`docs/self-assessment/completion-self-assessment.md`](self-assessment/completion-self-assessment.md) |
| AI Adoption Stage evaluation | [`docs/self-assessment/stage-evaluation.md`](self-assessment/stage-evaluation.md) |

> The self-assessment docs were written during the course and refer to the old `module-N/`
> paths in prose. A path note at the top of the handoff-checklist doc maps those to current
> locations; the `module-N` names are kept as the course-stage labels they described.

## Module 2 — note

Module 2 (the seven-command SDLC pipeline) was adapted rather than followed literally: the
`pr-code-review` family (review → gap-analyzer → retrospective) *is* the multi-stage pipeline,
with the same test-first discipline. This is flagged for the reviewer in the completion
self-assessment. There are no literal DevLog/Blackjack pipeline artifacts.

## The improvement loop (beyond the course)

The skill is maintained by a closed loop the course's Module 3 governance ideas map onto:

```
skills/pr-code-review  → writes findings file + review-log entry (sensor)
        ↓
docs/governance/validate-findings.sh  → validates the findings-file structure (hook)
        ↓
pr-code-review-gap-analyzer  → compares vs other reviewers, logs gaps, adds eval tests
        ↓
pr-code-review-retrospective → consolidates ≥3 reviews, edits checklist/skill, re-runs eval
        ↓
evals/pr-code-review  → verifies the change closed the gap
```

See [`skill-evaluation-workflow.md`](skill-evaluation-workflow.md) for the full evaluation and
improvement methodology.
