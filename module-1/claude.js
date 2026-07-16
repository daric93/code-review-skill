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

  const result = spawnSync('claude', ['-p', userMsg, '--system-prompt', systemMsg, '--model', 'sonnet'], {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (result.error) { console.error(result.error.message); process.exit(1); }
  if (result.status !== 0) { console.error(result.stdout || result.stderr); process.exit(result.status || 1); }
  console.log(result.stdout);
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

  const result = spawnSync('claude', ['-p', prompt, '--model', model], {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (result.error) { console.error(result.error.message); process.exit(1); }
  if (result.status !== 0) { console.error(result.stdout || result.stderr); process.exit(result.status || 1); }
  console.log(result.stdout);
}
