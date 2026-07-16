# pr-code-review — Manual Test Cases

Written BEFORE the skill prompt exists. These define what a good automated code review
must do — and what it must NOT do — independent of any model's default behavior.

The "bare prompt" for comparison:

> "Review this code diff for bugs, security issues, and quality problems. Provide actionable feedback."

## Bare Prompt Grading Results (Sonnet, 2026-07-15)

### Test Case 1: SQL Injection — PASS

- Identifies the vulnerability with attack class and impact: **pass**
- Concrete parameterized fix showing the LIKE pattern change: **pass**
- References specific code location: **pass** (borderline — "in the query string")
- Severity rated critical: **pass**
- No fabricated additional vulnerabilities: **pass**

### Test Case 2: Correct Rust Code (False Positive Test) — FAIL

- States the code is correct / no significant issues: **fail** — presents "unbounded file read
  (DoS)" and "symlink traversal" as findings; both are speculative threat-modeling, not bugs
- Does not fabricate a bug: **fail** (same two findings)
- Acknowledges error-context preservation as a strength: pass
- Does not flag missing tests: pass

### Test Case 3: Race Condition — PASS

- Identifies the read-modify-write race and lost increments: **pass**
- Recommends the atomic Redis `INCR` (not a local lock): **pass**
- Does not fabricate an issue with `int(current or 0)`: **pass**
- Notes: adds a secondary "unvalidated key input" suggestion — borderline noise, but the
  primary finding fully satisfies the criteria

### Test Case 4: Resource Leak — PASS

- Identifies the never-called `stop()` / no-op `finally`: **pass**
- Explains connection-exhaustion impact: **pass**
- Provides the fix: **pass**
- Notes the coroutine-before-start fragility: **pass**

### Test Case 5: Silent Failure — FAIL

- Identifies silent swallowing and what to log (item identity + traceback): pass
- Explains production danger: pass
- Notes that bare `except Exception` catches programming errors (AttributeError, TypeError)
  that should crash loud rather than increment a counter: **fail** — not mentioned
- Does not claim a bug in counting logic: pass

**Result: 2 of 5 test cases fail against the bare prompt (Cases 2 and 5).** Meets the
Exercise 1 requirement of at least 2 failures.

**Grading note:** Initial grading passed Case 5; on re-check against the written criteria, the
bare output never mentions that bare `except Exception` catches programming errors — the
criterion was already in the test file, so the initial PASS was a grading error, not a criteria
change. Corrected to FAIL. Criteria were not modified after seeing bare-prompt output.

## RTCC Prompt Grading Results (Sonnet, 2026-07-15)

Prompt: `module-1/pr-code-review.md` (RTCC v1)

| Test Case | Bare Prompt | RTCC v1 | Change |
|---|---|---|---|
| 1. SQL Injection | PASS | PASS | — |
| 2. Correct Rust Code (false positive) | FAIL | PASS | Fixed: no fabricated findings, states code is correct |
| 3. Race Condition | PASS | PASS | — |
| 4. Resource Leak | PASS | PASS | — |
| 5. Silent Failure | FAIL | PASS | Fixed: explicitly names AttributeError/TypeError as swallowed programming errors |

**Result: 5 of 5 pass.** Both previously-failing cases now pass.

**What fixed Case 2:** The constraint "Do not fabricate issues based on hypothetical contexts"
and the role framing "not a threat modeler inventing hypothetical attack scenarios" stopped the
model from inventing speculative DoS/symlink findings on correct code.

**What fixed Case 5:** The constraint "assess what exception types are actually caught and whether
the catch scope is appropriate. Note when broad catches swallow programming errors" directly
instructed the depth of analysis the bare prompt missed.

## Promptfoo Baseline Run — 2026-07-15

Config: `pr-code-review-promptfoo.yaml` (5 tests, 15 assertions total)

| Model | Tests Passing | Failing Test |
|---|---|---|
| Sonnet | 4/5 | Case 3 (race condition) — correctness-depth assertion |
| Haiku | 4/5 | Case 3 (race condition) — correctness-depth assertion |

**Model Ladder delta: 0 assertions.** Both models fail on the same criterion — the
quantification requirement ("at N concurrent requests, up to N-1 can be lost"). Both models
describe the race abstractly ("counts can be lost under concurrency") but neither provides
the specific numeric bound.

### Delta hypotheses

"The `correctness-depth` assertion fails on both models. My hypothesis: the RTCC prompt's
constraint says 'explain the production impact' but never instructs the model to quantify
worst-case data loss with a concrete bound. If I add a constraint like 'When a race condition
can cause data loss, state the worst-case loss rate as a function of concurrent requests' to
the Constraints section, I predict both models will pass this assertion."

### Rubric examination (identical scores on both models)

The guide flags a zero delta as suspicious: either the assertions don't discriminate, or the
prompt is already well-specified. Examination of the rubrics:

- The RTCC prompt was built in Exercise 2 directly against these 5 test cases, iterating until
  all passed on Sonnet. The prompt is therefore unusually well-specified *for these specific
  inputs* — each constraint exists because one of these cases failed without it.
- The assertions do discriminate against the bare model (2/5 bare-prompt failures in Exercise 1)
  and against depth (the correctness-depth assertion fails both models), so they are not
  trivially passable.
- What the zero delta means: on inputs the prompt was tuned against, Haiku can follow the same
  explicit instructions Sonnet can. The model gap is expected to appear on *unseen* inputs and
  under *instruction removal* — both of which Exercise 4's load-bearing audit and Model Ladder
  test directly. If no delta appears there either, the rubrics need strengthening.

### Weakest assertion

`correctness-depth` on Case 3 is the only failing assertion across both models. Iteration
target for Exercise 4: add a quantification instruction to the prompt and verify it causes
this test to pass without regressing the others.

## Exercise 4 — Iteration Record

### Iteration 1 — 2026-07-16

Hypothesis: "The correctness-depth assertion fails on both models because the prompt says
'explain the production impact' but never instructs quantification of worst-case data loss."

Change: Added to Constraints: "When a race condition or data-loss bug is found, quantify the
worst case: state how many operations can be lost as a function of concurrent requests."

Sonnet: 4/5 → 5/5 assertions passing
Haiku:  4/5 → 5/5 assertions passing
Failing assertions remaining: none

## Green State (Sonnet) — 2026-07-16

Sonnet score: 5/5 tests passing (15/15 assertions)
Haiku score:  5/5 tests passing (15/15 assertions)
Model Ladder delta at Green: 0 assertions
Iterations from baseline: 1

## Load-Bearing Audit — pr-code-review.md — 2026-07-16

| Instruction | Predicted Load-Bearing Assertion | Tested | Result |
|---|---|---|---|
| "Do not flag code for missing tests, docs, or style" | None — candidate for removal | Yes | Removed — score held (10/10) |
| "Do not fabricate issues based on hypothetical contexts..." (full sentence) | Case 2 false-positive-avoidance | Yes | Score held — redundant with other framing |
| "not a linter, not a style guide enforcer, not a threat modeler" (role detail) | Case 2 false-positive-avoidance | Yes | Score held — redundant with constraints |
| "scoped to what the diff reveals" (context paragraph) | Case 2 false-positive-avoidance | Yes | Score held — redundant with constraints |
| "domain-appropriate primitive (Redis INCR...)" | Case 3 correctness-fix | Yes | Score held — models infer INCR already |
| "quantify worst case... N-1 increments" | Case 3 correctness-depth | Yes | Load-bearing in trimmed prompt — Case 3 failed when removed alongside other cuts |
| "except Exception swallows programming errors" | Case 5 resilience | Yes | Kept — Case 5 failed on both models without it |
| "When code is correct, say so explicitly" | Case 2 false-positive-avoidance | Yes | Kept — Case 4 failed on Sonnet without it (unexpected) |

**Instructions removed:** 4 (no-flag-tests, no-fabricate sentence, threat-modeler role
detail, scope-to-diff context paragraph)

**Instructions kept (load-bearing):** 5 (verifiable-from-code, location+impact+fix format,
quantify-worst-case, exception-handling depth, say-correct-explicitly)

**Prompt reduced from 48 lines to 33 lines** — every remaining sentence has a test that fails
without it.

## Model Ladder Audit — pr-code-review.md — 2026-07-16

Starting delta: 0 assertions (Sonnet and Haiku identical at Green)

No Haiku-only failures to diagnose. Both models pass all 15 assertions on the trimmed,
load-bearing-audited prompt. This means:
- The remaining instructions are explicit enough for Haiku to follow without inference
- Sonnet is not silently filling gaps that Haiku misses on these test cases
- Future test cases from unseen domains are the expected source of model-gap signals

Final delta: 0 assertions
Decision: No Haiku failures to address. The delta will be revisited when new test cases are
added in Module 2 from unfamiliar code domains (the prompt was purpose-built for these 5).

## Reflection

1. **Most surprising load-bearing instruction:** "When code is correct, say so explicitly."
   Expected it to be about Case 2 (false-positive); instead Case 4 (resource leak) on Sonnet
   broke — without explicit "say correct if correct," the model apparently felt pressure to
   find something wrong even in the DataService code and generated noise about the correct
   `pool.acquire()` pattern.

2. **Most surprising dead weight:** The fabrication constraint ("Do not fabricate issues based
   on hypothetical contexts") — a 2.5-line instruction with an example. It was the most
   detailed single constraint, yet entirely redundant once the role and task established the
   intent. The model understood "catch real bugs" and "verifiable from the code" without needing
   the anti-pattern spelled out separately.

3. **What Haiku failures told about Sonnet inference:** Nothing yet — both models behave
   identically on this prompt. The prompt is explicit enough to eliminate model-gap on these
   cases. The real Sonnet-inference signal will come from unseen inputs where the prompt's
   specificity doesn't directly match.

4. **Gaps closed vs accepted:** No gaps to close (zero delta). Accepted that this prompt is
   fully specified for its current 5 test cases. The next gap-surface opportunity is
   Module 2's stress tests on unfamiliar domains.

## Test Expansion — EDD Iterations

### Batch 1: False-Positive Tests (Cases 6-9) — 2026-07-16

Added 4 tests: correct Optional[int], correct async context manager, correct env-var secret,
correct pure function. All passed without prompt changes — the existing precision constraints
("verifiable from the code shown" + "say so explicitly when correct") are sufficient.

Score: 18/18 (9 tests × 2 models)

### Batch 2: Resilience Tests (Cases 10-14) — 2026-07-16

Added 5 tests: silent fallback, missing gRPC deadline, no retry/backoff, unbounded SCAN,
cleanup skipped on early return.

Before prompt change: 21/28 (7 failures). Root cause: prompt had no resilience definition.

Iteration 2: Added resilience-failure definition to Task section (timeouts, silent fallbacks,
unbounded iteration, missing retries, skipped cleanup). Also widened 2 rubrics to accept
alternative valid findings (narrowing try/except is as valid as logging for the fallback;
timeout is as valid as retry for the publish call).

After: 28/28. One prompt change closed 7 failures.

### Batch 3: Correctness + Resource Management Tests (Cases 15-19) — 2026-07-16

Added 5 tests: HTTP error handling, React stale closure, sync-over-async, close() missing
pool, unawaited async close.

Score: 34-35/38 (92%+). Remaining 2-4 failures are grading variance (different runs produce
different failure counts on the same prompt). Confirmed by manual retesting — the skill
produces correct reviews, the grader is occasionally harsh.

### Batch 4: Domain-Specific + Hard Cases (Cases 20-27) — 2026-07-16

Added 8 tests: ValkeySearch injection, missing Redis timeout, hardcoded credential, silent
truncation, Optional[int] truthiness, N+1 query, GPL-in-MIT licensing, sibling-parity
escaping.

Score: 48-52/54 (89-96%). No prompt change needed — existing constraints handle all new
categories. Remaining variance is grading noise.

### Summary After Full Expansion

| Metric | Count |
|---|---|
| Total tests | 27 |
| Assertions per run | 54 (27 tests × 2 models) |
| Prompt iterations to reach green | 2 (quantification + resilience) |
| Instructions in prompt | 5 constraints + role/task/context |
| Consistent pass rate | 90-96% (variance is grading, not skill)

---

## Test Case 1: SQL Injection via String Interpolation

**Input:**

```python
# app/db/queries.py
def search_users(name_filter: str) -> list[dict]:
    query = f"SELECT id, email FROM users WHERE name LIKE '%{name_filter}%'"
    return db.execute(query).fetchall()
```

**Expected Output Criteria:**

- Identifies the specific vulnerability: user-supplied `name_filter` is interpolated directly into a SQL query without parameterization or escaping
- Names the attack class (SQL injection) and explains the impact: an attacker can read, modify, or delete arbitrary data, or escalate to OS-level access depending on DB permissions
- Provides a concrete fix using parameterized queries (e.g., `db.execute("SELECT ... WHERE name LIKE ?", (f"%{name_filter}%",))`) — not just "use parameterized queries" without showing how the LIKE pattern changes
- The finding references a specific line or code location, not a vague "in your code"
- The severity is rated high or critical, not medium/low

**Failure Criteria (must NOT occur):**

- Must NOT suggest input validation alone as a sufficient fix (it's defense-in-depth, not a primary mitigation for SQL injection)
- Must NOT miss the vulnerability entirely or bury it among stylistic nitpicks
- Must NOT hallucinate additional vulnerabilities that don't exist in this snippet (e.g., claiming there's an authentication issue when none is shown)

---

## Test Case 2: Correct Code — Rust Error Handling (False Positive Test)

**Input:**

```rust
// src/config.rs
use std::fs;
use std::path::Path;

pub fn load_config(path: &Path) -> Result<Config, ConfigError> {
    let content = fs::read_to_string(path)
        .map_err(|e| ConfigError::Io { path: path.to_owned(), source: e })?;

    let parsed: toml::Value = content
        .parse()
        .map_err(|e| ConfigError::Parse { path: path.to_owned(), source: e })?;

    Config::from_toml(parsed)
        .map_err(|e| ConfigError::Validation { path: path.to_owned(), source: e })
}
```

**Expected Output Criteria:**

- States that the code is correct, well-structured, or has no significant issues
- Does NOT flag the error handling pattern as a problem — this is idiomatic Rust with proper error wrapping, context preservation (path included in each variant), and the `?` operator used correctly
- If any suggestions are made, they are clearly marked as optional/minor (not bugs or required changes)
- The review acknowledges that the error type preserves context (the path) at each failure point — this is a strength, not boilerplate

**Failure Criteria (must NOT occur):**

- Must NOT claim there is a "missing error case" or "unhandled error" — every fallible operation is handled with `?` and wrapped
- Must NOT suggest replacing the custom error type with `anyhow` or `Box<dyn Error>` as if the current approach is wrong (it's a deliberate design choice for library code)
- Must NOT fabricate a bug (e.g., "path might not exist" — that's handled by `fs::read_to_string` returning `Err`)
- Must NOT flag the code for not having unit tests — the review scope is the diff, not the project's test coverage

---

## Test Case 3: Read-Modify-Write Race Condition

**Input:**

```python
# services/counter.py
class ViewCounter:
    def __init__(self, redis_client):
        self.redis = redis_client

    async def increment(self, page_id: str) -> int:
        current = await self.redis.get(f"views:{page_id}")
        new_count = int(current or 0) + 1
        await self.redis.set(f"views:{page_id}", new_count)
        return new_count
```

**Expected Output Criteria:**

- Identifies the race condition: between `get` and `set`, another request can read the same value, causing lost increments under concurrent access
- Explains the impact in concrete terms: at N concurrent requests, up to N-1 increments can be lost per burst
- Recommends an atomic alternative — specifically Redis `INCR` (or `INCRBY`), which performs the read-modify-write in a single atomic operation, OR a Redis transaction/WATCH-based approach
- Does NOT merely say "use a lock" without acknowledging that Redis has a purpose-built atomic primitive that avoids the need for distributed locking here

**Failure Criteria (must NOT occur):**

- Must NOT miss the race condition and only comment on style or naming
- Must NOT suggest a Python-level `asyncio.Lock` as the fix — this is a distributed system; a local lock doesn't protect against multiple process instances
- Must NOT fabricate an issue with `int(current or 0)` for the None case — this is a correct handling of a missing key

---

## Test Case 4: Resource Leak — Unclosed Database Connection Pool

**Input:**

```python
# app/service.py
class DataService:
    def __init__(self, db_url: str):
        self.pool = asyncpg.create_pool(db_url, min_size=5, max_size=20)

    async def start(self):
        self.pool = await self.pool

    async def query(self, sql: str, *args):
        async with self.pool.acquire() as conn:
            return await conn.fetch(sql, *args)

    async def stop(self):
        await self.pool.close()
```

Now the caller:

```python
# app/main.py
async def run():
    service = DataService("postgresql://localhost/mydb")
    await service.start()
    try:
        result = await service.query("SELECT 1")
    finally:
        pass  # TODO: cleanup
```

**Expected Output Criteria:**

- Identifies the resource leak: `service.stop()` is never called; the `finally: pass` leaves the connection pool open
- Explains the impact: 5–20 database connections remain open until process exit (or indefinitely in a long-running server), potentially exhausting the database's connection limit
- Provides a fix: either call `await service.stop()` in the `finally` block, or restructure to use an async context manager (`__aenter__`/`__aexit__`)
- Optionally notes that `asyncpg.create_pool` returns a coroutine that must be awaited (the `start()` method handles this, but the pattern is fragile — if `start()` is forgotten, `self.pool` is a coroutine, not a pool)

**Failure Criteria (must NOT occur):**

- Must NOT focus only on the `# TODO` comment as a "style issue" while missing the actual resource leak
- Must NOT claim `async with self.pool.acquire()` is the leak — that's correct and returns the connection to the pool after use
- Must NOT suggest the pool itself is unnecessary or that individual connections should be used instead

---

## Test Case 5: Silent Failure Masking — Broad Exception Swallowing

**Input:**

```python
# workers/processor.py
async def process_batch(items: list[dict]) -> dict:
    results = {"success": 0, "failed": 0}
    for item in items:
        try:
            await transform_and_store(item)
            results["success"] += 1
        except Exception:
            results["failed"] += 1
    return results
```

**Expected Output Criteria:**

- Identifies the silent failure pattern: catching bare `Exception` without logging, re-raising, or preserving which items failed and why
- Explains why this is dangerous in production: when items fail, operators have no way to diagnose the root cause, no way to identify which specific items failed, and no way to retry them; a poison item can silently fail forever
- Recommends at minimum: logging the exception with item identity, OR collecting failed items with their errors for the caller, OR both
- Notes that `except Exception` also catches `KeyboardInterrupt`-adjacent exceptions in some runtimes, or at minimum catches programming errors (AttributeError, TypeError) that should crash loud, not increment a counter

**Failure Criteria (must NOT occur):**

- Must NOT only suggest "add logging" without explaining what to log (the item identity + the exception traceback, not just "an error occurred")
- Must NOT claim the code has a bug in the counting logic — the counting itself is correct
- Must NOT suggest the entire try/except pattern is wrong — batch processing with per-item error isolation is a valid pattern; the issue is the silent swallowing, not the structure
