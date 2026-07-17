# Skill Evaluation & Improvement Workflow

How I evaluate and continuously improve my Kiro review skills (`pr-code-review`,
`pr-comment-resolver`) using promptfoo evals and a closed feedback loop driven by real
PR activity.

---

## TL;DR

I treat my review skills like production code: they have a test suite (promptfoo evals),
a feedback loop that turns real reviewer activity into new test cases, and a periodic
improvement step that edits the skill prompts only when a pattern recurs.

```
SETUP (once):     install promptfoo → smoke test → baseline eval

PRs I REVIEW:     #pr-code-review → others comment → #pr-code-review-gap-analyzer ┐
                                                                          ├→ review-gaps-retro.md
PRs I AUTHOR:     my PR → reviewers comment → #pr-comment-resolver ───────┘        │
                                              (fixes comments + logs detection rules)
                                                                                    ↓
EVERY ~3 PRs:                                                          #pr-code-review-retrospective
                                                          (reads gaps → edits skill → runs eval → sync)
```

---

## The core idea

A code-review skill is only as good as the issues it catches versus what skilled human
reviewers catch. So my ground truth is **real reviewer activity**, not synthetic guesses:

- When I **review** someone's PR, the issues *other* reviewers caught that I missed are gaps
  in `pr-code-review`.
- When I **author** a PR, every issue a reviewer flags is something `pr-code-review` should
  have caught if I'd self-reviewed before pushing.

Both are training signal. Both flow into one log. A periodic analyst step turns recurring
gaps into skill improvements, and every improvement is verified by re-running the eval.

---

## Components

### 1. The eval (`~/.kiro/evals/pr-code-review/`)

A promptfoo test suite for the `pr-code-review` skill. Three kinds of tests:

- **Positive** — feed buggy code, assert the skill catches the bug (SQL injection, race
  conditions, resource leaks, sync-over-async, query injection, missing timeouts, etc.)
- **Negative** — feed correct code, assert the skill does NOT fabricate issues (correct Rust
  error handling, correct `Optional[int]` checks, correct async context managers)
- **Resilience** — operational-safety patterns (silent fallback logging, missing gRPC
  deadlines, no retry/backoff on transient calls)

Each test has a `description:` (shows in `promptfoo view`, lets me target it with
`--filter-pattern`) and a `metric:` (groups scores by category: security, correctness,
resilience, false-positive-avoidance, etc.).

**Graded scoring (1–5, not binary).** A custom `rubricPrompt` in `defaultTest` converts every
test's criterion into a 1–5 quality score, normalized to 0–1:

| Rating | Score | Meaning |
|--------|-------|---------|
| 5 Excellent | 1.00 | Precise finding + impact + correct fix, no noise |
| 4 Good | 0.75 | Satisfies criterion, fix slightly thin |
| 3 Adequate | 0.50 | Vague mention or weak fix, or minor fabrication |
| 2 Poor | 0.25 | Misses the actual issue or wrong fix |
| 1 Fail | 0.00 | Misses entirely (or fabricates, for negative tests) |

`threshold: 0.75` means a test passes only at 4/5+. A barely-adequate 3/5 review fails the gate
AND shows a degraded score — this catches slow quality decay that binary pass/fail hides.
Because each test has a `metric:`, `promptfoo view` shows a per-dimension scorecard
(`security: 0.83`, `resilience: 0.61`, …) — the Matthias-style multi-dimension view, automatic.

**Provider & grader:** uses the Claude CLI via a small `claude.js` wrapper for both running the
skill (providers: sonnet + haiku, the Model Ladder) and `llm-rubric` grading. The wrapper hardens
grader-output JSON extraction (strips fences, extracts the first balanced object, retries once).

### 2. `grade-the-grader` skill (audits the eval itself)

The eval grades the skill; this skill grades the eval. Run every 5–10 eval runs, after a grader
model change, or when scores look suspicious (all 1.0 = too lenient; run-to-run swings = vague
criteria). It audits each grading decision for leniency, strictness, vague criteria, weak grader
reasoning, inverted negative-test logic, and inconsistency — then proposes sharper criteria,
rubricPrompt tweaks, or threshold changes. This is Matthias's "separate agent critiques the
grading" step. **Trust rule: if the grader is broken, fix it before acting on any score trend.**

### 3. `pr-code-review-gap-analyzer` skill (the sensor — PRs I reviewed)

Runs per PR after others have commented. Compares my review against everyone else's:
- **Misses** — issues others caught, I didn't → positive eval test candidates
- **False positives** — my comments that were rejected → negative eval test candidates
- **Agreements** — issues we both caught → tracked as a positive signal

Computes **recall** (caught / total real issues) and **precision** (valid / total I raised),
appends a per-PR entry + score row to `review-gaps-retro.md`, and (with approval) adds the
failing eval tests. **Does not edit skill prompts.**

### 4. `pr-comment-resolver` skill (the sensor — PRs I authored)

Its primary job is triaging and fixing reviewer comments on my own PRs. As a side-output, for
each issue it now records:
- **Prevention rule (implementer)** — "never write code that does X" (for implementation agents)
- **Detection rule (reviewer)** — "flag code that does X" (for `pr-code-review`)

It appends the *detectable* issues to the same `review-gaps-retro.md` file, tagged
`source: pr-comment-resolver (authored PR)`. **Does not edit skill prompts.**

### 5. `pr-code-review-retrospective` skill (the analyst + editor — every ~3 PRs)

The only skill that edits skill prompts. Reads the accumulated `review-gaps-retro.md` (plus
other retro files), builds the recall/precision trend table, and:
- Identifies **patterns** (a gap appearing in ≥2 PRs) vs **one-offs** (leave the eval test
  failing, wait for recurrence — except P0 security/correctness misses caught by a maintainer)
- Proposes and applies concrete skill-prompt edits
- Re-runs the eval to confirm previously-failing positive tests now pass and no negative test
  regressed
- Syncs edited skills back to the git-tracked `ai-dev-toolkit/` repo and archives consumed retros
  (preserving the trend table)

---

## Why the responsibilities are split this way (Option A)

The sensors (`pr-code-review-gap-analyzer`, `pr-comment-resolver`) only **log facts and add tests**.
The analyst (`pr-code-review-retrospective`) owns all **skill-prompt edits**.

This prevents two failure modes:
- **Over-fitting** — if every PR could edit the skill, one maintainer's pet peeve becomes a
  permanent rule. Requiring recurrence (≥2 PRs) before a skill edit filters noise.
- **Skill bloat** — uncontrolled per-PR edits make the skill sprawl. A single editor with the
  cross-PR view consolidates instead of appending duplicates.

Adding eval *tests* from a sensor is safe (tests are additive, a failing test just marks an
open gap), so that's allowed without the analyst.

---

## Step-by-step

### One-time setup
```bash
npm install -g promptfoo

# Smoke test the plumbing
cd ~/.kiro/evals/pr-code-review
promptfoo eval --filter-pattern "SQL injection"

# Baseline the full suite
promptfoo eval
promptfoo view
```

### Per PR I review
```
#pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
```
Wait for other reviewers to comment, then:
```
#pr-code-review-gap-analyzer
Analyze review gaps on this PR: https://github.com/owner/repo/pull/123
```

### Per PR I author (when reviewers comment)
```
#pr-comment-resolver
Check comments on this PR: https://github.com/owner/repo/pull/123
```
It fixes the comments AND logs the detection rules to `review-gaps-retro.md`.

### Every ~3 PRs (once review-gaps-retro.md has 3+ entries)
```
#pr-code-review-retrospective
```
Reviews accumulated gaps, edits the skill, re-runs the eval, syncs to git.

---

## Result tracking

- **promptfoo** stores all runs in `~/.promptfoo/output.db`. `promptfoo view` shows score
  trends, per-test history, token usage, and diffs between runs.
- **`review-gaps-retro.md`** holds the recall/precision trend table — the long-term signal of
  whether the review skill is actually getting better. This table survives retro archiving.

---

## Files

| Path | Role |
|---|---|
| `~/.kiro/evals/pr-code-review/promptfooconfig.yaml` | The eval test suite (graded 1–5 rubric) |
| `~/.kiro/evals/README.md` | How to run/maintain evals (when to run, fix skill, fix eval, improve) |
| `~/.kiro/skills/pr-code-review.md` | The skill under test |
| `~/.kiro/skills/grade-the-grader.md` | Meta-eval — audits the eval's grading quality |
| `~/.kiro/skills/pr-code-review-gap-analyzer.md` | Sensor — PRs I reviewed |
| `~/.kiro/skills/pr-comment-resolver.md` | Sensor — PRs I authored + comment fixing |
| `~/.kiro/skills/pr-code-review-retrospective.md` | Analyst + editor |
| `~/.kiro/retros/review-gaps-retro.md` | Shared ground-truth log + trend table |

---

## How this compares to my teammates

| Aspect | Riley | Matthias | Edward | Jonathan | **Mine** |
|---|---|---|---|---|---|
| Tooling | promptfoo | AI rubrics + grader agent | promptfoo | promptfoo (skill-creator generated) | promptfoo |
| Test design | positive + negative, llm-rubric | 15-dim rubric, 1–5 scoring | per-skill configs | agent-generated JSON | positive + negative + resilience, **graded 1–5 rubric**, per-metric scorecard |
| Grader | (improving/promptfoo default) | separate Kiro agent grades the grading | promptfoo | promptfoo | Claude CLI (via claude.js) + **grade-the-grader audit skill** |
| Ground truth source | manual + regression from own outputs | per-PR manual review | — | — | **automated: real reviewer activity (both roles)** |
| Feedback loop | "add errors to suite as regression" | "update agents with what they missed, manually" | "tests get stale, too costly" | tweak JSON manually | **structured sensor → log → analyst → eval** |
| Cadence | after every change | per PR (one scoring run so far) | rarely (cost) | ad hoc | per-PR logging, skill edits every ~3 PRs |
| Automation | none described | none ("nothing automated yet") | promptfoo runs | none | skill-driven, hook-ready |

**Where I'm ahead:**
- I capture ground truth from **both** roles (reviewing others + authoring), which neither
  Riley, Matthias, nor Edward described.
- My loop is **structured and repeatable** as named skills, not ad-hoc manual updates.
- I have an explicit **over-fitting guard** (recurrence ≥2 PRs) — others edit per PR or per
  whim, which risks drift.
- Every skill edit is **verified by re-running the eval**, closing the loop Matthias does
  manually and Edward skips.

**Where teammates are ahead (things to borrow):**
- **Matthias's rubric scoring + grader-grading.** ✅ Now adopted — graded 1–5 rubric with a
  per-metric scorecard, plus a `grade-the-grader` skill that audits the grader's calibration.
- **Edward's cost-awareness.** He stopped running evals on deep multi-step workflows because
  they're too expensive. I should keep evals on atomic skills (which I do) and explicitly NOT
  try to eval the 12-subagent valkey pipeline end-to-end.
- **Riley's discipline** of running evals after *every* change as a hard gate. I have the
  mechanism; I need the habit.

---

## How to improve further

Ordered by payoff:

### 1. Build the habit (free, highest payoff)
The whole loop is worthless if I don't run `#pr-code-review-gap-analyzer` after PRs and
`#pr-code-review-retrospective` every few PRs. Make it part of the PR routine, not an afterthought.

### 2. Add the `contribution-explorer` eval (low effort)
It has clean deterministic decisions to test: runs the health-check gate first, checks
`samples/` before recommending `new-package`, classifies `sample` vs `new-package` correctly.
Cheaper and more objective than the review eval.

### 3. ✅ DONE — Graded 1–5 rubric scoring (Matthias-style)
The eval now uses a custom `rubricPrompt` that scores each review 1–5 (normalized to 0–1) with a
0.75 pass threshold, and a per-`metric:` scorecard. A barely-adequate 3/5 review fails the gate
and shows a declining score, surfacing slow degradation binary tests miss.

### 4. ✅ DONE — `grade-the-grader` skill
A meta-eval skill audits whether the grader/criteria are well-calibrated (too lenient, too
strict, vague, inconsistent, or inverted on negative tests) and proposes concrete fixes. Run it
every 5–10 eval runs or after a grader model change.

### 5. Lightweight automation (when stable)
Once 3+ evals are stable, a `fileEdited` hook on the skill files to auto-run the relevant eval
gives Riley's "every change is gated" discipline for free. (Deliberately not enabled yet —
plumbing should be proven first.)

### 6. CI / scheduled runs (only if it earns its keep)
Move evals into the `ai-dev-toolkit` git repo and run nightly or on push via GitHub Actions —
Edward's setup. Worth it only with 3+ stable evals; otherwise maintenance cost outweighs benefit
(Edward's own tests went stale).

### 7. Expand the negative-test corpus deliberately
False positives erode trust in the skill faster than misses. Every time the skill flags correct
code, that snippet becomes a permanent negative test. Aim for a healthy ratio of negative to
positive tests so precision is protected, not just recall.

---

## Anti-patterns to avoid

- Don't eval the multi-step valkey-integration pipeline with promptfoo — use the retro loop.
- Don't let sensors edit skill prompts — only `pr-code-review-retrospective` does, and only on recurrence.
- Don't add a skill rule for a one-off gap — wait for it to recur (except P0 maintainer catches).
- Don't skip the eval run after a skill edit — an unverified edit is an unproven edit.
- Don't discard the recall/precision trend table when archiving retros — it's the long-term signal.
- Don't optimize for recall alone — protect precision with negative tests, or the skill cries wolf.
