# Shared references

Cross-cutting reference docs that several skills include, so a rule lives in exactly one place.
These are **not** standalone skills (no frontmatter, no `SKILL.md`) — they are includes.

| File | Used by |
|---|---|
| `review-checklist.md` | `pr-code-review` (and the security baseline) — the language-agnostic review rulebook: *what* to check |
| `review-findings-schema.md` | `pr-code-review` fan-out reviewers — the finding shape, review lenses, and persisted-findings-file format |
| `paths.md` | every skill that references config/retro/eval paths or provider tools |

## How they install

`sync.sh` copies `skills/_shared/*.md` to `~/.kiro/skills/_shared/` (Kiro) and
`~/.claude/skills/_shared/` (Claude). A skill installed as `~/.kiro/skills/<name>.md` can then
reference `_shared/<file>.md` as a sibling directory.

## Portability note

When pasting a single `SKILL.md` into a tool that doesn't support file references (Cursor, Codex,
etc.), also paste the referenced `_shared/*.md` content. The skills are written to degrade
gracefully — they name the patterns they rely on even when the include is unavailable.

## Provenance

`review-checklist.md` is the single source of truth for review rules; in the parent toolkit it is
also consumed by a Valkey self-reviewer (out of scope here — see the root README). The finding
schema and the shared-include pattern are adapted from
[edlng/agents](https://github.com/edlng/agents), rephrased for licensing compliance.
