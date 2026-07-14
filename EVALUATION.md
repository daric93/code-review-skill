# Evaluating the pr-code-review skill

How this skill is evaluated and kept from drifting: why the evaluation exists, how the harness
works, what the current results are, how the real-world improvement loop runs end to end, and
what's next. This describes the current state.

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

**Three test categories, kept in balance:** positive (buggy code, must catch), negative (correct
code, must not fabricate), and resilience/regression (operational-safety patterns, and any case a
live review once got wrong).

**Two arms.** The suite ships a skill arm and a baseline arm that differ by exactly one variable.
The skill arm ([`kiro-review.sh`](evals/kiro-review.sh)) injects the shared
[review checklist](skills/_shared/review-checklist.md) and the precision gates; the baseline arm
([`kiro-baseline.sh`](evals/kiro-baseline.sh)) runs the same model with no skill machinery. The
difference between the two is the skill's measured contribution.

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

The gap concentrates on the checks the checklist enforces (retry/backoff on a transient call: 0.25
baseline vs 1.0 skill; a hardcoded `LIMIT 0, 10000` flagged as silent data loss rather than a mere
performance note: 0.25 vs 1.0). The dimensions that tie do so because both arms run the same model:
on textbook cases the base model already scores a perfect 5, and the skill cannot exceed it. The
skill separates on cases that require specific knowledge or review discipline the model does not
reliably supply on its own.

## The improvement loop, end to end

The eval is a gate: it reports regressions but does not decide what to learn next, and it cannot
exercise a full multi-file review. The learning signal comes from real reviewer activity — what
other reviewers catch on the same PRs this skill reviewed. Here is the whole cycle with real
artifacts from live runs.

### Step 1 — a review runs and logs itself

Running `pr-code-review` on a PR produces a durable review and appends one entry to the review log
(`pr-review-log.md`), the cross-PR index. A real entry:

```markdown
## ENTRY 2026-07-02 | edlng/gateway#1
- pr_url: https://github.com/edlng/gateway/pull/1
- findings_file: ~/.kiro/reviews/2026-07-02__edlng__gateway__pr1.md
- verdict: REQUEST_CHANGES
- found: 8 (3 security/blocking, 1 correctness/blocking, 4 suggestions)
- posted: 8 / skipped: 0
- gap_analyzed: yes
```

### Step 2 — every finding is persisted before anything is posted

Before posting, the skill writes a findings file with every candidate finding, including ones it
later decides not to post. This is the source of truth the gap analysis reads. One finding from that
same PR's file:

```markdown
---
pr_url: https://github.com/edlng/gateway/pull/1
repo: edlng/gateway
head_sha: 87e374634dd783ca3c5ea1f7db596eb6ebfbdceb
verdict: REQUEST_CHANGES
---

## Finding 1
- id: password-in-client-cache-key
- lens: Correctness & Security
- file: src/providers/valkey-search/handlers.ts
- line_range: 37-62
- severity: blocking
- claim: The full customHost URL (including any embedded password) is used verbatim as the
  Map key in clientCache, so a heap dump or debug log that enumerates Map keys exposes
  plaintext credentials.
- suggested_fix: Hash the address before using it as a key (createHash('sha256')...).
- decision: posted

... (Findings 2–8) ...

posted: 8 / skipped: 0 / total: 8
```

Each finding records its `decision` (`posted` or `skipped`, with a `skip_reason`). That distinction
matters later: a later-caught issue that was **absent** from the file is a *detection* miss, while
one that was present but `skipped` is a *judgment* miss — the two need different fixes.

### Step 3 — gap analysis scores the review against other reviewers

Once other reviewers have commented, `pr-code-review-gap-analyzer` compares this review against
theirs on the same PR, computes recall and precision, and appends a per-PR entry plus a row to the
trend table in `review-gaps-retro.md`. Real rows:

```markdown
| Date       | PR                          | Recall     | Precision | Misses | False Pos | Maint. misses |
|------------|-----------------------------|------------|-----------|--------|-----------|---------------|
| 2026-07-02 | edlng/gateway#1             | 88% (7/8)  | 88% (7/8) | 1      | 1         | 0             |
| 2026-07-02 | MatthiasHowellYopp/agentscope#2 | 100% (9/9) | 100% (9/9)| 0    | 0         | 0             |
```

For the gateway PR that produced one miss and one false positive, the analyzer logs each as a
concrete, categorized candidate — never editing any rule itself:

- **Miss (detection):** `getCacheKey` omits `organisationId`, so two tenants issuing identical
  requests can share a cached LLM response. Proposed rule: *flag a multi-tenant cache key that omits
  a tenant/scope identifier that is in scope for the request.*
- **False positive:** the review flagged an un-awaited `close?.()` in `setBackend` as a blocking
  leak, but the object being closed is a no-op placeholder and the library's `close()` is
  synchronous. Proposed counter-rule: *don't flag a fire-and-forget `close()` without confirming the
  target is a live async resource.*

### Step 4 — the retrospective decides what actually becomes a rule

`pr-code-review-retrospective` is the only step that edits rules. It walks the review log, and once
at least three reviews are unprocessed it drives the gap analyzer over each, then consolidates the
results across all PRs (not just the current batch). Its core decision is **pattern vs one-off**:

- A gap that appears in **≥2 distinct PRs** becomes a checklist change.
- A gap seen in only **one** PR is *held* — the eval test that encodes it stays on record, and it is
  re-examined on every future retrospective, but no rule is written yet. (Exception: a P0
  security/correctness miss a maintainer caught can be fast-tracked.)
- Every rule change is verified by re-running the eval before it is kept, and the processed reviews
  are recorded in a ledger so nothing is analyzed twice.

This over-fitting guard is visible in the processed-entries ledger — most single-PR gaps were
deliberately **held, not turned into rules**:

```markdown
- ENTRY 2026-07-02 | edlng/gateway#1 — held (single-PR; no rule added)
- ENTRY 2026-06-30 | atao2004/unstructured-ingest#1 (run 2) — held (single-PR; no rule added)
- ENTRY 2026-07-02 | MatthiasHowellYopp/agentscope#2 — no gaps (100%/100%)
- ENTRY 2026-06-30 | atao2004/unstructured-ingest#1 (run 3) — FOLDED into pr-code-review Re-Review verification-depth guardrail
```

So on this batch, the gateway miss and false positive above did **not** change any rule: each was a
one-off, so both were held for recurrence. That is the guard working — one reviewer's single
observation does not become permanent doctrine.

### Step 5 — the file change, when a pattern does recur

One gap in the batch *was* systemic and did produce an edit. Across the `unstructured-ingest`
re-reviews, the skill repeatedly confirmed a fix existed without checking the newly-added code was
correct, and a maintainer then found real bugs inside that new code. That recurring pattern was
folded into the `pr-code-review` skill as a re-review guardrail. The applied change (excerpt):

```markdown
Re-scan newly-added code (do not just diff the flagged lines). When a fix introduces new code —
a new method, branch, helper, or file — treat that new code as a first-pass review target: apply
the full review checklist to it, not only a check that the original comment's intent was met.
Verifying a fix was added without re-scanning what it added is the single most common re-review miss.
```

Because rule changes land in the shared [`review-checklist.md`](skills/_shared/review-checklist.md)
(or, for workflow like the above, the skill body), the eval covers them directly: a new positive
test encodes the gap, and the rule change is what turns that test green.

## Where it improves next

- **Harder, multi-file tests.** Single-snippet tests tie on the categories where the base model is
  already strong. The cases that separate a skilled reviewer — a bug whose duplicate lives in another
  file, escaping validated against a real query engine, cross-file API inconsistency — need more than
  a five-line snippet.
- **Guarding against the green board.** A perfect score on an easy suite reflects the difficulty of
  the tests more than the strength of the skill. New failing tests, drawn from real review misses,
  keep the suite discriminating.
- **Running the loop consistently.** The feedback system only works if gap analysis runs after the
  PRs the skill reviews. The mechanism is in place; the cadence is the work.

## Summary

The skill is measured on recall and precision with a graded rubric, against a same-model baseline
that isolates its contribution. On the current suite it passes every test and shows real
per-dimension lift over the bare model on resilience, correctness, and false-positive avoidance,
with expected ties where a strong base model already suffices. Beyond the unit tests, a closed loop
turns real reviewer activity into scored gaps, holds one-offs, promotes only recurring patterns into
rules, and verifies every change on the eval. When the skill regresses, it shows up as a specific
number dropping on a specific dimension, caught in an eval run rather than in a posted review.
