---
name: grade-the-grader
description: Meta-evaluation. Critiques whether the pr-code-review eval's llm-rubric grader and criteria are well-calibrated — catching graders that are too lenient, too strict, vague, or inconsistent. Run periodically to keep the eval itself trustworthy.
inclusion: manual
---

# Grade the Grader

The eval grades the skill. This skill grades the eval. An eval you don't audit drifts: rubrics
get vague, the grader gets lenient, scores stop meaning anything. This is Matthias's
"separate agent critiques the grading" step.

You audit the `pr-code-review` eval's grading quality and propose concrete fixes to the rubric
criteria, the graded `rubricPrompt`, and the pass threshold.

## When to Use

- Every 5-10 eval runs, or monthly, whichever comes first
- After a model/version change to the grader (Claude version bump can shift calibration)
- When eval scores look suspicious — everything passing at 1.0 (too lenient) or oscillating
  run-to-run (inconsistent / vague criteria)
- Before trusting a score trend to make a decision about the skill

## Inputs

1. The eval config: `<config>/evals/pr-code-review/promptfooconfig.yaml`
   - The graded `rubricPrompt` template
   - Each test's `value:` criterion and `metric:`
   - The `threshold`
2. The last run's results: `<config>/evals/pr-code-review/results.json` (and/or `promptfoo view`
   history in `~/.promptfoo/output.db`) — the per-test `score`, `pass`, and grader `reason`.

## Process

### Phase 1: Pull the grading evidence

For each test in the last run, collect: the criterion, the skill's output, the score, the
pass/fail, and the grader's `reason`. The `reason` is the key artifact — it reveals HOW the
grader judged, not just the verdict.

### Phase 2: Audit each grading decision on these axes

For every test, check the grader's reasoning against its own output:

| Axis | Question | Symptom of a problem |
|------|----------|----------------------|
| **Leniency** | Did a thin/vague review score 4-5? | Grader rewards mentioning the area without the actual finding or fix |
| **Strictness** | Did a correct, complete review score <4? | Grader demands phrasing/APIs the criterion never required |
| **Criterion clarity** | Is the criterion specific enough to grade consistently? | Vague criterion ("identifies issues") that any output can satisfy |
| **Reason quality** | Does the `reason` cite specifics from the output, or is it generic? | "The review is good" with no evidence = grader didn't really read |
| **Negative-test integrity** | For "Does not flag" tests, did the grader penalize correct silence, or reward fabrication? | Inverted logic on negative tests is the most damaging failure |
| **Score/verdict coherence** | Does the numeric score match the reason? | reason describes a miss but score is 0.75 |

### Phase 3: Check calibration across the suite

- **Score distribution**: if every test scores 1.0, the grader (or threshold) is too lenient.
  A healthy suite has spread — some 1.0, some 0.75, occasional fails. All-perfect means the
  eval has stopped discriminating.
- **Consistency**: if available, compare the same test's score across the last 2-3 runs with an
  unchanged skill. Large swings (1.0 → 0.5 → 0.75) on identical input mean the criterion or
  rubricPrompt is too subjective. Recommend running `promptfoo eval --repeat 3` to quantify.
- **Metric balance**: are some `metric:` groups systematically higher? That may be real (skill
  is stronger there) or a grading artifact (those criteria are easier to satisfy vaguely).

### Phase 4: Present the audit report

```
## Grader Audit: pr-code-review eval — [date]

### Calibration summary
- Score distribution: [e.g. 8 tests at 1.0, 3 at 0.75, 1 at 0.5] — verdict: [healthy / too lenient / too strict]
- Suspected inconsistency: [tests with run-to-run swings, or "none observed"]
- Negative-test integrity: [all correct / N inverted]

### Per-test findings (only tests with an issue)

#### [test description]
- **Issue**: [leniency / strictness / vague criterion / weak reason / inverted negative / incoherent score]
- **Evidence**: [quote the grader's reason and the score]
- **Proposed fix**:
  - Criterion: [current `value:`] → [sharper `value:`]
  - and/or rubricPrompt anchor adjustment
  - and/or threshold change

### Suite-level recommendations
- [e.g. "rubricPrompt rewards vague mentions — tighten the 4-vs-3 boundary"]
- [e.g. "threshold 0.75 too lax given lenient grading — raise to 0.8 after fixing criteria"]
```

### Phase 5: Apply fixes (human-gated) and re-verify

After approval:
1. Sharpen vague **criteria** (the `value:` strings) — the most common and highest-value fix.
   Make them name the specific issue and the specific fix expected.
2. Adjust the **rubricPrompt** anchors only if the scale itself is mis-calibrated (e.g. the
   4-vs-3 line is too blurry). Edit cautiously — this affects every test.
3. Adjust the **threshold** only after criteria are fixed — never to mask a grading problem.
4. Re-run the eval and confirm scores now reflect reality:
   ```bash
   cd <config>/evals/pr-code-review && promptfoo eval
   ```
   Optionally `--repeat 3` on previously-inconsistent tests to confirm they stabilized.
5. Sync the eval config back into the repo's `evals/` so it's tracked in git (substitute `<config>` per `_shared/paths.md`):
   ```bash
   cp -r <config>/evals <repo-root>/ 2>/dev/null || true
   ```

## Relationship to other skills

- `pr-code-review-gap-analyzer` / `pr-comment-resolver` → improve the SKILL (add tests, log gaps)
- `pr-code-review-retrospective` → edits the skill prompt based on recurring gaps
- **`grade-the-grader` → improves the EVAL ITSELF** so the scores those others rely on stay honest

Order of trust: if grade-the-grader finds the grader is broken, fix the grader BEFORE acting on
any score trend — a trend from a broken grader is noise.

## Anti-Patterns

- DO NOT raise the threshold to make a lenient grader's scores "look strict" — fix the criteria/rubric first.
- DO NOT edit the rubricPrompt per-run — it's the shared scale; change it rarely and deliberately.
- DO NOT accept a grader `reason` that doesn't cite specifics as a valid grading — flag it.
- DO NOT skip the negative-test integrity check — an inverted negative test silently trains the skill to fabricate.
- DO NOT treat all-1.0 scores as success — that usually means the eval stopped discriminating.

---
> Path placeholders: `<config>` = your assistant's user-level dir (`~/.kiro` for Kiro, `~/.claude` for Claude); `<repo-root>` = this repo's checkout. See `_shared/paths.md`.
