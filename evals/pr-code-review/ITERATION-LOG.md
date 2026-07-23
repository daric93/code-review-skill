# Iteration Log — pr-code-review (EDD record)

The chronological record of how the prompt evolved: each iteration documents **baseline
scores → hypothesis → change made → measured result → reasoning**. This is the
Red/Green/Refactor evidence for the certification.

- Test case definitions (inputs + expected/failure criteria): [`pr-code-review-tests.md`](pr-code-review-tests.md)
- The prompt under test: [`pr-code-review.md`](pr-code-review.md)
- The eval that produced every score below: [`promptfooconfig.yaml`](promptfooconfig.yaml)

The "bare prompt" used as the pre-RTCC baseline:

> "Review this code diff for bugs, security issues, and quality problems. Provide actionable feedback."

## Iteration index

| # | Date | Baseline | Change | Result |
|---|---|---|---|---|
| 0 (red) | 2026-07-15 | bare prompt: 3/5 tests | wrote RTCC v1 against the 5 seed cases | 5/5 |
| 1 | 2026-07-16 | 4/5 promptfoo tests (both models) | added worst-case quantification constraint | 5/5 both models |
| — refactor | 2026-07-16 | 15/15 assertions green | load-bearing audit: removed 4 instructions | score held, prompt 48→33 lines |
| 2 | 2026-07-16 | 21/28 after resilience batch | added resilience-failure definition | 28/28 |
| 3 (no-op) | 2026-07-16 | 34-35/38, 48-52/54 | batches 3–4 passed without prompt changes | documented grader variance |
| 4 | 2026-07-16 | 48-52/54 band | structured sections: dimensions, precision gates, sibling sweep | 47-48/54 (within noise; structural value) |
| 5 (red→green) | 2026-07-16 | 10 parity cases failing by design | skill references shared checklist | 33/37 |
| 6 | 2026-07-16 | 33/37 (Case 32 precision regression) | test-quality sufficiency carve-out | 35/37, no recall regression |
| — unification | 2026-07-16 | two eval suites | merged to 40 canonical cases, graded 1–5 | 39/40 |

---

## Bare Prompt Grading Results (Sonnet, 2026-07-15)

### Test Case 1: SQL Injection — PASS

- Identifies the vulnerability with attack class and impact: **pass**
- Concrete parameterized fix showing the LIKE pattern change: **pass**
- References specific code location: **pass** (borderline — "in the query string")
- Severity rated critical: **pass**
- No fabricated additional vulnerabilities: **pass**

### Test Case 2: Correct Rust Code (False Positive Test) — FAIL

- States the code is correct / no significant issues: **fail** — presents "unbounded file read
  (DoS)" and "symlink traversal" as findings; both are speculative threat-modeling, not bugs
- Does not fabricate a bug: **fail** (same two findings)
- Acknowledges error-context preservation as a strength: pass
- Does not flag missing tests: pass

### Test Case 3: Race Condition — PASS

- Identifies the read-modify-write race and lost increments: **pass**
- Recommends the atomic Redis `INCR` (not a local lock): **pass**
- Does not fabricate an issue with `int(current or 0)`: **pass**
- Notes: adds a secondary "unvalidated key input" suggestion — borderline noise, but the
  primary finding fully satisfies the criteria

### Test Case 4: Resource Leak — PASS

- Identifies the never-called `stop()` / no-op `finally`: **pass**
- Explains connection-exhaustion impact: **pass**
- Provides the fix: **pass**
- Notes the coroutine-before-start fragility: **pass**

### Test Case 5: Silent Failure — FAIL

- Identifies silent swallowing and what to log (item identity + traceback): pass
- Explains production danger: pass
- Notes that bare `except Exception` catches programming errors (AttributeError, TypeError)
  that should crash loud rather than increment a counter: **fail** — not mentioned
- Does not claim a bug in counting logic: pass

**Result: 2 of 5 test cases fail against the bare prompt (Cases 2 and 5).** Meets the
Exercise 1 requirement of at least 2 failures.

**Grading note:** Initial grading passed Case 5; on re-check against the written criteria, the
bare output never mentions that bare `except Exception` catches programming errors — the
criterion was already in the test file, so the initial PASS was a grading error, not a criteria
change. Corrected to FAIL. Criteria were not modified after seeing bare-prompt output.

## RTCC Prompt Grading Results (Sonnet, 2026-07-15)

Prompt: `pr-code-review.md` (RTCC v1, this directory)

| Test Case | Bare Prompt | RTCC v1 | Change |
|---|---|---|---|
| 1. SQL Injection | PASS | PASS | — |
| 2. Correct Rust Code (false positive) | FAIL | PASS | Fixed: no fabricated findings, states code is correct |
| 3. Race Condition | PASS | PASS | — |
| 4. Resource Leak | PASS | PASS | — |
| 5. Silent Failure | FAIL | PASS | Fixed: explicitly names AttributeError/TypeError as swallowed programming errors |

**Result: 5 of 5 pass.** Both previously-failing cases now pass.

**What fixed Case 2:** The constraint "Do not fabricate issues based on hypothetical contexts"
and the role framing "not a threat modeler inventing hypothetical attack scenarios" stopped the
model from inventing speculative DoS/symlink findings on correct code.

**What fixed Case 5:** The constraint "assess what exception types are actually caught and whether
the catch scope is appropriate. Note when broad catches swallow programming errors" directly
instructed the depth of analysis the bare prompt missed.

## Promptfoo Baseline Run — 2026-07-15

Config: `pr-code-review-promptfoo.yaml` (5 tests, 15 assertions total)

| Model | Tests Passing | Failing Test |
|---|---|---|
| Sonnet | 4/5 | Case 3 (race condition) — correctness-depth assertion |
| Haiku | 4/5 | Case 3 (race condition) — correctness-depth assertion |

**Model Ladder delta: 0 assertions.** Both models fail on the same criterion — the
quantification requirement ("at N concurrent requests, up to N-1 can be lost"). Both models
describe the race abstractly ("counts can be lost under concurrency") but neither provides
the specific numeric bound.

### Delta hypotheses

"The `correctness-depth` assertion fails on both models. My hypothesis: the RTCC prompt's
constraint says 'explain the production impact' but never instructs the model to quantify
worst-case data loss with a concrete bound. If I add a constraint like 'When a race condition
can cause data loss, state the worst-case loss rate as a function of concurrent requests' to
the Constraints section, I predict both models will pass this assertion."

### Rubric examination (identical scores on both models)

The guide flags a zero delta as suspicious: either the assertions don't discriminate, or the
prompt is already well-specified. Examination of the rubrics:

- The RTCC prompt was built in Exercise 2 directly against these 5 test cases, iterating until
  all passed on Sonnet. The prompt is therefore unusually well-specified *for these specific
  inputs* — each constraint exists because one of these cases failed without it.
- The assertions do discriminate against the bare model (2/5 bare-prompt failures in Exercise 1)
  and against depth (the correctness-depth assertion fails both models), so they are not
  trivially passable.
- What the zero delta means: on inputs the prompt was tuned against, Haiku can follow the same
  explicit instructions Sonnet can. The model gap is expected to appear on *unseen* inputs and
  under *instruction removal* — both of which Exercise 4's load-bearing audit and Model Ladder
  test directly. If no delta appears there either, the rubrics need strengthening.

### Weakest assertion

`correctness-depth` on Case 3 is the only failing assertion across both models. Iteration
target for Exercise 4: add a quantification instruction to the prompt and verify it causes
this test to pass without regressing the others.

## Exercise 4 — Iteration Record

### Iteration 1 — 2026-07-16

Hypothesis: "The correctness-depth assertion fails on both models because the prompt says
'explain the production impact' but never instructs quantification of worst-case data loss."

Change: Added to Constraints: "When a race condition or data-loss bug is found, quantify the
worst case: state how many operations can be lost as a function of concurrent requests."

Sonnet: 4/5 → 5/5 assertions passing
Haiku:  4/5 → 5/5 assertions passing
Failing assertions remaining: none

## Green State (Sonnet) — 2026-07-16

Sonnet score: 5/5 tests passing (15/15 assertions)
Haiku score:  5/5 tests passing (15/15 assertions)
Model Ladder delta at Green: 0 assertions
Iterations from baseline: 1

## Load-Bearing Audit — pr-code-review.md — 2026-07-16

| Instruction | Predicted Load-Bearing Assertion | Tested | Result |
|---|---|---|---|
| "Do not flag code for missing tests, docs, or style" | None — candidate for removal | Yes | Removed — score held (10/10) |
| "Do not fabricate issues based on hypothetical contexts..." (full sentence) | Case 2 false-positive-avoidance | Yes | Score held — redundant with other framing |
| "not a linter, not a style guide enforcer, not a threat modeler" (role detail) | Case 2 false-positive-avoidance | Yes | Score held — redundant with constraints |
| "scoped to what the diff reveals" (context paragraph) | Case 2 false-positive-avoidance | Yes | Score held — redundant with constraints |
| "domain-appropriate primitive (Redis INCR...)" | Case 3 correctness-fix | Yes | Score held — models infer INCR already |
| "quantify worst case... N-1 increments" | Case 3 correctness-depth | Yes | Load-bearing in trimmed prompt — Case 3 failed when removed alongside other cuts |
| "except Exception swallows programming errors" | Case 5 resilience | Yes | Kept — Case 5 failed on both models without it |
| "When code is correct, say so explicitly" | Case 2 false-positive-avoidance | Yes | Kept — Case 4 failed on Sonnet without it (unexpected) |

**Instructions removed:** 4 (no-flag-tests, no-fabricate sentence, threat-modeler role
detail, scope-to-diff context paragraph)

**Instructions kept (load-bearing):** 5 (verifiable-from-code, location+impact+fix format,
quantify-worst-case, exception-handling depth, say-correct-explicitly)

**Prompt reduced from 48 lines to 33 lines** — every remaining sentence has a test that fails
without it.

## Model Ladder Audit — pr-code-review.md — 2026-07-16

Starting delta: 0 assertions (Sonnet and Haiku identical at Green)

No Haiku-only failures to diagnose. Both models pass all 15 assertions on the trimmed,
load-bearing-audited prompt. This means:
- The remaining instructions are explicit enough for Haiku to follow without inference
- Sonnet is not silently filling gaps that Haiku misses on these test cases
- Future test cases from unseen domains are the expected source of model-gap signals

Final delta: 0 assertions
Decision: No Haiku failures to address. The delta will be revisited when new test cases are
added in Module 2 from unfamiliar code domains (the prompt was purpose-built for these 5).

## Reflection

1. **Most surprising load-bearing instruction:** "When code is correct, say so explicitly."
   Expected it to be about Case 2 (false-positive); instead Case 4 (resource leak) on Sonnet
   broke — without explicit "say correct if correct," the model apparently felt pressure to
   find something wrong even in the DataService code and generated noise about the correct
   `pool.acquire()` pattern.

2. **Most surprising dead weight:** The fabrication constraint ("Do not fabricate issues based
   on hypothetical contexts") — a 2.5-line instruction with an example. It was the most
   detailed single constraint, yet entirely redundant once the role and task established the
   intent. The model understood "catch real bugs" and "verifiable from the code" without needing
   the anti-pattern spelled out separately.

3. **What Haiku failures told about Sonnet inference:** Nothing yet — both models behave
   identically on this prompt. The prompt is explicit enough to eliminate model-gap on these
   cases. The real Sonnet-inference signal will come from unseen inputs where the prompt's
   specificity doesn't directly match.

4. **Gaps closed vs accepted:** No gaps to close (zero delta). Accepted that this prompt is
   fully specified for its current 5 test cases. The next gap-surface opportunity is
   Module 2's stress tests on unfamiliar domains.

## Test Expansion — EDD Iterations

### Batch 1: False-Positive Tests (Cases 6-9) — 2026-07-16

Added 4 tests: correct Optional[int], correct async context manager, correct env-var secret,
correct pure function. All passed without prompt changes — the existing precision constraints
("verifiable from the code shown" + "say so explicitly when correct") are sufficient.

Score: 18/18 (9 tests × 2 models)

### Batch 2: Resilience Tests (Cases 10-14) — 2026-07-16

Added 5 tests: silent fallback, missing gRPC deadline, no retry/backoff, unbounded SCAN,
cleanup skipped on early return.

Before prompt change: 21/28 (7 failures). Root cause: prompt had no resilience definition.

Iteration 2: Added resilience-failure definition to Task section (timeouts, silent fallbacks,
unbounded iteration, missing retries, skipped cleanup). Also widened 2 rubrics to accept
alternative valid findings (narrowing try/except is as valid as logging for the fallback;
timeout is as valid as retry for the publish call).

After: 28/28. One prompt change closed 7 failures.

### Batch 3: Correctness + Resource Management Tests (Cases 15-19) — 2026-07-16

Added 5 tests: HTTP error handling, React stale closure, sync-over-async, close() missing
pool, unawaited async close.

Score: 34-35/38 (92%+). Remaining 2-4 failures are grading variance (different runs produce
different failure counts on the same prompt). Confirmed by manual retesting — the skill
produces correct reviews, the grader is occasionally harsh.

### Batch 4: Domain-Specific + Hard Cases (Cases 20-27) — 2026-07-16

Added 8 tests: ValkeySearch injection, missing Redis timeout, hardcoded credential, silent
truncation, Optional[int] truthiness, N+1 query, GPL-in-MIT licensing, sibling-parity
escaping.

Score: 48-52/54 (89-96%). No prompt change needed — existing constraints handle all new
categories. Remaining variance is grading noise.

### Summary After Full Expansion

| Metric | Count |
|---|---|
| Total tests | 27 |
| Assertions per run | 54 (27 tests × 2 models) |
| Prompt iterations to reach green | 2 (quantification + resilience) |
| Instructions in prompt | 5 constraints + role/task/context |
| Consistent pass rate | 90-96% (variance is grading, not skill)

### Iteration 4 — Skill Structure Expansion — 2026-07-16

Change: Expanded the flat constraint list into structured sections — review dimensions
(severity-ordered: security → correctness → resource-management → resilience → performance
→ licensing), precision gates (verify-before-flag, scope discipline, sibling sweep), finding
format, and depth rules.

Scores across 3 runs on the expanded prompt: 48/54, 47/54 (87-89%). Pre-expansion band was
48-52/54. Within noise for the sample size — no regression, but no measured lift either. The
expansion's value is structural (it makes the prompt extensible toward the full skill
architecture), not score-driven.

**Known grader variance:** The same prompt scores differently across runs (5-point band).
The flakiest rubrics are the HTTP error-handling and silent-fallback cases, where the model
produces a correct review that the grader scores 3/5 ("adequate") on some runs and 4/5
("good") on others. This is a documented eval-quality finding — the production toolkit
addresses it with a grade-the-grader meta-eval that audits grading consistency.

## Full-Parity Expansion (Cases 28–37) — Green Phase — 2026-07-16

The 10 parity cases (definitions and rationale in
[`pr-code-review-tests.md`](pr-code-review-tests.md)) were committed **before** the skill was
wired to the shared checklist — the red phase. This section records the green phase and the
iteration it forced.

### Green-phase result (Sonnet, checklist injected) — 2026-07-16

Ran all 37 cases on Sonnet after wiring the skill to the shared checklist: **33/37 pass.**

- **9 of 10 new parity cases pass** (28, 29, 30, 31, 33, 34, 35, 36, 37) — the recall gaps for
  design-fit, API consistency, library-API contract, test quality, documentation, dependencies,
  performance, and over-engineering are now closed by the checklist reference.
- **Case 32 fails** (`false-positive-avoidance`): given two correct, well-asserted slugify
  tests, the reviewer suggested additional/edge-case tests instead of staying silent. This is
  the predicted risk — the checklist's "Test Quality & Coverage" section ("edge cases tested?
  compare coverage with equivalent implementations") pulls the model toward demanding more of
  already-adequate tests. **Real precision regression introduced by the expansion; addressed in
  the next iteration.**
- The other 3 failures (cases 4, 5, 7) are pre-existing flaky cases in the documented
  grader-variance band (HTTP error-handling, silent-failure, async-context-manager), not
  regressions from this change.

Hypothesis for the fix: the skill's scope-discipline constraint needs an explicit test-quality
carve-out — "do not demand more tests when existing tests already assert observable behavior" —
strong enough to override the checklist's recall pull.

### Iteration — test-quality precision carve-out — 2026-07-16

Change (one, per the one-change rule): added a "Sufficiency over completeness (test code)"
constraint to `pr-code-review.md` — the checklist's test-quality checks catch tests that assert
*nothing* or the *wrong* thing, not tests that could theoretically cover more; "could add more
tests" is not a finding.

Re-ran all 37 on Sonnet: **35/37 pass.**
- Case 32 now passes — the reviewer stays silent on the two correct slugify tests.
- Case 31 still passes — the carve-out did NOT suppress the real test-quality recall (a test
  that asserts nothing is still flagged). Precision fix without a recall regression.
- Remaining 2 failures (Case 4 HTTP error-handling, Case 7 async context manager) are the
  documented pre-existing grader-variance cases — not regressions, not part of this expansion.

Net: full-parity expansion complete. Recall extended to all checklist categories; precision
held (false-positive-avoidance metric back to clean on the parity cases).

### Eval unification — merge to single canonical suite + graded 1-5 — 2026-07-16

Consolidated the two evals that existed for this one skill: this 37-case course-built suite and
the prior 29-case live toolkit eval. This suite is now **canonical** (better coverage — it adds
design-fit, API-consistency, test-quality, docs, dependencies — and it runs two providers for
the Model Ladder, which the live single-provider eval lacked).

Two changes:
1. **Folded in the 3 cases unique to the live eval** (cases 38-40): operator-not-handled-in-delete
   (CRUD operator parity), missing-TLS+auth-for-cloud-cache (cloud readiness), naive-escaping-of-
   FT-TEXT-phrase (a distinct escape context from the TAG cases 20/27). The other live cases
   already had equivalents here, so only these three added coverage. Suite is now **40 cases**.
2. **Converted scoring from binary `llm-rubric` to graded 1-5** (threshold 0.75), matching what
   RUBRIC.md and the README already documented. Ported the `rubricPrompt` + normalization from
   the live eval. Each test's `value:` is unchanged — it becomes the `{{rubric}}` the 1-5 grader
   scores against. A 3/5 "sort of" review now fails the gate and shows a degraded score instead
   of passing silently.

Graded result (Sonnet, 40 cases): **39/40.**
- 37 cases score a clean 1.00.
- Case 7 (correct async context manager) scores **0.625** — the documented borderline FP case;
  graded scoring surfaces it as degraded rather than a silent pass. This is the method working.
- Case 16 (React stale closure) hit a transient grader glitch ("could not extract JSON from
  llm-rubric response") and scored 0 on that run; **re-run in isolation it scores 1.00** — a
  grader-parse flake, not a skill failure.

**Grader-calibration note (for grade-the-grader):** 37 of 40 at a perfect 1.00 is the "all-1.0"
signal `grade-the-grader` flags — the graded scale may not be discriminating hard enough on the
strong cases. Left as a documented meta-eval input, not fixed here.
