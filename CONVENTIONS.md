# Conventions

How skills, agents, and evals are structured in this repo, and how to use a single
`SKILL.md` across Kiro, Claude Code, and other assistants.

## One skill, many providers

Each skill is a folder with a canonical, provider-neutral `SKILL.md` plus a short `README.md`:

```
skills/<skill-name>/
├── SKILL.md     # the skill instructions (canonical source of truth)
└── README.md    # what it does, when to use, per-provider invocation
```

### Frontmatter (superset that works everywhere)

```yaml
---
name: skill-name
description: One-line description of what the skill does and when to use it.
inclusion: manual        # Kiro reads this; Claude and others ignore unknown keys
---
```

Keeping `inclusion: manual` is safe across providers — Kiro uses it to load the skill only
when referenced; Claude Code and others ignore keys they don't recognize.

### Invocation differs by provider

| Provider | Install location (user) | Install location (project) | Invoke |
|---|---|---|---|
| Kiro | `~/.kiro/skills/<name>.md` | `<proj>/.kiro/skills/<name>.md` | `#<name>` |
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | `<proj>/.claude/skills/<name>/SKILL.md` | `/<name>` |
| Other (Cursor, Codex, etc.) | n/a | n/a | paste or @-reference `SKILL.md` |

Write `SKILL.md` bodies provider-neutral ("when this skill runs…") rather than hardcoding
`#name` or `/name`. Provider-specific invocation lives in the per-skill `README.md`.

### Shared includes (`skills/_shared/`)

Cross-cutting rules that several skills reuse (e.g. the humanizer pattern catalog, the review
findings schema, the path/tool conventions) live in `skills/_shared/*.md`. They are **not**
standalone skills — no frontmatter, no `SKILL.md`. `sync.sh` installs them to
`<root>/skills/_shared/` for both providers, so an installed skill can reference `_shared/<file>.md`
as a sibling directory. Skills that depend on a shared include still name the rules they rely on,
so they degrade gracefully when pasted into a tool that can't resolve the include.

### Provider-neutral paths and tools in skill bodies

Skill bodies never hardcode `~/.kiro/` or a Kiro-only tool name. They use the placeholders defined
in [`skills/_shared/paths.md`](skills/_shared/paths.md): `<config>` for the user-level assistant dir
(`~/.kiro` in Kiro, `~/.claude` in Claude) and `<workspace-config>` for the per-project dir
(`.kiro` / `.claude`). Concrete tools appear only as parenthetical examples ("append to the file —
in Kiro, `fs_append`"). Each affected skill carries a one-line footer pointing at `paths.md` so it's
self-explanatory standalone. Provider-specific **invocation** (`#name` vs `/name`) stays in each
skill's `README.md`.

### Installing (don't copy by hand)

`./sync.sh` adapts the canonical layout to each provider automatically:

```bash
./sync.sh kiro                 # push to ~/.kiro      (flat <name>.md)
./sync.sh claude               # push to ~/.claude    (folder <name>/SKILL.md)
./sync.sh kiro --project ../some-repo     # install into that repo's .kiro/
./sync.sh status kiro          # show which installed files differ from the repo
./sync.sh pull kiro            # copy installed edits back into the repo (round-trip)
```

`status`/`pull` make the repo the source of truth round-trippable: edit a skill live in
`~/.kiro/`, then `pull` it back into the tracked `SKILL.md`.

## Agents

`agents/*.md` are Kiro custom-agent definitions (general purpose). Project-specific agents
live under `projects/<project>/agents/`. Claude Code subagents use a different format, so
agents are not auto-installed for the claude target — port them manually if needed.

## Steering

`steering/*.md` are Kiro steering files (extra always-on or conditional context). `sync.sh kiro`
installs them to `~/.kiro/steering/`. They use Kiro front-matter (`inclusion: auto|fileMatch|manual`)
that other providers ignore. Steering is Kiro-specific and is not installed for the claude target.

## Evals

`evals/` holds promptfoo test suites that score skills via the Claude CLI (through the
`claude.js` wrapper). See `evals/README.md`.

## Project-specific vs general

General, reusable skills/agents live at the top level. Anything bound to a specific project
(e.g. Valkey integration) lives under `projects/<project>/` with its own `skills/` and
`agents/`. This keeps the reusable toolkit clean and namespaces the project work.
