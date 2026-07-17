# pr-code-review — Skill Certification Submission

> A production-grade, provider-neutral **code-review skill**, the reusable skills it composes,
> the **promptfoo evaluation framework** that scores it (with a baseline-vs-skill A/B that
> proves it adds value), and the **closed feedback loop** that keeps it improving from real
> reviewer activity.

This package is the certification submission for the [`pr-code-review`](skills/pr-code-review/)
skill. It follows an **eval-driven development (EDD)** approach: the skill is treated like
production code with a test suite, a measured baseline, and a repeatable improvement process.

> **Provenance.** This repository *rebuilds an existing, in-use skill* by following the
> AI Self-Directed Learning course end to end — writing tests before prompts, growing the
> skill through measured iterations, and letting the git history record each step. The
> `pr-code-review` skill (and the `_shared/` rulebook, `evals/`, and sibling skills it
> composes with) already lives in my day-to-day toolkit; here it is re-derived from a minimal
> starting point so the EDD discipline is demonstrable in the commit timeline. The supporting
> `skills/`, `evals/`, `docs/`, `CONVENTIONS.md`, and `sync.sh` are copied in from that toolkit
> so this repo is self-contained — they will appear as new files here, but they are existing
> work, not built fresh for the course. The step-by-step rebuild lives under
> [`module-1/`](module-1/) … [`module-4/`](module-4/).

- **Skill under review:** [`skills/pr-code-review/SKILL.md`](skills/pr-code-review/SKILL.md)
- **Eval framework:** [`evals/pr-code-review/`](evals/pr-code-review/)
- **How I evaluate & improve (the rubric):** [`RUBRIC.md`](RUBRIC.md) and
  [`docs/skill-evaluation-workflow.md`](docs/skill-evaluation-workflow.md)

---

## The problem

Code review is the highest-leverage quality gate in software delivery, but it's inconsistent:
reviewers miss real bugs under time pressure, and automated reviewers do the opposite — they
"cry wolf," flagging correct code and burying the few real issues in noise. A review assistant
is only trustworthy if it does **both** well: high **recall** (catches the real bugs skilled
humans catch) *and* high **precision** (does not fabricate issues in correct code). A single
hallucinated comment makes an author distrust the entire review.

Most AI review prompts are never measured against either axis. They're written once, and drift
silently as models change.

## The solution

A layered, reusable skill system plus a measurement harness:

1. A **single rulebook** ([`_shared/review-checklist.md`](skills/_shared/review-checklist.md)) —
   the language-agnostic "what to check" (design, correctness, resource management, resilience,
   security, performance, tests, licensing). It's the single source of truth, shared verbatim by
   the PR reviewer *and* the Valkey self-reviewer so their criteria never diverge.
2. The **`pr-code-review` skill** wraps that rulebook with a full review workflow: context
   gathering (local or fully remote PRs), optional sub-agent fan-out per review lens, a dedicated
   security pass, **precision gates** (verify-before-flag, nitpick filter, never-fabricate), and
   GitHub inline-comment posting gated on user approval.
3. A **promptfoo eval** scores the skill on a graded 1–5 rubric across every review dimension,
   with a **baseline arm** that measures the bare model so the skill's value is quantified, not
   asserted.
4. A **closed improvement loop** turns real reviewer activity into new test cases and, on
   recurrence, into sharpened rules — every edit verified by re-running the eval.

### Skills reused (the composition)

The submission is not one prompt — it's a system of small, single-purpose, reusable skills:

| Component | Path | Role in the system |
|---|---|---|
| **pr-code-review** | [`skills/pr-code-review/`](skills/pr-code-review/) | The skill under certification. Full PR review + re-review workflow. |
| review-checklist (shared) | [`skills/_shared/review-checklist.md`](skills/_shared/review-checklist.md) | The rulebook — single source of truth for review rules. |
| review-findings-schema (shared) | [`skills/_shared/review-findings-schema.md`](skills/_shared/review-findings-schema.md) | Canonical review lenses + finding output format. |
| **security-review** | [`skills/security-review/`](skills/security-review/) | Focused fresh-eyes security pass; run by a `security-reviewer` sub-agent. |
| **pr-code-review-gap-analyzer** | [`skills/pr-code-review-gap-analyzer/`](skills/pr-code-review-gap-analyzer/) | Sensor — compares my review vs other reviewers to find misses/false positives. |
| **pr-code-review-retrospective** | [`skills/pr-code-review-retrospective/`](skills/pr-code-review-retrospective/) | Analyst/editor — consolidates gaps, edits the skill + checklist, re-runs the eval. |
| **grade-the-grader** | [`skills/grade-the-grader/`](skills/grade-the-grader/) | Meta-eval — audits the eval's grading quality so scores stay meaningful. |

All are provider-neutral (`SKILL.md`) and install into Kiro or Claude Code via
[`sync.sh`](sync.sh). See [`CONVENTIONS.md`](CONVENTIONS.md).

---

## The evaluation framework

Located in [`evals/pr-code-review/`](evals/pr-code-review/). Built on
[promptfoo](https://promptfoo.dev), running both the review generation and the LLM grading
through `kiro-cli` (no separate API key — uses the Kiro subscription).

### Two arms — the evidence of value

| Arm | Config | Provider | What it measures |
|---|---|---|---|
| **Skill ON** | [`promptfooconfig.yaml`](evals/pr-code-review/promptfooconfig.yaml) | [`kiro-review.sh`](evals/kiro-review.sh) — injects the checklist + precision gates | The skill's actual behavior |
| **Skill OFF (baseline)** | [`promptfooconfig.baseline.yaml`](evals/pr-code-review/promptfooconfig.baseline.yaml) | [`kiro-baseline.sh`](evals/kiro-baseline.sh) — bare model, same pin | The raw model on the same tests |

Both arms use the **same model, same test snippets, same grader, same rubric, same threshold**.
The only variable is whether the skill's rulebook and precision gates are present. The
per-metric score delta between the two runs is the skill's measured lift — its evidence of value.

### Three test categories (always kept in balance)

- **Positive** — buggy code; assert the skill catches the bug (SQL injection, race conditions,
  resource leaks, sync-over-async, query injection, missing timeouts, N+1, silent truncation…).
- **Negative** — correct code; assert the skill does **not** fabricate issues. Precision matters
  as much as recall; a skill that cries wolf is worthless.
- **Resilience/regression** — operational-safety patterns and any case a live run got wrong.

Each test carries a `metric:` (security, correctness, resource-management, resilience,
performance, licensing, false-positive-avoidance) so `promptfoo view` shows a **per-dimension
scorecard**, not a single number.

### Graded scoring, not pass/fail

A custom `rubricPrompt` scores each review 1–5 (normalized 0–1) with a `0.75` threshold — a test
passes only at 4/5 or better. A barely-adequate 3/5 review fails the gate *and* shows a declining
score, catching slow quality decay that binary pass/fail hides. Full scale in [`RUBRIC.md`](RUBRIC.md).

### Running it

```bash
npm install -g promptfoo                     # once
curl -fsSL https://cli.kiro.dev/install | bash   # once — provides kiro-cli

cd evals/pr-code-review

# Evidence-of-value A/B (run both, then compare in the UI):
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # skill OFF
promptfoo eval -c promptfooconfig.yaml          --no-cache   # skill ON
promptfoo view                                               # compare per-metric scores

# Iterate on a single dimension while editing the checklist:
promptfoo eval --filter-pattern "SQL injection"
```

Full run/maintain guide: [`evals/README.md`](evals/README.md).

---

## How I evaluate and improve (the loop)

Ground truth for a review skill = **what other skilled reviewers caught that it didn't**. The
loop turns that real activity into measured improvement:

```
PRs I REVIEW:  #pr-code-review → others comment → #pr-code-review-gap-analyzer ┐
                                                                       ├→ review-gaps-retro.md
PRs I AUTHOR:  my PR → reviewers comment → #pr-comment-resolver ───────┘        │
                                           (logs detection rules)                ↓
EVERY ~3 PRs:                                              #pr-code-review-retrospective
                                       (reads gaps → edits skill/checklist → re-runs eval → sync)
```

- **Sensors** (`gap-analyzer`, `pr-comment-resolver`) only *log facts and add tests* — never edit
  rules. Misses become positive eval tests; false positives become negative tests.
- **Analyst** (`retrospective`) is the *only* thing that edits rules, and only when a gap recurs
  in ≥2 PRs (an explicit over-fitting guard) — except P0 security/correctness misses.
- **Every rule edit is verified** by re-running the eval before it's committed.
- **The grader itself is audited** by `grade-the-grader` so scores don't quietly drift.

The recall/precision trend table in `review-gaps-retro.md` is the long-term signal of whether the
skill is actually getting better. Rationale, comparison to peers, and anti-patterns:
[`docs/skill-evaluation-workflow.md`](docs/skill-evaluation-workflow.md).

---

## Why this meets the certification bar

- **Reusable skills, cleanly composed** — one shared rulebook, single-purpose skills, provider-neutral.
- **A real evaluation framework** — graded, per-dimension, three balanced test categories.
- **Measured evidence of value** — a baseline-vs-skill A/B on identical tests, not a claim.
- **A documented, repeatable improvement methodology** — sensors → log → analyst → eval, with an
  over-fitting guard and a grader audit, all driven by real reviewer ground truth.
