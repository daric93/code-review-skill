#!/usr/bin/env bash
# BASELINE provider for promptfoo — the A/B control for the pr-code-review eval.
#
# This is the "no-skill" arm of the comparison. It sends the test's code snippet
# to the SAME model as the skill provider (kiro-review.sh) but injects NONE of the
# skill's machinery: no review-checklist.md rulebook and no Phase-3 precision
# preamble. It measures what the bare model does when simply asked to review code.
#
# Running this config alongside promptfooconfig.yaml (the skill arm) isolates a
# single variable — "checklist + precision gates present or not" — so the
# per-metric score delta is the skill's measured value-add. This is the
# certification "evidence of value": same tests, same grader, same model, skill
# on vs skill off.
#
# Keep the model pin identical to kiro-review.sh so the ONLY difference between
# the two arms is the injected skill context.

export PATH="$HOME/.local/bin:$PATH"

# A minimal, neutral instruction. The test prompts already say "Review this
# <lang> code:" so we add only enough framing to elicit a review, deliberately
# WITHOUT the checklist or the verify-before-flag / nitpick / never-fabricate
# gates that the skill arm supplies.
prompt="You are reviewing code. Point out any real issues you find and suggest fixes.

${1}"

exec kiro-cli chat --no-interactive --trust-tools=read,grep --model claude-sonnet-4.6 "$prompt"
