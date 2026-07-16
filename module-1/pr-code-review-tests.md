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
