#!/usr/bin/env bash
# Grader wrapper for promptfoo's llm-rubric provider.
#
# The grader uses kiro-cli just like the main provider, but llm-rubric expects
# the model's reply to be a parseable JSON object. kiro-cli decorates its chat
# output (a leading "> " marker, a "Credits/Time" footer, sometimes a code
# fence, and occasionally raw newlines inside string values) which can make
# promptfoo's strict JSON extraction fail ("Could not extract JSON from
# llm-rubric response"). This wrapper isolates that: it runs kiro-cli, finds the
# first balanced {...} object, and re-serializes it so promptfoo always gets
# clean, valid JSON. The main review provider keeps using kiro-chat.sh unchanged.

# promptfoo spawns this in a non-login shell; make sure kiro-cli is findable.
export PATH="$HOME/.local/bin:$PATH"

raw="$(kiro-cli chat --no-interactive --trust-tools=read,grep --model claude-sonnet-4.6 "$1" 2>/dev/null)"

# Pass the captured output via an env var (not stdin): the heredoc below is
# itself the Python program on stdin, so the raw text must arrive another way.
RAW="$raw" python3 - <<'PY'
import os, sys, json

text = os.environ.get("RAW", "")

def extract(s):
    """Return a clean JSON string for the first balanced {...} that parses,
    re-serialized via json.dumps so the consumer never sees control chars or
    chat decoration. Falls back to None if nothing parseable is found."""
    for i, c in enumerate(s):
        if c != '{':
            continue
        depth = 0
        in_str = False
        esc = False
        for j in range(i, len(s)):
            ch = s[j]
            if in_str:
                if esc:
                    esc = False
                elif ch == '\\':
                    esc = True
                elif ch == '"':
                    in_str = False
            else:
                if ch == '"':
                    in_str = True
                elif ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0:
                        cand = s[i:j + 1]
                        # strict first, then tolerant of raw control chars
                        for kw in ({}, {"strict": False}):
                            try:
                                return json.dumps(json.loads(cand, **kw))
                            except Exception:
                                pass
                        break  # this candidate didn't parse; try the next '{'
    return None

obj = extract(text)
# Fall back to the raw text so a genuine non-JSON reply still surfaces as a
# real promptfoo error rather than being silently masked.
sys.stdout.write(obj if obj is not None else text)
PY
