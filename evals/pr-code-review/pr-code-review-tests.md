# pr-code-review — Manual Test Cases

Written BEFORE the skill prompt exists. These define what a good automated code review
must do — and what it must NOT do — independent of any model's default behavior.

> **The iteration log** (baseline scores → hypothesis → change → measured result → reasoning,
> per iteration, plus the load-bearing audit and Model Ladder record) lives in
> [`ITERATION-LOG.md`](ITERATION-LOG.md). This file holds the test case *definitions*:
> inputs, expected-output criteria, and failure criteria.

The five seed cases below are written in full prose (input + criteria). Cases 6–40 are
defined directly as `llm-rubric` assertions in [`promptfooconfig.yaml`](promptfooconfig.yaml);
the expansion rationale for cases 28–37 is documented at the end of this file.

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

---

## Full-Parity Expansion (Cases 28–37) — 2026-07-16

These 10 cases were added to exercise checklist categories the first 27 tests did not cover, so
the certification skill reaches full parity with the live skill's shared rulebook
(`_shared/review-checklist.md`). Written and committed **before** the skill was wired to
reference that shared checklist — the red phase of this expansion. (Green-phase scores and the
precision-carve-out iteration they forced are in [`ITERATION-LOG.md`](ITERATION-LOG.md).)

| # | Category tested | Kind | Checklist section it exercises |
|---|---|---|---|
| 28 | Reimplemented utility (slugify) | recall | Design & Architecture / codebase alignment |
| 29 | Inconsistent constructor signature | recall | API Consistency |
| 30 | Unawaited async `close()` | recall | Pre-check: Library API contracts + Resource Management |
| 31 | Test asserts nothing | recall | Test Quality & Coverage |
| 32 | Correct test with real assertions | false-positive | Test Quality (precision guard) |
| 33 | Fallback log omits consequence | recall | Documentation & Comments / operability |
| 34 | Unpinned + heavyweight dependency | recall | Dependencies, Build & Licensing |
| 35 | N+1 query in a loop | recall | Performance (measurable impact) |
| 36 | Over-engineered plugin framework | recall | Design & Architecture / complexity (YAGNI) |
| 37 | Missing docstring on trivial code | false-positive | Documentation (scope/precision guard) |

**Why these were failing before the expansion:** the Module-1 skill body (`pr-code-review.md`)
inlined only six review dimensions (security, correctness, resource-management, resilience,
performance, licensing). It had no design-fit, API-consistency, library-API-contract,
test-quality, or documentation guidance — so cases 28–33 had no instruction to satisfy them,
and the two new false-positive guards (32, 37) had no scope rule to lean on. These are the gaps
the shared-checklist reference closes in the skill-expansion commit that follows.

Two of the ten (32, 37) are deliberately negative: bringing in a large recall-oriented checklist
risks new false positives (demanding more tests, flagging trivial missing docstrings), so the
expansion must close the recall gaps WITHOUT regressing precision. These guard that.
