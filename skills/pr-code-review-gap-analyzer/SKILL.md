---
name: pr-code-review-gap-analyzer
description: Compares your pr-code-review output against what OTHER reviewers (humans + bots) caught on the same PR. Logs misses and false positives, then proposes concrete improvements to pr-code-review and pr-comment-resolver skills plus new eval test cases. The self-improvement engine for review skills.
inclusion: manual
---

# PR Code Review Gap Analyzer

You measure how good your own review skills are by comparing their output against ground truth: what other human reviewers and bots actually caught on the same PR. Every gap is a concrete, verified improvement opportunity — not a synthetic guess.

This skill closes the loop:
```
your review → others' reviews → delta → logged gaps → proposed skill edits + eval tests → eval run
```

## How to Use

```
#pr-code-review-gap-analyzer
Analyze review gaps on this PR: https://github.com/owner/repo/pull/123
```

```
#pr-code-review-gap-analyzer
Analyze gaps on these PRs I reviewed:
- https://github.com/owner/repo/pull/123
- https://github.com/owner/repo/pull/456
```

Optionally tell it which of your comments came from the skill (if you edited some manually):
```
#pr-code-review-gap-analyzer
Analyze gaps on https://github.com/owner/repo/pull/123
My comments are from the daric93 account.
```

## Input Parsing

- **PR URL(s)** (required) — parse `owner`, `repo`, `pullNumber`
- **Findings file** (optional but preferred) — a path to the `pr-code-review` findings file for this
  PR (the `findings_file` recorded in `pr-review-log.md`). When provided, it is the authoritative
  source of *what your review found*, including findings you chose **not** to post. `pr-code-review-retrospective`
  always passes this; an interactive user may omit it.
- **Your account** (optional) — if not given, call `get_me` to determine it

## Modes

- **Interactive** — a user runs `#pr-code-review-gap-analyzer` on a PR they reviewed. If they don't pass a
  findings file, reconstruct "your review" from your posted GitHub comments.
- **Orchestrated** — `pr-code-review-retrospective` invokes this skill (or the `pr-code-review-gap-analyzer` sub-agent) once
  per unprocessed review, passing the PR URL **and** its `findings_file`. Prefer the findings file
  over GitHub reconstruction whenever it's supplied — it's richer (sees skipped findings) and immune
  to later comment edits/resolutions.

## Process

### Phase 1: Identify Your Review vs Everyone Else's

**First, establish the source of YOUR review:**
- **If a findings file was provided** (orchestrated mode, or the user passed one): read it. The
  findings it lists — with their `decision` (`posted` / `skipped`) — ARE your review. This is
  authoritative: it captures what the skill detected even if you didn't post it. Still fetch the
  GitHub comments below to confirm what was actually posted and to read others' reviews.
- **Otherwise** (interactive, no file): reconstruct your review from your posted GitHub comments
  (the steps below). Note in the report that skipped findings are invisible in this mode, so a
  "miss" can't be distinguished from a deliberate skip.

Then gather everything on the PR:
1. Call `get_me` to get your username (`$ME`) unless the user specified it.
2. `pull_request_read(method="get_reviews")` — all submitted reviews.
3. `pull_request_read(method="get_review_comments")` — all inline review threads.
4. `pull_request_read(method="get_comments")` — general PR comments.
5. Partition every comment into:
   - **Yours** — authored by `$ME` (and, when a findings file exists, also the `skipped` findings
     that never became comments)
   - **Others'** — everyone else (maintainers, contributors, Copilot, CI bots)
6. For each commenter, capture `author_association` (OWNER, MEMBER, CONTRIBUTOR, NONE) and whether they're a bot. Maintainer-caught misses are weighted highest.

### Phase 2: Read the Code Under Review

For each comment (yours and others'), you need the actual code to judge overlap:
- `pull_request_read(method="get_diff")` — the full diff
- Read changed files at the PR head ref if more context is needed

You cannot judge a "miss" without understanding what the code actually does.

### Phase 3: Compute the Delta

#### 3a. Misses — issues others caught that you didn't

For each comment from another reviewer:
1. Find the file + line/area it targets.
2. Check whether ANY of your comments addressed the same issue (same substance, not exact wording — your comment on line 40 about error handling overlaps with their comment on line 42 about the same try/except).
3. If no posted comment of yours overlaps → it's a candidate **MISS**. Before recording, classify it
   using the findings file (when available):
   - The issue is **absent** from the findings file → **detection miss**: the skill never found it.
     Fix target = a new/sharper checklist rule + a positive eval test.
   - The issue **is in the findings file but marked `skipped`** → **judgment miss**: the skill found
     it but we chose not to post it. Fix target = severity/nitpick-filter calibration or posting
     guidance — NOT a detection rule. Quote the `skip_reason`.
   - No findings file available → record as a plain MISS and note it can't be split.

Filter out non-actionable "misses" before logging:
- Pure questions ("why did you choose X?") — not a miss
- Praise / approvals — not a miss
- Subjective style preferences with no correctness impact — note but mark low priority
- Out-of-scope comments (about code your review wasn't asked to cover) — not a miss

#### 3b. False positives — your comments that were rejected

For each of YOUR comments:
1. Check replies in the thread and whether the thread was resolved/dismissed.
2. If the author or a maintainer pushed back with a valid reason, OR the comment was marked as not-applicable → it's a candidate **FALSE POSITIVE**.
3. Read the code to confirm the pushback is correct (don't log a false positive if the pushback was actually wrong and your comment was right).

#### 3c. Agreements — issues both you and others caught

Count these too. A high agreement rate is the positive signal that the skill is working. Track it as a metric.

### Phase 4: Categorize Each Gap

For every miss and false positive, assign:
- **Category** — Security, Correctness, Performance, Resilience, Resource Mgmt, API Consistency, Test Coverage, Docs, Style
- **Which skill it maps to**:
  - A **detection MISS** (absent from findings) → `pr-code-review` lacks a rule/check → propose a skill rule + an eval positive test.
  - A **judgment MISS** (found but `skipped`) → `pr-code-review`'s severity/nitpick-filter dropped a real issue → propose a calibration tweak (raise that pattern's severity, or stop filtering it) + an eval positive test asserting it's surfaced. Do NOT add a detection rule — it already detects it.
  - A FALSE POSITIVE → `pr-code-review` is too aggressive → propose a skill counter-rule + an eval negative test
  - A miss specifically about *triage/priority* of existing comments → maps to `pr-comment-resolver`
- **Root cause** — knowledge gap, missing checklist item, wrong assumption, or category not covered at all
- **Prevention rule** — one actionable imperative sentence ("Always X when Y")

### Phase 5: Present the Gap Report

```
## Review Gap Analysis: [PR title]
PR: owner/repo#N
Your comments: N | Others' comments: M | Agreements: K

### Score
- Recall (caught / total real issues): X% — caught K of (K + misses)
- Precision (valid / total you raised): Y% — (yours - false_pos) of yours
- Maintainer-caught misses: N (highest priority)

---

### MISSES (others caught, you didn't)

#### M1: [Priority] [Short title]  — caught by @maintainer (OWNER)
- **File**: `path:line`
- **What they caught**: [summary]
- **Why you missed it**: [root cause]
- **Category**: [category]
- **Maps to**: pr-code-review
- **Proposed skill rule**: "[imperative rule]"
- **Proposed eval test** (positive):
  ```yaml
  - vars:
      prompt: |
        Review this [lang] code:
        ```[lang]
        [minimal snippet reproducing the pattern]
        ```
    assert:
      - type: llm-rubric
        value: "Identifies [the issue] and recommends [the fix]."
  ```

---

### FALSE POSITIVES (you raised, others rejected)

#### F1: [Short title]
- **File**: `path:line`
- **What you said**: [summary]
- **Why it was wrong**: [the valid pushback, with evidence from the code]
- **Maps to**: pr-code-review
- **Proposed counter-rule**: "Do NOT flag X when Y — this is correct because Z."
- **Proposed eval test** (negative):
  ```yaml
  - vars:
      prompt: |
        Review this [lang] code:
        ```[lang]
        [the correct code you wrongly flagged]
        ```
    assert:
      - type: llm-rubric
        value: "Does not flag [pattern] as an issue — it is correct because [reason]."
  ```

---

### Summary of Proposed Changes
| # | Type | Skill | Eval test | Priority |
|---|------|-------|-----------|----------|
| M1 | rule add | pr-code-review | positive | P0 |
| F1 | counter-rule | pr-code-review | negative | P1 |
```

### Phase 6: Log the Gaps (always, automatically)

**Append** to `<config>/retros/review-gaps-retro.md` (create with a `# Review Gaps Retrospective`
header if missing — never overwrite, always append; use an append operation like `fs_append`).
This is the running ground-truth log that the `pr-code-review-retrospective` skill and eval improvements draw from.

Each entry MUST start with a stable, unique entry-ID header in this exact format so `pr-code-review-retrospective`
can track what it has already processed and avoid reprocessing:

```markdown
## ENTRY 2026-06-10 | owner/repo#123 — source: pr-code-review-gap-analyzer (reviewed PR)
- findings_file: <config>/reviews/2026-06-10__owner__repo__pr123.md  (or "none — GitHub reconstruction")
- misses: N (detection: A, judgment: B)
- false_positives: M
```

The entry-ID is `ENTRY <YYYY-MM-DD> | <owner>/<repo>#<PR>`. The date is the calendar date of the
analysis; repo#PR makes it unique across same-day runs. Record the `findings_file` you analyzed (so
`pr-code-review-retrospective` can trace it) and the detection/judgment miss split. Follow the header with the
per-gap detail from the report.

Also append the score line to a metrics table at the top of the file so trends are visible across
PRs (this table is exempt from archiving — `pr-code-review-retrospective` preserves it):
```
| Date | PR | Recall | Precision | Misses | False Pos | Maintainer misses |
|------|----|--------|-----------|--------|-----------|-------------------|
```

### Phase 7: Add Eval Test Cases (optional, human-gated) — do NOT edit skill prompts

This skill is the **sensor**. It records facts and adds tests. It does NOT edit skill prompts —
that is the `pr-code-review-retrospective` skill's job, because skill-prompt edits need the cross-PR view to
avoid over-fitting to a single reviewer or a one-off comment.

Adding eval test cases here IS allowed, because tests are additive and safe — a new positive
test just encodes "the skill should catch this", and a new negative test encodes "the skill
should not flag this". They don't risk skill bloat or regression.

Ask the user: **"Want me to add these as test cases to the eval? (Skill-prompt changes are deferred to `pr-code-review-retrospective`.)"**

If yes:
1. Add approved test cases to `<config>/evals/pr-code-review/promptfooconfig.yaml`, each with a
   `description:` and the appropriate `metric:`. Positive tests for misses, negative tests for
   false positives.
2. Run the eval to record the current baseline (newly added positive tests are EXPECTED to fail
   until the skill is improved — that's the point; they encode the gap):
   ```bash
   cd <config>/evals/pr-code-review && promptfoo eval
   ```
3. Report which new tests pass and which fail. Failing positive tests are the open gaps that
   `pr-code-review-retrospective` will later close by improving the skill.

**Do NOT** edit `pr-code-review.md` or `pr-comment-resolver.md` here. Leave the proposed rules in
the gap report and the retro log — `pr-code-review-retrospective` consumes them after enough PRs accumulate.

## Handoff to / from pr-code-review-retrospective

`pr-code-review-retrospective` owns the trigger and the cadence now. It walks `pr-review-log.md`, and once **≥3
reviews are unprocessed since the last retro**, it invokes this skill (or the `pr-code-review-gap-analyzer`
sub-agent) once per review — passing the PR URL and its `findings_file` — then consolidates the
resulting gap entries, decides which proposed rules are real patterns vs one-offs, applies the
skill-prompt edits, and re-runs the eval.

So there are two entry points, both ending in the same `review-gaps-retro.md` log:
- **Interactive:** you run `#pr-code-review-gap-analyzer` on a single PR for an immediate gap report.
- **Orchestrated:** `pr-code-review-retrospective` runs you in a batch. This is the normal path.

Either way, this skill only logs gaps and (optionally, human-gated) adds eval tests — it never edits
skill prompts. That stays with `pr-code-review-retrospective`.

## Anti-Patterns

- DO NOT log a "miss" for questions, praise, or out-of-scope comments — only real actionable issues.
- DO NOT log a false positive when the pushback was wrong and your comment was actually correct — verify against the code.
- DO NOT edit skill prompt files (`pr-code-review.md`, `pr-comment-resolver.md`) — that is `pr-code-review-retrospective`'s job. This skill only logs gaps and adds eval tests.
- DO NOT skip logging — the per-PR entry and score row in `review-gaps-retro.md` are the whole point.
- DO NOT overwrite the retro log — always append.

---
> Path placeholders: `<config>` = your assistant's user-level dir (`~/.kiro` for Kiro, `~/.claude` for Claude); `<workspace-config>` = the per-project dir (`.kiro` / `.claude`). See `_shared/paths.md`.
