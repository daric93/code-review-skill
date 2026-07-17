# Governed Flow — Test Results

## The Flow (Option B: deferred consumer)

```
pr-code-review (sensor)
    writes: findings file  +  pr-review-log entry (gap_analyzed: no)
    never edits prompts
        │
        ▼  [HOOK: validate-findings.sh runs on findings-file write]
        │   validates STRUCTURE (required fields, valid verdict, decision state)
        │   pass → entry is a valid contract, available to downstream
        │   halt → contract broken, entry not consumable
        │
        ▼  (deferred — runs later, when ≥3 new entries accumulate)
pr-code-review-retrospective (orchestrator)
    walks pr-review-log, gates on ≥3 unprocessed entries, per entry:
        │
        ▼
    pr-code-review-gap-analyzer (sensor)
        compares review vs other reviewers on that PR
        logs misses / false positives
        ADDS EVAL TESTS (failing = red phase)   ← test-before-prompt enforced here
        never edits prompts
        │
        ▼
    retrospective consolidates gaps across PRs, proposes + applies prompt edits,
    re-runs eval (failing tests turn green = green phase)
```

The **contract** between sensor and consumer is the findings file + log entry. The hook
enforces that the contract is well-formed. Consumption is deferred, not immediate — this is
the key difference from the exercise's Step1→Step2 pattern, and it matches the real system.

## Test Scenarios

### Scenario 1: Go path (happy path)

**Setup:** pr-code-review runs on a PR with 2 real bugs. Writes findings file with both
findings, verdict `REQUEST_CHANGES`, all decisions recorded (`posted`). Writes log entry
with `gap_analyzed: no`.

**Hook result:** PASS — all required fields present, verdict valid, no `proposed` findings
left after a non-pending verdict.

**Downstream:** Entry sits in the log until the next retro. When retro runs (≥3 entries),
this entry is picked up, gap-analyzed, and folded into consolidation.

**Verdict:** ✅ Flow proceeds as designed.

---

### Scenario 2: No-go path (malformed contract)

**Setup:** pr-code-review crashes mid-write — findings file is missing the `verdict:` field.

**Hook result:** HALT — "Findings file malformed: missing 'verdict' header."

**Downstream:** The log entry (if written) points to a findings file that can't be consumed.
Because the hook halted, the user knows immediately the review didn't complete cleanly and
can re-run. gap-analyzer will not be handed a broken file.

**Verdict:** ✅ No-go correctly blocks a broken contract from entering the pipeline.

---

### Scenario 3: Gap-but-structurally-valid (the hook is the floor, not the ceiling)

**Setup:** pr-code-review runs on a PR with a subtle race condition. It MISSES the race but
finds a lesser issue. Findings file is well-formed: valid verdict, all fields present,
findings recorded.

**Hook result:** PASS — the file is structurally valid. The hook cannot know a bug was
missed; it validates structure, not quality.

**Downstream:** Later, gap-analyzer compares this review against the human reviewer who caught
the race. It logs a **detection miss** and writes a **failing positive eval test** encoding
"the skill should catch this race." The test fails (red). At the next retrospective, the
recurrence is evaluated; if the race pattern appears in ≥2 PRs, retrospective adds a checklist
rule and re-runs the eval until the test passes (green).

**Verdict:** ✅ The hook (structure) and the eval (quality) are complementary layers. A
quality gap slips past the hook — correctly — and is caught by the deferred quality layer.
This is why the hook is NOT a quality gate.

---

### Scenario 4: Missing sentinel (crash before write)

**Setup:** pr-code-review crashes during Phase 2 (analysis), before Phase 3.5 writes the
findings file. No findings file exists.

**Hook result:** HALT — "Findings file not found. Review did not complete."

**Downstream:** No log entry with `gap_analyzed: no` is created for a review that didn't
happen. Retrospective's idempotency ledger only processes entries that exist; a review that
never wrote its contract is simply absent — it isn't silently marked processed and lost. The
user re-runs the review.

**Verdict:** ✅ A missing sentinel halts cleanly and loses nothing. The append-only log +
ledger design means an incomplete review leaves no false "processed" state.

---

## What This Demonstrates

- **Structure vs quality separation:** the hook enforces the contract's *shape*
  (deterministic, fast, cannot judge correctness). The eval enforces the contract's *quality*
  (probabilistic, deferred, judges correctness against ground truth). Scenario 3 is the proof
  they're different layers.
- **Test-before-prompt is architectural:** gap-analyzer (adds failing tests) and retrospective
  (edits prompts to pass them) are separate skills. The prompt literally cannot be edited
  before the test exists, because the skill that finds gaps is forbidden from editing prompts.
- **Deferred consumption is safe:** the append-only log + idempotency ledger means a broken or
  missing contract (Scenarios 2, 4) never corrupts downstream state — the entry is either
  absent or flagged, never silently consumed.
