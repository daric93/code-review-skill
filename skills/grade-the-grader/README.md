# grade-the-grader

Meta-evaluation. Critiques whether the pr-code-review eval's llm-rubric grader and criteria are well-calibrated — catching graders that are too lenient, too strict, vague, or inconsistent. Run periodically to keep the eval itself trustworthy.

## Use it in

| Provider | Install | Invoke |
|---|---|---|
| Kiro | `./sync.sh kiro` (from repo root) → `~/.kiro/skills/grade-the-grader.md` | `#grade-the-grader` |
| Claude Code | `./sync.sh claude` → `~/.claude/skills/grade-the-grader/SKILL.md` | `/grade-the-grader` |
| Other | reference or paste `SKILL.md` into the assistant | — |

Add `--project /path/to/repo` to either sync command to install at project level
(`<repo>/.kiro/` or `<repo>/.claude/`) instead of user level.

The canonical, provider-neutral instructions live in [`SKILL.md`](SKILL.md).
