# pr-code-review

Performs a thorough code review of any GitHub PR — local workspace or fully remote. Supports any language/framework. Posts inline comments as a pending review for user approval before submission.

## Use it in

| Provider | Install | Invoke |
|---|---|---|
| Kiro | `./sync.sh kiro` (from repo root) → `~/.kiro/skills/pr-code-review.md` | `#pr-code-review` |
| Claude Code | `./sync.sh claude` → `~/.claude/skills/pr-code-review/SKILL.md` | `/pr-code-review` |
| Other | reference or paste `SKILL.md` into the assistant | — |

Add `--project /path/to/repo` to either sync command to install at project level
(`<repo>/.kiro/` or `<repo>/.claude/`) instead of user level.

The canonical, provider-neutral instructions live in [`SKILL.md`](SKILL.md).
