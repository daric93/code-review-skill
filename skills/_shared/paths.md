# Shared: portable paths & tool conventions

> Shared reference so skill bodies stay provider-neutral. Not a standalone skill.
> Skills use the placeholders below instead of hardcoding a provider's paths or tool names.

## Path placeholders

| Placeholder | Meaning | Kiro | Claude Code |
|---|---|---|---|
| `<config>` | your assistant's **user-level** config dir | `~/.kiro` | `~/.claude` |
| `<workspace-config>` | the assistant's **per-project** dir in the repo | `.kiro` | `.claude` |

So when a skill says `<config>/retros/review-gaps-retro.md`, read it as
`~/.kiro/retros/review-gaps-retro.md` in Kiro or `~/.claude/retros/review-gaps-retro.md` in Claude.

Installed skill files themselves live at:
- Kiro: `<config>/skills/<name>.md` (flat)
- Claude: `<config>/skills/<name>/SKILL.md` (folder)

## Tool placeholders

Skills name capabilities, not provider-specific tool IDs. Where a concrete tool helps, it is given
as a parenthetical example, e.g. "append to the file (in Kiro, `fs_append`)".

| Capability | Kiro tool (example) | Notes |
|---|---|---|
| append to a file without overwriting | `fs_append` | any append/edit mechanism is fine |
| delegate to a sub-agent | `invokeSubAgent` | only where the provider supports sub-agents; otherwise do the work inline |
| read / search files | `readFile`, `grepSearch`, `fileSearch` | use the provider's equivalents |
| run a shell command | `executeBash` | |

## Syncing edits back to this repo

Don't hardcode `cp ~/.kiro/... ~/Projects/...` chains in a skill. Use the repo's round-trip helper:

```bash
./sync.sh pull kiro      # or: ./sync.sh pull claude
```

This copies installed edits back into the tracked `SKILL.md` files regardless of provider.
