# pr-code-review eval

Promptfoo-based evaluation for the `pr-code-review` skill. Grades the skill's review behavior on
a suite of code snippets, scored 1–5 by an LLM grader, across two models (Sonnet + Haiku).

## Structure

```
evals/
  README.md                     ← this file
  pr-code-review/
    promptfooconfig.yaml          ← canonical eval — SKILL ON (40 cases, graded 1-5, 2 providers)
    promptfooconfig.baseline.yaml ← SKILL OFF — same 40 cases, bare model (A/B control arm)
    pr-code-review.md             ← the skill command form under test (eval fixture)
    pr-code-review-tests.md       ← the test cases in prose + the iteration/grading log
    claude.js                     ← provider + grader wrapper: shells out to the Claude CLI
    results.json                  ← last run snapshot (gitignored; the promptfoo DB is source of truth)
```

## How the skill is fed to the grader

The `pr-code-review` skill references `skills/_shared/review-checklist.md` as its rulebook. A bare
prompt of just the code would measure the raw model and ignore that rulebook. So the **canonical**
config injects both the skill command (`pr-code-review.md`) and the checklist content into the
prompt, then appends the code — the eval grades the skill *as designed*. The wrapper
[`claude.js`](pr-code-review/claude.js) routes the prompt to the Claude CLI (provider mode) and
also backs the `llm-rubric` grader (grader mode, detected by the JSON chat-array input).

## Two arms — evidence of value

| Arm | Config | Prompt fed | Measures |
|---|---|---|---|
| **Skill ON** | `promptfooconfig.yaml` | skill command + checklist + code | the skill's behavior |
| **Skill OFF** | `promptfooconfig.baseline.yaml` | code only | the bare model |

Both configs are identical except the baseline's prompt omits the skill and checklist. Same 40
snippets, same `claude.js` provider + Model Ladder (Sonnet + Haiku), same graded rubric, same
`0.75` threshold. The per-metric delta between the two runs is the skill's measured lift.

## Running

```bash
npm install -g promptfoo    # once
# Claude CLI must be installed and authenticated — claude.js shells out to it

cd pr-code-review
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # SKILL OFF
promptfoo eval -c promptfooconfig.yaml          --no-cache   # SKILL ON
promptfoo view                                               # compare per-metric scores

# Faster iteration — one provider:
promptfoo eval -c promptfooconfig.yaml --filter-providers sonnet --no-cache
```

Use `--no-cache` after editing the skill or checklist so the new behavior is regenerated and
re-graded (promptfoo caches by prompt, so an unchanged config re-runs from cache).

## Graded scoring (1–5, not pass/fail)

A custom `rubricPrompt` in `defaultTest` scores each review 1–5, normalized to 0–1:

| Rating | Score | Meaning |
|--------|-------|---------|
| 5 Excellent | 1.00 | Precise finding + impact + correct fix, no noise |
| 4 Good | 0.75 | Satisfies criterion, fix slightly thin |
| 3 Adequate | 0.50 | Vague mention or weak fix, or minor fabrication |
| 2 Poor | 0.25 | Misses the actual issue or wrong fix |
| 1 Fail | 0.00 | Misses entirely (or fabricates, for negative tests) |

`threshold: 0.75` means a test passes only at 4/5+. A barely-adequate 3/5 review fails the gate
AND shows a degraded score — catching slow quality decay that binary pass/fail hides. Each test's
`metric:` tag makes `promptfoo view` show a per-dimension scorecard (security, correctness,
resource-management, resilience, performance, licensing, false-positive-avoidance, design-fit,
api-consistency, test-quality, documentation, dependencies, library-api-contract).

## Three test categories (kept in balance)

- **Positive** — buggy code; assert the skill catches the bug.
- **Negative** — correct code; assert the skill does NOT fabricate issues. Precision matters as
  much as recall.
- **Regression/resilience** — operational-safety patterns and any case a live run got wrong.

## Grading the grader

An eval you don't audit drifts. The `grade-the-grader` skill audits this eval's grading quality —
run it every 5–10 runs, after a grader-model change, or when scores look suspicious (all-1.0 =
possibly too lenient; run-to-run swings = vague criteria). If the grader is broken, fix it before
trusting any score trend.

## Improvement loop

The strongest signal is what OTHER reviewers caught that the skill didn't. `pr-code-review-gap-analyzer`
compares the skill's review against other reviewers on the same PR, logs misses/false-positives,
and adds eval tests; `pr-code-review-retrospective` consolidates ≥3 reviews and edits the
checklist/skill, then re-runs this eval to confirm the gap closed. Misses become positive tests;
false positives become negative tests. See [`../EVALUATION.md`](../EVALUATION.md).
