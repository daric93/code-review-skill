# Skills

Each skill is a folder with a canonical, provider-neutral `SKILL.md` and a short `README.md`.
See [`../CONVENTIONS.md`](../CONVENTIONS.md) for the cross-provider format and
[`../EVALUATION.md`](../EVALUATION.md) for how these are evaluated and improved.

| Skill | What it does | Kiro | Claude |
|---|---|---|---|
| [pr-code-review](pr-code-review/) | Thorough review of any GitHub PR (local or remote), inline comments posted as a pending review; optional sub-agent fan-out, security pass, nitpick filter, per-finding verification, and a re-review mode | `#pr-code-review` | `/pr-code-review` |
| [security-review](security-review/) | Focused fresh-eyes security pass (injection, auth, secrets, data handling) → severity-ranked findings report | `#security-review` | `/security-review` |
| [pr-code-review-gap-analyzer](pr-code-review-gap-analyzer/) | Compares my review against other reviewers on the same PR to find misses/false positives; logs gaps + proposes eval tests | `#pr-code-review-gap-analyzer` | `/pr-code-review-gap-analyzer` |
| [pr-code-review-retrospective](pr-code-review-retrospective/) | The improvement engine: consolidates recurring gaps, edits the shared rulebook, re-runs the eval | `#pr-code-review-retrospective` | `/pr-code-review-retrospective` |
| [grade-the-grader](grade-the-grader/) | Meta-eval: audits the eval's own grading quality so scores stay trustworthy | `#grade-the-grader` | `/grade-the-grader` |

Shared includes used by several skills live in [`_shared/`](_shared/) (not standalone skills).

## Installing

Use the repo's sync script (don't hand-copy):

```bash
../sync.sh kiro       # installs every skill to ~/.kiro/skills/<name>.md
../sync.sh claude     # installs every skill to ~/.claude/skills/<name>/SKILL.md
```

Add `--project /path/to/repo` to install at project level instead of user level.
