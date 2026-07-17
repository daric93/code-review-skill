# Shared: Review findings schema & lenses

> Shared reference used by `pr-code-review`'s fan-out reviewers. Not a standalone skill.
> Single source of truth for the findings shape, the review lenses, and the filing rules.
> Consuming skills may add their own lenses or severity vocabulary on top of this base.
> Adapted from [edlng/agents](https://github.com/edlng/agents) `skills/_shared/review-findings-schema.md`.

## Finding shape

Each finding has:

- `id` — short slug, e.g. `auth-missing-rate-limit`
- `lens` — see lenses below
- `file` — path
- `line_range` — e.g. `42-58`
- `severity` — `blocking` | `suggestion` | `nit` (a consuming skill may override, e.g. `must_fix` | `should_fix` | `consider`)
- `claim` — one sentence: what is wrong
- `evidence` — one or two literal lines from the diff/codebase that prove the claim. **If you cannot quote evidence, do not file the finding.**
- `suggested_fix` — a concrete change

## The four core lenses (apply in this order)

**Codebase alignment is the primary lens** — a change that does not fit the existing codebase is a defect regardless of correctness. Load the diff once, not once per lens.

1. **Codebase alignment & design fit (PRIMARY)** — Does the code belong in this codebase? Flag reimplemented utilities that already exist nearby, naming/casing that deviates from convention, mismatched error-handling/logging style, layering violations, premature abstraction, duplication. Only flag what conflicts with patterns visible in the code, not matters of taste.
2. **Correctness & security** — logic bugs, off-by-ones, races, unhandled errors, broken invariants; injection (SQL/command/template/query-DSL), authn/authz gaps, secrets in code, unsafe deserialization, SSRF, path traversal, weak crypto, missing input validation at trust boundaries. Be concrete about the threat model — generic "add validation" findings get rejected.
3. **Requirements alignment** — Does it satisfy every acceptance criterion? Quote the requirement. Flag missing/partial coverage and scope creep. Skip if no requirements source exists.
4. **Testability** — Do tests cover every acceptance criterion and listed edge case? Do they assert behavior or just exercise code paths? Are dependencies mocked that should be real? Missing tests for new failure paths?

## Filing rules

- Only flag what is in the diff, except where surrounding context is essential to prove a diff issue (e.g. a caller breaks due to a signature change in the diff).
- Cite a real symbol, file, and line. Never invent function names or files.
- Default severity rubric:
  - `blocking` — violates a requirement, introduces a real security/correctness bug, breaks an interface, or fails tests.
  - `suggestion` — a real improvement (perf, clarity, robustness) that does not block merge.
  - `nit` — pure style/naming.
- If you are not sure something is wrong, omit it. A verification pass will downgrade or reject a weak finding, not rescue it.

## Persisted findings file (pr-code-review)

`pr-code-review` persists every run's findings to a durable Markdown file **before** posting, so
the user can review/approve offline and so `pr-code-review-gap-analyzer` can later read what was found —
including findings that were deliberately **not** posted. This is the single source of truth for
"what our review found on this PR."

**Path:** `<config>/reviews/<YYYY-MM-DD>__<owner>__<repo>__pr<N>.md`
(same-day re-review of the same PR → append `__run2`, `__run3`, … to keep the path unique).

**Required header** (so the file is self-describing and parseable):

```markdown
---
pr_url: https://github.com/owner/repo/pull/123
repo: owner/repo
pr_number: 123
review_date: 2026-06-29
head_sha: <commit SHA reviewed>
reviewer: <your account / $ME>
verdict: REQUEST_CHANGES | COMMENT | APPROVE | (pending)
tickets: [optional issue/design-doc links]
---

# Review findings — owner/repo#123 (2026-06-29)
```

**Each finding** uses the finding shape above, plus one extra field that records the
human-in-the-loop decision:

- `decision` — `proposed` (default, before approval) → updated to one of:
  - `posted` — approved and posted as an inline comment.
  - `skipped` — the user chose not to post it. **Record a one-line `skip_reason`** (e.g.
    "out of scope", "nit", "disagreed", "duplicate of @x").

A trailing summary line: `posted: X / skipped: Y / total: N`.

**Why the `decision` field matters:** it lets `pr-code-review-gap-analyzer` distinguish two very different
gap types when a maintainer later catches something:
- the issue is **absent** from the findings file → a **detection miss** (the skill never found it;
  fix = a new checklist rule + positive eval test).
- the issue is **present but `skipped`** → a **judgment/triage miss** (the skill found it but we
  dropped it; fix = severity/nitpick-filter calibration or posting guidance, NOT a detection rule).
Without the persisted decision, these are indistinguishable and lead to wrong fixes.
