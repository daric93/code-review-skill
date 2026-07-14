# Evaluating the pr-code-review skill

How this skill is evaluated and kept from drifting: why the evaluation exists, how the harness
works, what the current results are, and what's next. This describes the current state, not a
history.

---

## Why evaluate a skill at all

A skill is a prompt that makes the judgment calls a human reviewer would otherwise make, and those
calls drift as the underlying model changes. Without a written definition of "good" and a way to
measure against it, a regression only shows up in a bad review that already went out. Treating the
skill like production code (a test suite, a measured baseline, a graded rubric) turns that silent
drift into a visible, dimensioned score.

A code reviewer specifically has to be measured on two axes, not one:

- **Recall** — does it catch the real bugs (injection, race conditions, resource leaks, missing
  timeouts)?
- **Precision** — does it stay quiet on correct code instead of flagging non-issues or padding a
  review with noise?

Precision is the axis most evaluations skip, and it's the one that determines whether people trust
the tool. Every dimension of this eval is therefore paired: for each class of bug the skill should
catch, there is a matching test of correct code it must not touch.

## How the evaluation works

The harness is [promptfoo](https://promptfoo.dev). Each test is a code snippet plus one specific
criterion (for example, "identifies the race condition when `increment` is called concurrently").
Both the review and the grading run through `kiro-cli`, so no separate API key is required.

**Graded, not pass/fail.** Every review is scored 1–5 and normalized to 0–1. A 5 names the issue
precisely, explains the impact, and gives a correct fix with no noise; a 3 half-mentions it or gives
a weak fix; a 1 misses it entirely (or, on a negative test, fabricates the issue). The pass
threshold is 0.75, so a test only passes at 4/5 or better, and a mediocre 3 both fails the gate and
shows as a degraded score. Every test carries a `metric:` tag, so results come back as a per-dimension
scorecard (security, correctness, resilience, resource-management, performance, licensing,
false-positive-avoidance) rather than a single number.

**Three test categories, kept in balance:**

- **Positive** — buggy code; the skill must catch the bug.
- **Negative** — correct code; the skill must not fabricate an issue.
- **Resilience / regression** — operational-safety patterns, and any case a live review once got
  wrong.

**Two arms.** The suite ships a skill arm and a baseline arm that differ by exactly one variable.
The skill arm ([`kiro-review.sh`](evals/kiro-review.sh)) injects the shared
[review checklist](skills/_shared/review-checklist.md) and the precision gates; the baseline arm
([`kiro-baseline.sh`](evals/kiro-baseline.sh)) runs the same model with no skill machinery. Same
tests, same grader, same model. The difference between the two is the skill's measured contribution.

```bash
cd evals/pr-code-review
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # skill off
promptfoo eval -c promptfooconfig.yaml          --no-cache   # skill on
promptfoo view
```

## Current results

Latest run, 29 tests, same model on both arms:

| Arm | Passed (≥4/5) |
|---|---|
| Skill on | 29 / 29 |
| Skill off (bare model) | 27 / 29 |

Per-dimension, skill minus baseline:

| Metric | Baseline | Skill | Δ |
|---|---|---|---|
| resilience | 0.86 | 1.00 | +0.14 |
| false-positive-avoidance | 0.90 | 1.00 | +0.10 |
| correctness | 0.91 | 1.00 | +0.09 |
| security | 0.95 | 0.95 | +0.00 |
| resource-management | 1.00 | 1.00 | +0.00 |
| performance | 1.00 | 1.00 | +0.00 |
| licensing | 1.00 | 1.00 | +0.00 |

The gap concentrates on the checks the checklist enforces. Representative diverging cases:

- **Retry/backoff on a transient call** — baseline 0.25, skill 1.0. The bare model handled the
  exception but did not identify the missing retry/backoff on a transient failure.
- **Silent truncation (`LIMIT 0, 10000`)** — baseline 0.25, skill 1.0. The bare model framed it as a
  performance/memory concern; the skill flags it as silent data loss.
- **Correct Rust error handling (negative test)** — baseline 0.75, skill 1.0. The bare model invented
  a concern the code already guarded; the skill's verify-before-flag gate kept it clean.

The dimensions that tie do so because both arms run the same model: on textbook cases (a plain SQL
injection, an N+1 loop) the base model already scores a perfect 5, and the skill cannot exceed it.
The skill separates on cases that require specific knowledge or review discipline the model does not
reliably supply on its own. A control that ties on easy tests and separates on hard ones is
functioning as intended.

## The components under test

The skill is not a single prompt. It composes a set of reusable pieces, all provider-neutral:

| Component | Role |
|---|---|
| [`pr-code-review`](skills/pr-code-review/SKILL.md) | The review workflow: context gathering, optional sub-agent fan-out, precision gates, inline posting, re-review. |
| [`_shared/review-checklist.md`](skills/_shared/review-checklist.md) | The rulebook — single source of truth for what to check. Editing it is how review rules change. |
| [`security-review`](skills/security-review/SKILL.md) | A focused security pass, delegated to a fresh-context sub-agent. |
| [`pr-code-review-gap-analyzer`](skills/pr-code-review-gap-analyzer/SKILL.md) | Compares a review against other reviewers on the same PR; logs misses and false positives. |
| [`pr-code-review-retrospective`](skills/pr-code-review-retrospective/SKILL.md) | Consolidates recurring gaps, edits the checklist, and re-runs the eval. |
| [`grade-the-grader`](skills/grade-the-grader/SKILL.md) | A meta-eval that audits the grader itself (leniency, strictness, consistency, inverted negative-test logic) so the scores stay trustworthy. |

## The improvement loop

The eval is a gate; it reports regressions but does not decide what to learn next, and it cannot
exercise a full multi-file review. Improvement is driven by real reviewer activity: issues other
reviewers catch on PRs this skill reviewed, and pushback on comments it posted.

- **Sensors log facts.** The gap-analyzer records misses and false positives; it does not edit rules.
- **The retrospective edits rules, on recurrence only.** A gap that appears in ≥2 PRs becomes a
  checklist change; a one-off stays a logged data point. This is the over-fitting guard.
- **Every rule change is verified by the eval.** A miss becomes a failing positive test first, and
  the rule change is what turns it green; a false positive becomes a negative test.

Large multi-step agents that are too expensive to unit-test end to end are handled the same way:
real usage surfaces gaps, which feed back into the rules, rather than scoring the whole pipeline.

## Where it improves next

- **Harder, multi-file tests.** Single-snippet tests tie on the categories where the base model is
  already strong. The cases that separate a skilled reviewer, a bug whose duplicate lives in another
  file, escaping validated against a real query engine, cross-file API inconsistency, need more than
  a five-line snippet. Those are the next tests the suite needs.
- **Guarding against the green board.** A perfect score on an easy suite reflects the difficulty of
  the tests more than the strength of the skill. New failing tests, drawn from real review misses,
  keep the suite discriminating.
- **Running the loop consistently.** The feedback system only works if gap analysis runs after the
  PRs the skill reviews. The mechanism is in place; the cadence is the work.

## Summary

The skill is measured on recall and precision with a graded rubric, against a same-model baseline
that isolates its contribution. On the current suite it passes every test and shows real per-dimension
lift over the bare model on resilience, correctness, and false-positive avoidance, with expected ties
on cases a strong base model already handles. The remaining work is harder tests and consistent use
of the improvement loop. The point of the whole setup is simple: when the skill regresses, it shows
up as a specific number dropping on a specific dimension, caught in an eval run rather than in a
posted review.
