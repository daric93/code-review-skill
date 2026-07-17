# security-review

Focused, fresh-eyes security review of a diff/PR/fileset — injection, auth/authz, secrets, insecure
data handling — returning a severity-ranked findings report with `file:line` and concrete fixes.
Does not modify code or run tests.

| Provider | Install | Invoke |
|---|---|---|
| Kiro | `./sync.sh kiro` → `~/.kiro/skills/security-review.md` | `#security-review` |
| Claude Code | `./sync.sh claude` → `~/.claude/skills/security-review/SKILL.md` | `/security-review` |
| Other | reference or paste `SKILL.md` | — |

## Skill vs the `security-reviewer` agent

This **skill** is the canonical security-review method and criteria — usable standalone, in any
provider. The **`security-reviewer` agent** (`agents/security-reviewer.md`) is a thin Kiro sub-agent
wrapper that *applies this skill* and adds orchestration: Mode A (Valkey Phase 5b → writes
`.kiro/valkey-phases/phase-5b-security.md`) and Mode B (inline findings for `pr-code-review`).

So the security checks live here; the agent just runs them with fresh context where a pipeline needs
a dedicated sub-agent. `pr-code-review` delegates its security pass by spawning that sub-agent and
telling it to apply this skill.
