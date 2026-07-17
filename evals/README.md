# Skill Evals

Promptfoo-based evaluations for Kiro skills and agents.

## Structure

```
evals/
  README.md                     ← this file
  .gitignore                    ← excludes results.json and local promptfoo db
  kiro-chat.sh                  ← bare wrapper: routes a prompt straight to kiro-cli
  kiro-review.sh                ← REVIEW provider: injects the skill's checklist + precision
                                   gates so the eval grades the SKILL, not the bare model
  kiro-baseline.sh              ← BASELINE provider: bare model (same pin, no skill machinery),
                                   the A/B control arm for measuring the skill's value-add
  kiro-grade.sh                 ← GRADER provider: runs kiro-cli then extracts/sanitizes the
                                   JSON object so llm-rubric parsing never flakes
  pr-code-review/
    promptfooconfig.yaml          ← tests for pr-code-review skill (SKILL ON arm)
    promptfooconfig.baseline.yaml ← representative subset run against the bare model (SKILL OFF)
  contribution-explorer/
    promptfooconfig.yaml        ← tests for contribution-explorer skill (TODO)
  ci-failure-review/
    promptfooconfig.yaml        ← tests for ci-failure-review skill (TODO)
```

> **Grading the skill vs the bare model.** The `pr-code-review` skill is `inclusion: manual`,
> so kiro-cli does NOT auto-load it — a bare prompt would measure raw model behavior and ignore
> the checklist. The **review provider** (`kiro-review.sh`) fixes this: it injects the real
> `skills/_shared/review-checklist.md` (the rulebook — single source of truth, so checklist
> edits flow straight into the eval) plus a compact preamble mirroring the skill's Phase-3
> precision gates (verify-before-flag, nitpick filter, never-fabricate). It deliberately omits
> the skill's GitHub-posting / re-review / retrospective workflow, which is irrelevant to a code
> snippet. The **grader provider** (`kiro-grade.sh`) sanitizes kiro-cli's reply down to a clean
> JSON object so the llm-rubric "Could not extract JSON" flake can't recur. `kiro-chat.sh` is
> kept as the original bare wrapper for ad-hoc use.
>
> Consequence: to improve a review *rule*, edit `review-checklist.md` and re-run with
> `--no-cache` — the change now actually affects the generated review. The first run after
> switching to `kiro-review.sh` may shift some scores (richer context); watch the negative
> (`false-positive-avoidance`) tests in particular, since the recall-oriented checklist can push
> toward over-flagging — the precision preamble is there to counter that.

## Baseline comparison (evidence of value)

The eval ships **two arms** that differ only in whether the skill is present:

| Arm | Config | Provider |
|---|---|---|
| **Skill ON** | `promptfooconfig.yaml` | `kiro-review.sh` — injects the checklist + precision gates |
| **Skill OFF** | `promptfooconfig.baseline.yaml` | `kiro-baseline.sh` — bare model, same model pin |

Same tests, model, grader, rubric, and threshold — the only variable is the skill. Run both and
compare the per-metric scores; the delta is the skill's measured lift.

```bash
cd pr-code-review
promptfoo eval -c promptfooconfig.baseline.yaml --no-cache   # SKILL OFF
promptfoo eval -c promptfooconfig.yaml          --no-cache   # SKILL ON
promptfoo view                                               # compare per-metric scores
```

The baseline carries a representative subset (one test per metric) so a control run is cheap
while still covering every scoring dimension. This A/B is the "evidence of value" packaged in
[`../certification/pr-code-review/`](../certification/pr-code-review/).

## Philosophy

Three test categories, always keep all three present:

- **Positive tests** — verify the skill catches real bugs and anti-patterns (SQL injection, race conditions, resource leaks, etc.)
- **Negative tests** — verify the skill does NOT fabricate issues in correct code. These are equally important. A skill that cries wolf on every review is useless.
- **Regression tests** — added any time the skill makes a real mistake on a live run. These are the most valuable tests over time.

---

## Setup

```bash
# Install promptfoo (once)
npm install -g promptfoo

# Install kiro-cli (once) — provides the headless chat used by the evals
curl -fsSL https://cli.kiro.dev/install | bash
```

No separate API keys needed. The evals use your existing Kiro subscription by shelling out to
`kiro-cli` in headless mode (`--no-interactive`). Both the **provider** (what generates the
review) and the **llm-rubric grader** (what scores the review) run through `kiro-cli`.

### Why a wrapper script (`kiro-chat.sh`)?

promptfoo's `exec:` provider invokes the command with the prompt as the **first argument**,
then appends its own JSON metadata as **additional arguments**. `kiro-cli chat` rejects those
extra args (`error: unexpected argument '{...}'`). The wrapper at `~/.kiro/evals/kiro-chat.sh`
forwards only `$1` (the prompt) to `kiro-cli` and ignores the rest:

```bash
#!/usr/bin/env bash
exec kiro-cli chat --no-interactive --trust-tools=read,grep "$1"
```

Each `promptfooconfig.yaml` points both the provider and `defaultTest.options.provider`
(the grader) at this wrapper:

```yaml
providers:
  - id: "exec: ../kiro-chat.sh (in this repo) or ~/.kiro/evals/kiro-chat.sh (when installed)"
    label: "kiro-cli"

defaultTest:
  options:
    provider:
      id: "exec: ../kiro-chat.sh (in this repo) or ~/.kiro/evals/kiro-chat.sh (when installed)"
      label: "kiro-cli-grader"
```

> **Note:** Do NOT use the `anthropic:messages:...` provider with `apiKeyRequired: false`.
> That path expects a `claudeCodeOAuthToken` in the macOS keychain, but the Kiro/Claude Code
> keychain entry only contains `mcpOAuth` — so it fails with
> `Claude Code macOS keychain entry is malformed`. Route everything through `kiro-cli` instead.

### Auth

`kiro-cli` uses your logged-in Kiro session. The first headless call may open a browser to
authorize the device, after which it caches the credential. If it ever fails to authenticate,
run `kiro-cli` once interactively to re-login.

### PATH

`kiro-cli` installs to `~/.local/bin`. If that isn't on your `PATH`, prefix eval runs with
`PATH="$HOME/.local/bin:$PATH"` (the wrapper uses an absolute path, so this is mostly for
`promptfoo` itself to resolve any helper binaries).

---

## Running Evals

```bash
# Run a specific eval
cd ~/.kiro/evals/pr-code-review
promptfoo eval

cd ~/.kiro/evals/pr-code-review && PATH="$HOME/.local/bin:$PATH" promptfoo eval 2>&1

# Run and immediately open results in browser
promptfoo eval --view

# Force a fresh run (ignore cached provider + grader responses).
# promptfoo caches by prompt, so an unchanged config re-runs in ~1s using cached output.
# Use --no-cache after editing the SKILL (not the config) so the new behavior is actually
# regenerated and re-graded — otherwise you're scoring the old cached response.
promptfoo eval --no-cache

# Run a single test by description (cheap — for quick iteration while editing)
# NOTE: --filter-pattern matches the test's `description` field, not prompt content.
# The current tests have no descriptions, so add a `description:` to a test before
# filtering on it, e.g.  - description: "sync-over-async"
promptfoo eval --filter-pattern "SQL injection"
promptfoo eval --filter-pattern "sync-over-async"

# Open the web UI to browse all past runs and compare scores over time
promptfoo view
```

### When to run

| Trigger | Which eval | Why |
|---|---|---|
| After editing a skill file | The eval for that skill | Minimum bar — all tests must still pass |
| After a live run where the skill missed something | The eval for that skill | Add the missed case as a regression test first, then fix |
| After a live run where the skill fabricated a bug | The eval for that skill | Add a negative test first, then fix |
| Every few weeks (maintenance) | All evals | Catch score drift from model changes |
| After syncing skills from ai-dev-toolkit | All evals | Confirm no regressions were introduced |

---

## What to Check After a Run

Open `promptfoo view` or inspect `results.json`. Go through this checklist:

### 1. Pass rate
All tests should be **100% pass**. Any failure is a regression — investigate before moving on.

### 2. Scores on llm-rubric assertions
Each `llm-rubric` assertion returns a score from 0.0 to 1.0. Look at:
- **Score dropped vs previous run** on a test that still "passes" — the rubric threshold may be met but quality degraded. Investigate.
- **Score is consistently low (0.6–0.7)** on a test — either the rubric is poorly written or the skill is marginally meeting it. Both need fixing.
- **Score improved** — good signal that a skill edit worked.

#### Metric labels (how scores surface as columns in the UI)
Each assertion has a `metric:` label that groups it into a review category. promptfoo
aggregates these into **named scores** shown as columns/chips at the top of the results table.
Without a `metric:`, an assertion contributes only to the raw aggregate and per-cell pass/fail —
nothing shows in the named-score panels (this is why scores looked "missing" before).

Current metric groups for `pr-code-review`:

| Metric | What it covers |
|---|---|
| `security` | injection, escaping, secret handling |
| `correctness` | logic errors, race conditions, error handling, silent failures |
| `resource-management` | leaks, cleanup paths, closing all resources |
| `resilience` | timeouts, fallbacks, operational safety |
| `false-positive-avoidance` | the negative tests — must NOT fabricate issues in correct code |

The header shows a summed score per metric (e.g. `correctness: 4.8` out of 5 tests = 0.96 avg).
A metric trending below ~0.8 is the weakest category in the skill — focus skill edits there.

When you add a new test, give it a `metric:` so it joins an existing column (or creates a new
one). Keep the label identical to existing ones — `correctness`, not `Correctness` or
`correct` — or it'll split into a separate column.

### 3. Token usage
Promptfoo tracks token counts per test. Check:
- Did total tokens go up after a skill edit? A longer skill isn't always better.
- Is one test using disproportionately many tokens? The prompt may be triggering verbose behavior you don't need.

### 4. Consistency (flakiness check)
`llm-rubric` uses an LLM grader, which can be non-deterministic. If a test is borderline:
```bash
promptfoo eval --repeat 3
```
If the same test flips pass/fail across runs, the rubric assertion is too vague. Tighten it.

---

## How to Fix the Skill (`pr-code-review.md`)

When a test fails, the skill is not behaving as expected. Fix order:

**1. Understand the failure first.**
Read the failing test's prompt and rubric assertion. Then read the skill's actual output for that test (visible in `promptfoo view` or `results.json`). Ask: did the skill miss the issue entirely, mention it too vaguely, or actively get it wrong?

**2. Find the relevant section in the skill.**
The skill is organized by review category (Correctness, Security, Performance, etc.). Find the category that should have caught this issue.

**3. Make a targeted edit.**
- If the skill **missed the pattern entirely** → add an explicit bullet under the relevant category. Be specific — don't say "check for threading issues", say "check for read-modify-write sequences without locks when the class is used in multi-threaded contexts".
- If the skill **mentioned it too vaguely** → sharpen the instruction. Add a concrete example of what to look for and what to say.
- If the skill **fabricated a false positive** (negative test failed) → add a counter-instruction. Example: "Do NOT flag `if x is not None` as a bug when the parameter is `Optional[int]` — this is the correct pattern."

**4. Re-run the specific test.**
```bash
promptfoo eval --filter-pattern "the test description"
```
Confirm it passes before running the full suite.

**5. Run the full suite.**
Confirm no regressions. A fix in one section can sometimes suppress correct behavior in another.

**6. Sync the skill.**
If you edit `~/.kiro/skills/pr-code-review.md`, sync it back to the repo's `skills/` so the change is tracked in git:
```bash
cd ~/Projects/ai-dev-toolkit
cp ~/.kiro/skills/pr-code-review.md skills/pr-code-review/SKILL.md
```

---

## How to Fix the Eval Itself

Evals can also be wrong. Fix the eval, not the skill, when:

- **The rubric assertion is too vague** — "Identifies security issues" passes even if the skill only mentions it in passing. Be specific: "Identifies SQL injection risk and recommends parameterized queries."
- **The rubric assertion is too strict** — it requires exact phrasing and fails on equivalent wording. Rewrite it to describe intent, not words.
- **The test code snippet has its own bugs** — the "correct code" in a negative test accidentally contains a real issue. Fix the snippet.
- **The test is testing the wrong thing** — the prompt is ambiguous or doesn't isolate the behavior you want to verify. Rewrite the prompt to be more focused.
- **A negative test is failing because the skill's suggestion is reasonable** — re-examine whether the suggestion is actually a false positive, or whether your negative test snapshot was wrong to begin with.

When rewriting a rubric assertion:
```yaml
# Too vague — passes even with a shallow mention
assert:
  - type: llm-rubric
    value: "Mentions thread safety."

# Better — tests for actionable, specific output
assert:
  - type: llm-rubric
    value: "Identifies the read-modify-write race condition on self.count and recommends a threading.Lock or atomic operation."
```

---

## How to Improve Over Time

### Add regression tests from live runs
This is the highest-leverage improvement loop:

1. Run a live code review with the skill on a real PR
2. If the skill misses a real bug → write a minimal test case reproducing it, add it to the eval
3. If the skill fabricates an issue on correct code → write a negative test for that pattern
4. Fix the skill, confirm the new test passes, confirm no regressions
5. Commit both the new test and the skill fix together

Each regression test makes the eval more valuable. After 10–15 real PRs, the eval suite will catch most failure modes automatically.

### Use retro files as test inspiration
Your `~/.kiro/retros/pr-comment-resolver-retro.md` logs every issue found by human reviewers. Each entry there is a candidate for a new positive test case — if a human reviewer had to catch it, the skill should catch it too.

```
retro file entry → extract the code pattern → write a minimal test prompt → add to eval
```

### The review-gap loop (strongest signal)
Ground truth for how good `pr-code-review` is = what OTHER reviewers caught that you didn't.
The `pr-code-review-gap-analyzer` skill automates this comparison:

```
your review → others' reviews on same PR → delta (misses + false positives)
  → ~/.kiro/retros/review-gaps-retro.md → proposed skill rules + eval tests → eval run
```

Run it after others have commented on a PR you reviewed:
```
#pr-code-review-gap-analyzer
Analyze review gaps on this PR: https://github.com/owner/repo/pull/123
```

Misses become positive eval tests; false positives become negative eval tests. The skill
appends a recall/precision score per PR so you can watch the skill improve over time.

### Track score trends in promptfoo view
Open `promptfoo view` every few weeks and look at:
- Are average scores trending up or flat?
- Which tests have the lowest scores? Those are the weakest spots in the skill.
- Did a model update (Claude version change) affect scores? Re-run evals after any model change.

### Add new test categories as the skill grows
When you add a new check to the skill (e.g., a new security pattern or a new language-specific rule), add a corresponding test immediately. Tests and skill sections should grow together.

### Periodically challenge the negative tests
Negative tests ("does not fabricate") can become stale — what was once correct code might now have known issues. Review them every few months and update the code snippets if needed.

---

## Costs

Full eval runs use `kiro-cli` for both the review generation and the `llm-rubric` grading,
all against your Kiro subscription (no separate API key cost). The `pr-code-review` eval has
~12 tests, each with one provider call plus one grader call, so roughly ~24 `kiro-cli` calls
per full run. These count against your Kiro subscription the same as regular Kiro usage —
each call reports its credit cost in the headless output.

To reduce usage during active iteration:
```bash
# Run only the tests relevant to the section you edited
promptfoo eval --filter-pattern "sync-over-async"
promptfoo eval --filter-pattern "bulk"
promptfoo eval --filter-pattern "Valkey"
```

Run the full suite only when you think the change is ready.

---

## Graded Scoring (1–5 scale, not just pass/fail)

The eval uses a custom `rubricPrompt` in `defaultTest` that converts every test's binary
criterion into a graded 1–5 score, normalized to 0–1:

| Rating | Normalized score | Meaning |
|--------|-----------------|---------|
| 5 Excellent | 1.00 | Precise finding + impact + correct fix, no noise |
| 4 Good | 0.75 | Satisfies criterion, fix slightly thin |
| 3 Adequate | 0.50 | Vague mention or weak fix, or minor fabrication |
| 2 Poor | 0.25 | Misses the actual issue or wrong fix |
| 1 Fail | 0.00 | Misses entirely (or fabricates, for negative tests) |

`threshold: 0.75` means a test only passes at **4/5 or better**. A barely-adequate review (3/5)
no longer passes silently — it shows as a degraded score AND fails the gate. This catches slow
quality decay that binary pass/fail misses.

Because each test has a `metric:` tag, `promptfoo view` aggregates scores per dimension
(security, correctness, resilience, false-positive-avoidance, etc.) — a per-dimension scorecard,
not a single number.

## Grading the Grader

An eval you don't audit drifts: rubrics get vague, the grader gets lenient, scores stop meaning
anything. The `grade-the-grader` skill audits the eval's grading quality periodically:

```
#grade-the-grader
Audit the pr-code-review eval grading from the last run.
```

Run it every 5–10 eval runs, after a grader model change, or whenever scores look suspicious
(everything at 1.0 = too lenient; run-to-run swings = vague criteria). It proposes sharper
criteria, rubricPrompt anchor tweaks, or threshold changes. **If the grader is broken, fix it
before trusting any score trend** — a trend from a broken grader is noise.

## Result Tracking

Promptfoo stores all run history automatically in `~/.promptfoo/output.db` (SQLite).
`promptfoo view` is the dashboard — it shows all past runs, score trends, and diffs.

Each eval folder also writes `results.json` — a snapshot of the last run.
Do NOT commit `results.json` to git (it's in `.gitignore`) — the DB is the source of truth.
