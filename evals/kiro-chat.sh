#!/usr/bin/env bash
# Wrapper for promptfoo exec: provider.
# promptfoo calls: script "<prompt>" '<provider-json>' '<context-json>'
# kiro-cli only wants the first argument (the prompt); the rest are promptfoo internals.

# promptfoo spawns this in a non-login shell whose PATH may not include the
# kiro-cli install dir. Ensure the common install location is on PATH so the
# eval works regardless of how it was launched.
export PATH="$HOME/.local/bin:$PATH"

exec kiro-cli chat --no-interactive --trust-tools=read,grep "$1"
