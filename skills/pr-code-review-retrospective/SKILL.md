---
name: pr-code-review-retrospective
description: The improvement engine for the pr-code-review skill. Walks the review log, drives pr-code-review-gap-analyzer over new reviews, consolidates the gaps across PRs, and proposes/applies edits to pr-code-review and its shared review files (review-checklist.md, review-findings-schema.md), then re-runs the eval. Trigger after ≥3 new reviews since the last retro.
inclusion: manual
---

# PR Code Review Retrospective

The analyst + editor for the **pr-code-review** family. It turns accumulated review gaps into
concrete, verified improvements to `pr-code-review` and the **shared review files** it uses, then
proves the improvement with the eval.

Scope is deliberately narrow: this skill owns **only** the review domain —
- the `pr-code-review` skill body, and
- the shared review files: `_shared/review-checklist.md` and `_shared/review-findings-schema.md`.

It does NOT edit valkey-integration agents, ci-failure-review, or pr-comment-resolver — those belong
to the generic `retrospective` skill. (Note: improving `_shared/review-checklist.md` transitively
improves the valkey self-reviewer, because that sub-agent applies the same shared checklist — but you
edit the shared file, never the valkey agent.)

## When to Use

Trigger manually **after ≥3 new reviews in `pr-review-log.md` since the last retro** (the normal
cadence). Also valid: a P0 security/correctness miss a maintainer caught (fast-path, may run earlier
with user confirmation).

This is the ONLY skill that edits the `pr-code-review` prompt and its shared review files.
`pr-code-review` (the sensor that logs reviews) and `pr-code-review-gap-analyzer` (the sensor that
logs gaps) never edit prompts.

## Step 0: Load the processed-entries ledger (do this FIRST)

To stay idempotent, keep a ledger at `<config>/retros/.processed-entries.md`. It records which
`pr-review-log.md` entries have been processed, which `review-gaps-retro.md` entry-IDs have been
folded into edits, and the date of the last retro.

1. Read `<config>/retros/.processed-entries.md` if it exists (create it later if not). Format:
   ```markdown
   # Processed Entries Ledger
   Last retro: 2026-06-10

   ## <config>/retros/pr-review-log.md
   - ENTRY 2026-06-08 | owner/repo#120
   - ENTRY 2026-06-09 | owner/repo#121

   ## <config>/retros/review-gaps-retro.md
   - ENTRY 2026-06-08 | owner/repo#120 — source: pr-code-review-gap-analyzer (reviewed PR)
   ```
2. Parse entries in `pr-review-log.md` by their `## ENTRY <date> | <repo>#<PR>` headers.
3. **Only process entries whose ENTRY-ID is NOT already in the ledger** and whose `gap_analyzed` is
   `no`. These are "new reviews since the last retro." This is the primary trigger counter.

## Step 1: Drive gap analysis for the new reviews

1. Collect the unprocessed `pr-review-log.md` entries from Step 0.
2. **Gate on count:** if fewer than 3, stop and tell the user there isn't enough new data yet
   (exception: a known P0 security/correctness maintainer-miss may justify an early run — proceed
   only if the user confirms).
3. **Process the batch one entry at a time, persisting progress after EACH entry.** For each
   unprocessed entry, in order:

   a. **Idempotency guard (check BEFORE dispatching).** Skip the entry — do not invoke the
      gap-analyzer — if ANY of these is already true for its ENTRY-ID:
      - it appears in the ledger's `pr-review-log.md` section, OR
      - its `gap_analyzed` flag is already `yes`, OR
      - a gap entry with the same ENTRY-ID already exists in `review-gaps-retro.md`.

      If a gap entry exists but the flag/ledger weren't updated (e.g. a prior interrupted run),
      **self-heal**: flip the flag and record the ledger entry now, then skip. Do NOT re-run the
      analysis or append a second gap entry. This is the guard that makes the batch safe to resume.

   b. **Dispatch.** Run `pr-code-review-gap-analyzer`, passing the **PR URL** and its
      **`findings_file`** path (from the log entry). Where sub-agents are supported, delegate to the
      `pr-code-review-gap-analyzer` sub-agent (in Kiro, `invokeSubAgent`) so each PR's analysis runs
      in isolated context and doesn't bloat this orchestrator. Otherwise apply the gap-analyzer
      process inline. The run appends one gap entry to `review-gaps-retro.md` and returns misses
      (split into **detection** vs **judgment**) and false positives.

   c. **Persist progress IMMEDIATELY, before moving to the next entry** (this is what prevents an
      infinite re-dispatch loop — do NOT defer it to Step 6):
      - flip that entry's `gap_analyzed: no → yes` in `pr-review-log.md`, AND
      - append its ENTRY-ID to the ledger's `pr-review-log.md` section in
        `<config>/retros/.processed-entries.md` (create the ledger file if it doesn't exist yet).

   d. Collect the returned misses/false positives in memory for consolidation (Step 3).

   Only after an entry's flag AND ledger record are written do you advance to the next entry. If the
   run is interrupted, resuming re-reads the log and the guard in (a) skips everything already
   persisted — the batch is monotonic and always terminates.

## Step 2: Read current state before proposing

Read the files you might edit, so you sharpen what's there instead of duplicating:
- `<config>/skills/pr-code-review.md` — the skill body (workflow + review behavior)
- `<config>/skills/_shared/review-checklist.md` — the shared rulebook (what to check)
- `<config>/skills/_shared/review-findings-schema.md` — finding shape, lenses, persisted-file schema
- the eval at `<config>/evals/pr-code-review/promptfooconfig.yaml` — to see which tests encode the gaps

Also read the **retained gap history** so recurrence is measured against all prior PRs, not just
this batch:
- `<config>/retros/review-gaps-retro.md` — every prior PR's misses/false positives (up to the most
  recent 50, per the Step 6 archiving rule). This is where a one-off held in an earlier retro lives;
  a class that reappears here in a new PR is what turns a held candidate into an actionable pattern.
  There is no separate "held candidates" list to maintain — this retained log IS the held-candidate
  store.

## Step 3: Consolidate — patterns, not one-offs

Look for recurring signals across the newly-processed batch **AND the retained gap entries already
in `review-gaps-retro.md` from prior retros** (read in Step 2). **Recurrence is measured across the
full retained history, not just the current batch:** a gap *class* seen in a prior PR that shows up
again in a new PR is a ≥2-PR pattern and is now actionable — even if it appears only once in the
current batch. This is how a one-off held in an earlier retro gets escalated when it recurs; you do
not need a separate held-candidates list, because the retained log carries every prior one-off
forward. Count distinct PRs, not entries — multiple re-review runs of the SAME PR (e.g. `run 2` /
`run 3`) count as one PR for the ≥2 test.

| Signal | Fix | Where |
|--------|-----|-------|
| **Same detection miss (issue absent from findings) in ≥2 distinct PRs** (across current batch + retained history) | Add/sharpen a check | `_shared/review-checklist.md` |
| **Maintainer caught the same class of issue twice** | Add a high-priority rule | `_shared/review-checklist.md` |
| **Same judgment miss (found but `skipped`) in ≥2 distinct PRs** | Recalibrate severity / nitpick-filter so it isn't dropped — NOT a detection rule | `pr-code-review` (or checklist severity note) |
| **Same false-positive pattern in ≥2 distinct PRs** | Add a counter-rule / anti-pattern | `_shared/review-checklist.md` or `pr-code-review` |
| **A one-off miss with no matching class anywhere in the retained history** | Do NOT add a rule yet — the eval test gap-analyzer added already encodes it; it stays in `review-gaps-retro.md` and is reconsidered automatically next retro when the history is re-scanned | (no edit) |
| Workflow problem (findings file, posting flow, re-review) recurs | Fix the workflow | `pr-code-review` body |

**Over-fitting guard:** a gap in only ONE PR is not a pattern. Add a rule only on recurrence (≥2
PRs), OR for a P0 security/correctness miss a maintainer caught.

### Routing rule — where does each edit belong?

Decide the target by *kind*, to maximize leverage and avoid pollution:
- **Universal review rule** (applies to any codebase/language) → `_shared/review-checklist.md`. This
  is the default and highest-leverage target: both `pr-code-review` and the valkey self-reviewer gain
  it, and the eval covers it.
- **pr-code-review workflow** (findings file, posting, re-review, the review log) → the
  `pr-code-review` skill body only.
- **Finding shape / lenses / persisted-file format** → `_shared/review-findings-schema.md`.
- **Domain-specific check** (e.g. Valkey GLIDE) → does NOT belong here. Leave it out; it stays in
  that domain's own files. Never put a domain rule in the shared checklist.

## Step 4: Quantitative summary

Pull the recall/precision rows from the top of `review-gaps-retro.md`:

```markdown
## Review Skill Trend (from review-gaps-retro.md)

| Date | PR | Recall | Precision | Misses (det/judg) | False Pos | Maintainer misses |
|------|----|--------|-----------|-------------------|-----------|-------------------|

Trend: is recall rising across PRs? Is precision holding (not dropping from over-aggressive rules)?
```

If recall is flat or precision is dropping after a recent edit, flag it — a previous change may have
regressed. Precision drops are the signal that a rule got too aggressive.

## Step 5: Propose concrete changes

For each consolidated pattern:

```markdown
### Problem: [description]
**Evidence**: [quote from review-gaps-retro.md — include the PR number(s)]
**Recurrence**: [how many PRs / which ones — proves it's a pattern]
**Miss type**: detection | judgment | false-positive
**Impact**: 🔴 High / 🟡 Medium / 🟢 Low
**Target file**: `_shared/review-checklist.md` | `pr-code-review.md` | `_shared/review-findings-schema.md`  (per the routing rule)
**Current text**: [quote or summary]
**Proposed text**: [new text]
**Why**: [what this prevents]
**Eval test**: [which existing failing test in promptfooconfig.yaml this should make pass]
```

## Step 6: Apply changes and verify

After the user approves:
- Apply approved edits — insert under the correct existing section; sharpen an existing rule rather
  than adding a duplicate.
- **Run the eval to confirm the edits closed the gaps:**
  ```bash
  cd <config>/evals/pr-code-review && promptfoo eval --no-cache
  ```
  The positive tests gap-analyzer added for these gaps should now PASS. If one still fails, the rule
  wasn't strong enough — sharpen and re-run. Confirm no negative (`false-positive-avoidance`) test
  regressed — that's the signal a rule got too aggressive.
- **Sync edited skills/shared files back to the git-tracked repo:**
  ```bash
  ./sync.sh pull kiro      # or: ./sync.sh pull claude
  ```
  Review the diff before committing.
- **Finalize the ledger** at `<config>/retros/.processed-entries.md`: the per-`pr-review-log.md`
  ENTRY-IDs were already appended incrementally in Step 1c. Now (a) append the
  `review-gaps-retro.md` entry-IDs you folded into edits, and (b) update the `Last retro:` date (the
  watermark the next run counts from). NOT optional.
- **Confirm** — do not re-do — that every processed review already has `gap_analyzed: yes` in
  `pr-review-log.md` and a ledger record (both written per-entry in Step 1c). If any is missing, the
  Step 1 loop was interrupted before persisting; flip/record it now so it isn't re-analyzed next run.
- **Do NOT clear or delete the logs.** They are append-only; the ledger (not deletion) tracks
  processed state. When `review-gaps-retro.md` grows large, you may archive entries older than the
  most recent 50 to `<config>/retros/retro-archive/[date].md` — but always PRESERVE the
  recall/precision trend table at the top, and keep the ledger intact.

## Anti-Patterns

- DO NOT edit valkey-integration agents, ci-failure-review, or pr-comment-resolver — that's the
  generic `retrospective` skill's job. This skill owns only `pr-code-review` + shared review files.
- DO NOT put a domain-specific (e.g. Valkey GLIDE) rule into the shared checklist — it pollutes the
  general reviewer.
- DO NOT add a skill rule for a gap that occurred in only ONE PR — wait for recurrence (exception:
  P0 security/correctness misses caught by a maintainer).
- DO NOT re-invoke `pr-code-review-gap-analyzer` for an entry that already has `gap_analyzed: yes`, a
  ledger record, OR an existing gap entry in `review-gaps-retro.md`. Re-dispatching an
  already-processed entry is the infinite-loop failure mode. Persist progress per-entry (Step 1c) and
  honor the Step 1a idempotency guard — never defer flag/ledger writes to the end of the batch.
- DO NOT add a *detection* rule for a **judgment** miss — the skill already found it; fix the
  severity/nitpick calibration instead.
- DO NOT just summarize the gaps — every proposal must be a concrete text change to a named file.
- DO NOT skip the eval run after applying edits — an unverified edit is an unproven edit.
- DO NOT reprocess entries already in the ledger; DO NOT forget to update the ledger + `Last retro`.
- DO NOT clear/overwrite the logs — append-only; track state via the ledger.

---
> Path placeholders: `<config>` = your assistant's user-level dir (`~/.kiro` for Kiro, `~/.claude` for Claude); `<workspace-config>` = the per-project dir (`.kiro` / `.claude`). See `_shared/paths.md`.
