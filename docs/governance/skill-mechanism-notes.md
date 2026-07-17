# Skill Mechanism Notes — Claude Code

Claude Code discovers skills from `.claude/skills/` directories (user-level at
`~/.claude/skills/` or project-level at `<repo>/.claude/skills/`). Each skill is a
directory containing a `SKILL.md` file with YAML frontmatter (`name`, `description`,
`inclusion`).

The model sees available skills listed in its system prompt. When `inclusion: manual`,
the skill only runs when the user explicitly invokes it with `/skill-name`. When
`inclusion: auto`, the model decides whether to invoke based on the `description` field
matching the user's request.

Invocation signals: the `name` field matches slash-command input; the `description` field
is what the model reads to decide relevance for auto-inclusion. The skill's full
`SKILL.md` content is loaded into context only after invocation — so the description
must be precise enough for the model to decide without seeing the full instructions.

Observability: Claude Code shows which skill was loaded in the conversation context.
There's no separate invocation log — the conversation history IS the record. For Kiro,
skills are invoked with `#skill-name` and show in the chat as tool calls.

For the certification skill (`pr-code-review`), we use `inclusion: manual` — the user
explicitly invokes it because a code review is a deliberate act, not something that
should trigger autonomously mid-conversation.
