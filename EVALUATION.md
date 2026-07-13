# Treating an AI code-review skill like production code

*How I evaluate and keep a code-review skill honest — with a test suite, a baseline, a graded
rubric, and a feedback loop driven by real reviewer activity.*

---

Most AI review prompts are written once and never measured. They drift silently as models change,
and nobody notices until the reviews get worse. I wanted the opposite: a code-review skill I could
*score*, catch when it regresses, and improve deliberately. So I treat it like production code —
it has a test suite, a measured baseline, and a rubric.

This is the short version of how that works, with real numbers from a recent run.

## The two ways a reviewer fails

A review assistant fails in two directions, and most people only measure one:

- **Misses (low recall).** It doesn't catch the SQL injection, the race condition, the leaked
  connection. Obvious, and usually the only thing people test.
- **False positives (low precision).** It flags *correct* code — "this `is not None` check is
  wrong!" — and buries the two real issues under ten fake ones. One hallucinated comment and the
  author stops trusting the whole review.

Precision is the one everyone forgets, and it's the one that kills adoption. So every dimension of
my eval is paired: for each class of bug the skill *should* catch, there's a "correct code it must
**not** flag" test.

## The harness

The skill under test is [`pr-code-review`](skills/pr-code-review/SKILL.md). The eval is a
[promptfoo](https://promptfoo.dev) suite. The clever bit is that both the *review* and the
*grading* run through `kiro-cli`, so there's no separate API key — it rides my existing
subscription.

Each test is a small code snippet plus a single, specific criterion. For example:

```yaml
- description: "race condition on read-modify-write"
  vars:
    prompt: |
      Review this code used in a multi-threaded web server:
      ```python
      class Counter:
          def __init__(self): self.count = 0
          def increment(self):
              current = self.count
              self.count = current + 1
      ```
  assert:
    - type: llm-rubric
      value: "Identifies the race condition when increment is called concurrently."
      metric: correctness
```

Three kinds of tests, always kept in balance: **positive** (buggy code, must catch),
**negative** (correct code, must stay quiet), and **resilience/regression** (operational-safety
patterns and anything a live run once got wrong).

## Graded, not pass/fail

Binary pass/fail hides slow decay. A review that "sort of" mentions the bug passes — and you never
see quality erode. So a custom rubric grades every review **1–5**, normalized to 0–1:

| 5 → 1.00 | 4 → 0.75 | 3 → 0.50 | 2 → 0.25 | 1 → 0.00 |
|---|---|---|---|---|
| precise + impact + correct fix | correct, fix a bit thin | vague / weak fix / minor noise | misses or wrong fix | misses entirely (or fabricates, on a negative test) |

The pass threshold is **0.75** — a test only passes at 4/5 or better. A barely-adequate 3/5 fails
the gate *and* shows a declining score. Every test carries a `metric:` tag, so the results break
out into a per-dimension scorecard instead of one meaningless number.

## A real run

Here's the suite from **2026-07-03** — 27 tests, all through `kiro-cli`:

| Metric | Tests | Avg score |
|---|---|---|
| correctness | 8 | 1.00 |
| resilience | 7 | 1.00 |
| security | 4 | **0.94** |
| false-positive-avoidance | 4 | 1.00 |
| resource-management | 2 | 1.00 |
| performance | 1 | 1.00 |
| licensing | 1 | 1.00 |
| **Total** | **27** | **27/27 pass** |

The grader's reasoning is the useful artifact, not the number. On the SQL-injection test it wrote:

> *"The review precisely identifies the SQL injection risk from f-string interpolation, provides
> concrete attack examples (OR 1=1, table drops, data exfiltration), and gives a correct,
> actionable parameterized query fix…"*

And — crucially — on the negative test, it confirmed the skill stayed quiet on correct code:

> *"The review correctly does not flag 'is not None' as an issue. It explicitly affirms the guard
> is correct, explains why 'if limit:' would be wrong (silently ignoring 0), and concludes with no
> issues found."*

That's precision working: the skill didn't invent a bug where there wasn't one.

## Why "all green" is a smell, not a victory

Twenty-seven for twenty-seven looks like a win. It's also exactly what a *too-lenient grader*
produces. So I distrust green by default, and two mechanisms keep it honest.

**First, the one non-perfect score is the interesting one.** The `security` metric came in at 0.94
because the "hardcoded credential" test scored 4/5, not 5. The grader explained:

> *"…identifies the hardcoded live API key, explains the impact clearly … and provides two
> correct, actionable fixes using environment variables. It does not explicitly recommend rotating
> the exposed key or note it should never have been committed, which are bonus criteria, but the
> core criterion is fully and strongly satisfied."*

That's the rubric doing its job — a strong-but-not-perfect review scores 4, not a rubber-stamp 5.
It also tells me exactly what to sharpen (rotate-the-key guidance) if I want that dimension green.

**Second, I built a meta-eval.** [`grade-the-grader`](skills/grade-the-grader/SKILL.md) audits the
grader itself — is it too lenient, too strict, inconsistent run-to-run, or (worst of all) inverted
on negative tests? An eval you don't audit drifts. If the grader is broken, you fix it *before*
trusting any trend.

## The missing control: baseline vs skill

A score in isolation doesn't prove the *skill* did anything — a strong base model might score well
on its own. So the suite ships two arms that differ by exactly one variable:

- **Skill ON** ([`promptfooconfig.yaml`](evals/pr-code-review/promptfooconfig.yaml)) — injects the
  shared checklist and the precision gates.
- **Skill OFF** ([`promptfooconfig.baseline.yaml`](evals/pr-code-review/promptfooconfig.baseline.yaml))
  — same model, same tests, same grader, no skill machinery.

Run both; the per-metric delta is the skill's measured value-add — evidence, not a claim.

```bash
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # SKILL OFF
promptfoo eval -c promptfooconfig.yaml          --no-cache   # SKILL ON
promptfoo view
```

| Metric | Baseline (skill off) | Skill on |
|---|---|---|
| security | _run to fill_ | 0.94 |
| correctness | _run to fill_ | 1.00 |
| false-positive-avoidance | _run to fill_ | 1.00 |
| resilience | _run to fill_ | 1.00 |

*(The skill-on column is real from the 2026-07-03 run; drop in your baseline numbers after a
control run to complete the comparison.)*

## The loop that keeps it sharp

The eval is the gate. The improvement signal is **real reviewer activity** — what other reviewers
caught that my skill didn't:

```
PRs I review  → pr-code-review → others comment → pr-code-review-gap-analyzer ┐
                                (misses, false positives, recall/precision)    ├→ gaps log
every ~3 PRs  →                            pr-code-review-retrospective ───────┘
              (consolidate → edit the shared rulebook → re-run the eval → sync)
```

Two rules keep this from degenerating:

1. **Sensors don't edit rules.** The gap-analyzer only logs facts and proposes tests. Only the
   retrospective edits the rulebook — and only when a gap recurs across **≥2 PRs** (an
   over-fitting guard, so one reviewer's pet peeve doesn't become a permanent rule).
2. **Every edit is verified by re-running the eval.** A miss becomes a *failing positive test*
   first; the rule change is what turns it green. A false positive becomes a *negative test*. An
   unverified edit is an unproven edit.

## Takeaways

- **Measure precision, not just recall.** Pair every "must catch" with a "must not flag."
- **Grade on a scale.** Binary pass/fail hides decay; a 3/5 that still "passes" is a warning.
- **Distrust all-green.** Audit the grader; a green suite with a broken grader is noise.
- **Keep a control.** Baseline-vs-skill turns "it feels better" into a number.
- **Improve on recurrence, verify on the eval.** Real reviewer gaps in, verified rule changes out.

The point isn't the 27/27. It's that when the skill *does* regress — a model bump, a rule that got
too aggressive — I'll see it as a dropped score on a specific dimension, not discover it in a PR.
