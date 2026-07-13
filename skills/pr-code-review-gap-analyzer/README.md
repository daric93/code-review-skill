# pr-code-review-gap-analyzer

Compares your pr-code-review output against what OTHER reviewers (humans + bots) caught on the same PR. Logs misses and false positives, then proposes concrete improvements to pr-code-review and pr-comment-resolver skills plus new eval test cases. The self-improvement engine for review skills.

## Use it in

| Provider | Install | Invoke |
|---|---|---|
| Kiro | `./sync.sh kiro` (from repo root) → `~/.kiro/skills/pr-code-review-gap-analyzer.md` | `#pr-code-review-gap-analyzer` |
| Claude Code | `./sync.sh claude` → `~/.claude/skills/pr-code-review-gap-analyzer/SKILL.md` | `/pr-code-review-gap-analyzer` |
| Other | reference or paste `SKILL.md` into the assistant | — |

Add `--project /path/to/repo` to either sync command to install at project level
(`<repo>/.kiro/` or `<repo>/.claude/`) instead of user level.

The canonical, provider-neutral instructions live in [`SKILL.md`](SKILL.md).
