# Evaluation Rubric — pr-code-review

How the `pr-code-review` skill is scored, what "good" means per dimension, and the methodology
for improving it. This is the grading contract the [eval](evals/pr-code-review/) enforces
and the standard a certifier can hold the skill to.

---

## 1. Scoring scale (graded, 1–5 → normalized 0–1)

Every test grades the skill's review against **one** criterion on this scale. The grader prompt
that enforces it lives in `defaultTest.rubricPrompt` of
[`promptfooconfig.yaml`](evals/pr-code-review/promptfooconfig.yaml).

| Rating | Normalized | Meaning |
|---|---|---|
| **5 Excellent** | 1.00 | Precise finding (or correct silence, for negative tests) + impact + correct, actionable fix. No noise. |
| **4 Good** | 0.75 | Satisfies the criterion; fix slightly thin or imprecise. Minor noise acceptable. |
| **3 Adequate** | 0.50 | Vague mention, buried finding, weak/partial fix, or minor fabrication. |
| **2 Poor** | 0.25 | Misses the actual issue, wrong recommendation, or fabricates a significant non-issue. |
| **1 Fail** | 0.00 | Misses entirely; or (negative test) fabricates the issue it should have ignored. |

**Pass threshold: `0.75`** — a test passes only at **4/5 or better**. A 3/5 "sort of" review
fails the gate *and* shows a degraded score, so slow quality decay surfaces instead of hiding
behind binary pass/fail.

---

## 2. Scoring dimensions (metrics)

Each test is tagged with a `metric:` so `promptfoo view` renders a per-dimension scorecard. A
dimension trending below ~0.8 is the weakest area of the skill and is where the next edit goes.

| Metric | What it grades | Example test |
|---|---|---|
| `security` | injection, escaping completeness, secret handling | SQL injection via f-string; FT.SEARCH tag/phrase escaping; hardcoded credential |
| `correctness` | logic errors, races, error handling, silent failures | read-modify-write race; sync-over-async; `Optional[int]` truthiness dropping 0 |
| `resource-management` | leaks, cleanup on all paths, awaited async close | `close()` misses `_pool`; unawaited async `close()` |
| `resilience` | timeouts, retries/backoff, fallbacks, unbounded iteration, cloud readiness | missing gRPC deadline; silent cache fallback; unbounded SCAN |
| `performance` | round-trips, N+1, allocations (measurable impact only) | N+1 query in a loop |
| `licensing` | dependency license compatibility | GPL dep added to an MIT project |
| `false-positive-avoidance` | **negative tests** — must NOT fabricate issues in correct code | correct `is not None`; correct async context managers; secret from env |

Positive dimensions test **recall**; `false-positive-avoidance` tests **precision**. Both are
first-class — the skill is not "good" if it wins one at the expense of the other.

---

## 3. Evidence of value — baseline vs skill

The rubric is applied to **two arms** on identical tests, model, and grader:

- **Baseline (skill OFF):** [`promptfooconfig.baseline.yaml`](evals/pr-code-review/promptfooconfig.baseline.yaml)
  — the bare model gets only the code (no skill, no checklist).
- **Skill ON:** [`promptfooconfig.yaml`](evals/pr-code-review/promptfooconfig.yaml)
  — the skill command + shared checklist are injected. Same `claude.js` provider and grader.

The **delta in per-metric scores** between the two runs is the skill's measured value-add. The
baseline is the honest control: if a dimension shows no lift over the bare model, the skill's
rules for that dimension aren't earning their place.

> Record each A/B run's per-metric numbers in a dated row so the lift is auditable over time.
> `promptfoo view` keeps full run history in `~/.promptfoo/output.db`.

---

## 4. Test-design rules

- **Keep all three categories present** — positive, negative, resilience/regression. Never let
  the negative (precision) tests erode; false positives destroy trust faster than misses.
- **One criterion per test.** The rubric grades against a single, specific expectation. Vague
  criteria ("mentions thread safety") pass shallow reviews; write actionable criteria
  ("identifies the read-modify-write race on `self.count` and recommends a lock or atomic op").
- **Accept equivalent correct answers.** Criteria describe *intent*, not exact wording, and
  explicitly allow any technically correct remediation (see the sync-over-async test).
- **Every live miss becomes a test first, then a fix.** Regression tests are the highest-value
  tests over time.
- Some checklist categories (API consistency, test coverage, dependency CVEs, design fit,
  documentation) need project-level context a snippet can't supply — they are **deliberately
  exercised by full PR runs**, not snippet rubrics. This omission is documented in the config.

---

## 5. Improvement methodology (how a score becomes a better skill)

1. **Sense** — after PRs I review, `pr-code-review-gap-analyzer` compares my review against other
   reviewers (misses → positive test candidates; false positives → negative test candidates).
   After PRs I author, `pr-comment-resolver` logs the detectable issues. Both write to
   `review-gaps-retro.md`. Sensors **log and add tests only** — they never edit rules.
2. **Analyze** — every ~3 PRs, `pr-code-review-retrospective` reads the accumulated gaps and
   separates **patterns** (a gap in ≥2 PRs) from **one-offs**. Only patterns earn a rule edit
   (over-fitting guard); a one-off leaves its eval test failing until it recurs — except a P0
   security/correctness miss caught by a maintainer.
3. **Edit** — the rule change is made in the **shared checklist**
   ([`_shared/review-checklist.md`](skills/_shared/review-checklist.md)), not scattered
   into the skill, so both the PR reviewer and the Valkey self-reviewer inherit it.
4. **Verify** — re-run the eval. Previously-failing positive tests must now pass, and **no
   negative test may regress**. An unverified edit is an unproven edit.
5. **Audit the grader** — every 5–10 runs (or after a grader-model change), `grade-the-grader`
   checks the grader for leniency, over-strictness, vague criteria, and inverted negative-test
   logic. If the grader is broken, fix it before trusting any score trend.

---

## 6. Anti-patterns (what this rubric refuses to do)

- Don't optimize recall alone — protect precision with negative tests, or the skill cries wolf.
- Don't let a sensor edit rules — only the retrospective does, and only on recurrence.
- Don't add a rule for a one-off gap — wait for it to recur (except P0 maintainer catches).
- Don't skip the eval run after an edit.
- Don't discard the recall/precision trend when archiving retros — it's the long-term signal.
- Don't eval multi-step agent pipelines with promptfoo — evals stay on atomic skills; pipelines
  use the retro loop (cost discipline).
