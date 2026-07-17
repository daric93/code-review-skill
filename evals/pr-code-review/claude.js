#!/usr/bin/env node
// Combined Claude Code CLI provider and grader for promptfoo
//
// Auto-detects mode based on prompt format:
// - Grader mode: Prompt is JSON array [{role, content}, ...]
// - Provider mode: Prompt is plain text
//
// Provider: Passes prompt directly to Claude CLI with --model flag
// Grader: Parses JSON chat array, routes system message via --system-prompt

const { spawnSync } = require('child_process');

const prompt = process.argv[2];
const options = process.argv[3];

// Extract a clean JSON object from CLI stdout that may be wrapped in prose or
// markdown code fences. promptfoo's llm-rubric parser needs a bare JSON object;
// the `claude -p` CLI sometimes ignores "raw JSON only" and fences/prefixes it,
// which silently scored a passing review as 0. Returns the JSON string if found,
// else the original text (so a genuinely non-JSON response still surfaces).
function extractJson(text) {
  if (!text) return text;
  // 1. Strip a ```json ... ``` or ``` ... ``` fence if present.
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fence ? fence[1] : text;
  // 2. Extract the first balanced {...} object.
  const start = body.indexOf('{');
  if (start === -1) return body.trim();
  let depth = 0, inStr = false, esc = false;
  for (let i = start; i < body.length; i++) {
    const ch = body[i];
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) return body.slice(start, i + 1); }
  }
  return body.trim();
}

// Run the claude CLI, retrying once on empty/non-JSON output in grader mode.
function runClaude(args, { expectJson } = {}) {
  for (let attempt = 0; attempt < (expectJson ? 2 : 1); attempt++) {
    const result = spawnSync('claude', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
    if (result.error) { console.error(result.error.message); process.exit(1); }
    if (result.status !== 0) { console.error(result.stdout || result.stderr); process.exit(result.status || 1); }
    if (!expectJson) return result.stdout;
    const json = extractJson(result.stdout);
    try { JSON.parse(json); return json; } catch (e) { /* retry once */ }
  }
  // Both attempts failed to yield parseable JSON — emit the last try so promptfoo
  // reports the real parse failure rather than a spurious pass.
  const last = spawnSync('claude', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  return extractJson(last.stdout);
}

let isGraderMode = false;
try {
  const parsed = JSON.parse(prompt);
  if (Array.isArray(parsed) && parsed.length > 0 && parsed[0].role) {
    isGraderMode = true;
  }
} catch (e) {
  // Not JSON — provider mode
}

if (isGraderMode) {
  let systemMsg, userMsg;
  try {
    const messages = JSON.parse(prompt);
    const systemMessage = messages.find(m => m.role === 'system');
    const userMessage = messages.find(m => m.role === 'user');
    systemMsg = systemMessage ? systemMessage.content : '';
    userMsg = userMessage ? userMessage.content : prompt;
  } catch (e) {
    systemMsg = 'You are an evaluator. Respond with only valid JSON: {"pass": bool, "score": 0.0-1.0, "reason": "string"}';
    userMsg = prompt;
  }

  console.log(runClaude(['-p', userMsg, '--system-prompt', systemMsg, '--model', 'sonnet'], { expectJson: true }));
} else {
  let model = 'sonnet';
  if (options && options !== '{}') {
    try {
      const optionsObj = JSON.parse(options);
      if (optionsObj.config && optionsObj.config.model) {
        model = optionsObj.config.model;
      }
    } catch (e) {}
  }

  console.log(runClaude(['-p', prompt, '--model', model]));
}
