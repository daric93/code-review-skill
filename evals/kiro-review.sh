#!/usr/bin/env bash
# Review provider for promptfoo — generates the code review the way the
# pr-code-review skill would, so the eval grades the SKILL, not the bare model.
#
# Why this exists: promptfoo sends each test's code snippet as a bare prompt.
# The pr-code-review skill is `inclusion: manual`, so kiro-cli does NOT auto-load
# it — a bare prompt measures raw model behavior and ignores the checklist. This
# wrapper reconstructs the skill's review behavior for a snippet:
#   1. it injects the real review-checklist.md (the rulebook — single source of
#      truth, so checklist edits flow straight into the eval), and
#   2. a compact preamble mirroring the skill's Phase-3 precision gates
#      (verify-before-flag, nitpick filter, never-fabricate) so the recall-
#      oriented checklist doesn't cause the negative tests to regress.
# It intentionally omits the skill's GitHub-posting / re-review / retrospective
# workflow, which is irrelevant to grading a code snippet.
#
# The grader stays in kiro-grade.sh; the main review runs here.

export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the checklist: repo layout first, then installed Kiro/Claude layouts.
CHECKLIST=""
for c in \
  "$SCRIPT_DIR/../skills/_shared/review-checklist.md" \
  "$HOME/.kiro/skills/_shared/review-checklist.md" \
  "$HOME/.claude/skills/_shared/review-checklist.md"; do
  if [ -f "$c" ]; then CHECKLIST="$c"; break; fi
done

checklist_text=""
if [ -n "$CHECKLIST" ]; then
  checklist_text="$(cat "$CHECKLIST")"
fi

PREAMBLE="$(cat <<'ENDOFPREAMBLE'
You are performing a professional code review, following the pr-code-review skill.
Review ONLY the code provided at the end of this message.

Apply every relevant check from the REVIEW CHECKLIST below as your rulebook. For each
real issue, report it with: a short label (Bug / Security / Performance / Design /
Test / Nit), what is wrong and why it matters, and a concrete, actionable fix (include
a corrected code snippet where useful).

Precision rules — these are as important as finding issues:
- Verify before you flag: only report an issue that is genuinely present in the code
  shown. Never fabricate, speculate, or pad the review with issues that are not there.
- Do NOT flag correct code. If a construct is correct for its stated intent, do not
  invent a problem with it; at most note a minor, clearly-optional suggestion.
- Scope discipline: review ONLY what the code snippet does. Do NOT invent missing
  features (e.g. "this function should also validate X") unless the absence is a clear
  correctness or security bug given the stated purpose. A function that does one thing
  correctly is not deficient for not doing other things.
- Do NOT flag missing error handling, missing timeouts, or missing validation on code
  that does not make any external calls or perform any I/O — those concerns only apply
  when the code actually does network/IO operations.
- Do NOT flag Rust code for resource leaks: the Rust ownership and RAII/Drop system
  guarantees cleanup automatically. Do not invent resource leak findings in Rust unless
  there is explicit use of unsafe or an FFI resource that is provably not cleaned up.
- Do NOT flag correct use of async context managers (e.g. "async with session:" in
  Python aiohttp) as a resource leak. Context managers guarantee cleanup by design.
  Only flag a resource leak if there is an actual missing close/cleanup path in the
  code shown.
- Drop pure style/formatting nits with no functional, security, or correctness impact.
- Always surface security and correctness issues that ARE present; never suppress those.
- Be specific and concrete — no vague "this could be better" remarks.
- Never repeat a finding across multiple instances — comment once, note other locations.

REVIEW CHECKLIST
================
ENDOFPREAMBLE
)"

prompt="${PREAMBLE}
${checklist_text}

CODE TO REVIEW
==============
${1}"

exec kiro-cli chat --no-interactive --trust-tools=read,grep --model claude-sonnet-4.6 "$prompt"
