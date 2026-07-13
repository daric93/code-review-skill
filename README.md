# code-review-skill

A production-grade, provider-neutral **AI code-review skill** — plus the reusable skills it
composes, the **promptfoo evaluation harness** that scores it (skill-vs-baseline A/B included),
and a short write-up on how the skill is evaluated and improved.

Works with [Kiro](https://kiro.dev) (`#skill-name`) and [Claude Code](https://docs.claude.com/claude-code)
(`/skill-name`) from a single canonical `SKILL.md` per skill.

> Extracted from a larger toolkit for standalone use and certification. The parent repo remains
> the source of truth; this repo is a self-contained, runnable subset focused on `pr-code-review`.

## What's in here

```
skills/
  pr-code-review/                 # the skill: full PR review + re-review workflow
  security-review/                # focused security pass (delegated to by pr-code-review)
  pr-code-review-gap-analyzer/    # sensor: my review vs other reviewers → logged gaps
  pr-code-review-retrospective/   # analyst/editor: consolidates gaps → edits rules → re-runs eval
  grade-the-grader/               # meta-eval: audits the eval's own grading quality
  _shared/                        # the rulebook + finding schema shared across the skills
agents/
  security-reviewer.md            # thin sub-agent wrapper applying security-review
  pr-code-review-gap-analyzer.md  # thin sub-agent wrapper applying the gap analyzer
evals/
  kiro-review.sh                  # provider: runs the review WITH the skill (checklist + gates)
  kiro-baseline.sh                # provider: runs the bare model (A/B control, skill OFF)
  kiro-grade.sh                   # grader: sanitizes kiro-cli output to clean JSON for llm-rubric
  kiro-chat.sh                    # bare passthrough wrapper
  pr-code-review/
    promptfooconfig.yaml          # 27-test graded suite (SKILL ON)
    promptfooconfig.baseline.yaml # representative subset (SKILL OFF) for the A/B
EVALUATION.md                     # the write-up: how the skill is evaluated & improved (blog format)
sync.sh                           # install skills/agents into Kiro or Claude
```

## The skill

[`pr-code-review`](skills/pr-code-review/SKILL.md) does a thorough review of any GitHub PR —
local workspace or fully remote, any language. It gathers PR + ticket context, reviews against a
shared [rulebook](skills/_shared/review-checklist.md), optionally fans the review out to
fresh-context sub-agents (one per lens), runs a dedicated
[security pass](skills/security-review/SKILL.md), applies **precision gates**
(verify-before-flag, nitpick filter, never-fabricate), then posts inline comments as a *pending*
GitHub review that you approve before submission.

It's built for **both recall** (catch the real bugs) **and precision** (don't fabricate issues in
correct code) — the eval scores both.

## Install & use

```bash
./sync.sh kiro       # installs skills + agents to ~/.kiro/
./sync.sh claude     # or to ~/.claude/
./sync.sh kiro --project /path/to/repo    # install into a specific repo instead
```

Then invoke it:

```
#pr-code-review                       (Kiro)      /pr-code-review   (Claude)
Review this PR: https://github.com/owner/repo/pull/123
Ticket: https://github.com/owner/repo/issues/456     (optional)
Focus: correctness, test coverage                    (optional)
```

Re-review a PR you already reviewed with `Re-review: <PR URL>`. See each skill's `README.md` for
per-provider invocation and [`CONVENTIONS.md`](CONVENTIONS.md) for the cross-provider format.

## Run the evals

The review skill is treated like production code: it has a test suite, a measured baseline, and a
graded rubric. Built on [promptfoo](https://promptfoo.dev); both the review and the grading run
through `kiro-cli` (no separate API key).

```bash
npm install -g promptfoo                          # once
curl -fsSL https://cli.kiro.dev/install | bash    # once — provides kiro-cli

cd evals/pr-code-review

# A/B — the evidence of value (run both, then compare per-metric scores):
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # SKILL OFF (bare model)
promptfoo eval -c promptfooconfig.yaml          --no-cache   # SKILL ON
promptfoo view                                               # dashboard: scores, trends, diffs

# Iterate on one dimension while editing the rulebook:
promptfoo eval --filter-pattern "SQL injection"
```

Full run/maintain guide in [`evals/README.md`](evals/README.md). Read
[`EVALUATION.md`](EVALUATION.md) for the story of how the skill is evaluated and kept sharp,
including real scores from a recent run.

## How it improves itself (short version)

```
PRs I review  → #pr-code-review → others comment → #pr-code-review-gap-analyzer ┐
                                                                        ├→ gaps log
                                              (misses/false-positives, recall/precision)│
every ~3 PRs  →                                       #pr-code-review-retrospective ────┘
                          (consolidate patterns → edit the rulebook → re-run the eval → sync)
```

Sensors only log facts and add tests; the retrospective is the only step that edits rules, and
only when a gap recurs across ≥2 PRs (an over-fitting guard). `grade-the-grader` periodically
audits the grader so scores stay honest. Details in [`EVALUATION.md`](EVALUATION.md).

## Scope & provenance

This repo is the general-purpose review core. A couple of references in the skill bodies point at
optional pieces that live in the parent toolkit and are **not required here**:

- **`glide-reviewer`** — an optional, self-gating Valkey-GLIDE domain reviewer. `pr-code-review`
  uses it only "if available"; on any non-GLIDE code it does nothing, so its absence changes
  nothing.
- **the Valkey self-reviewer** — another consumer of the same shared checklist in the source
  project; mentioned to explain why the rulebook lives in `_shared/`.
- **`pr-comment-resolver`** — the author-side companion (fix reviewer comments on your own PRs);
  referenced only to disambiguate roles. Out of scope for this review-focused repo.

The shared `_shared/*.md` files are copied verbatim from the parent toolkit to preserve fidelity;
some structure (finding schema, shared includes) is adapted from
[edlng/agents](https://github.com/edlng/agents) and noted inline.

## License

MIT — see [`LICENSE`](LICENSE).
