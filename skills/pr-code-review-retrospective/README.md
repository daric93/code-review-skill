# pr-code-review-retrospective

The improvement engine for the `pr-code-review` skill. Walks the review log (`pr-review-log.md`),
drives `pr-code-review-gap-analyzer` over new reviews, consolidates the gaps across PRs, and
applies verified edits to `pr-code-review` and its shared review files
(`_shared/review-checklist.md`, `_shared/review-findings-schema.md`), then re-runs the eval.

Owns the review domain only. A separate generic `retrospective` skill (in the full toolkit, not
included in this certification submission) owns the non-review domains (valkey-integration,
ci-failure-review, pr-comment-resolver).

## Use it in

| Provider | Install | Invoke |
|---|---|---|
| Kiro | `./sync.sh kiro` (from repo root) → `~/.kiro/skills/pr-code-review-retrospective.md` | `#pr-code-review-retrospective` |
| Claude Code | `./sync.sh claude` → `~/.claude/skills/pr-code-review-retrospective/SKILL.md` | `/pr-code-review-retrospective` |
| Other | reference or paste `SKILL.md` into the assistant | — |

Add `--project /path/to/repo` to either sync command to install at project level
(`<repo>/.kiro/` or `<repo>/.claude/`) instead of user level.

The canonical, provider-neutral instructions live in [`SKILL.md`](SKILL.md).
