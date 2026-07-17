# Shared: code review checklist

> The language-agnostic review rulebook. Single source of truth for *what* to check in a code review.
> Consumed by `pr-code-review` (which adds posting, re-review, and the eval/retro loop on top) and by
> the Valkey `valkey-integration-subagent-self-reviewer` (which adds Valkey-specific checks and writes
> a verdict artifact instead of posting). Not a standalone skill.
>
> Both reviewers apply **every** check here, so their criteria stay identical. Each consumer keeps
> only its own *workflow* (how it gathers the diff, whether it posts, its output format) and any
> domain-specific checks on top. When a review rule is added or sharpened, edit it HERE.
>
> The deep **security** pass is the `security-review` skill, run by a `security-reviewer` sub-agent;
> both consumers delegate to it. The Security section below is the lightweight baseline both keep
> when that sub-agent is unavailable. Finding output format and the high-level lenses live in
> [`review-findings-schema.md`](review-findings-schema.md).

## Pre-check: Library API contracts
For any new external dependency introduced:
- Read the library's type definitions (or equivalent) for methods used — especially constructors, `close`/`dispose`, and any method whose return value drives control flow.
- Verify the code handles the actual return types (not assumed from naming).
- Check whether cleanup methods (`close`, `destroy`, `dispose`, `shutdown`) return a Promise/Future — if so, they must be awaited.
- Use web search if types are ambiguous or the library is unfamiliar.

Review each changed file against the categories below. Weight by user-specified focus areas if given; otherwise review all equally.

## Design & Architecture (review first — highest leverage)
- **Overall design**: Does this change belong in this codebase, or should it be a library/separate service? Does it integrate well with the rest of the system?
- **Complexity**: Can it be understood quickly? Are functions/classes doing too much? Over-engineering — more generic than needed, or functionality not needed yet?
- **Code health**: Is this improving overall code health, or adding complexity/less tested code?
- **Scalability**: Will it handle increased load? Bottlenecks? Modular enough to scale?
- **Configurability**: Hardcoded values different deployments would tune (algorithm/strategy choices, capacity params like batch/pool/retry counts, infra choices like ports/paths/protocol versions) should be config with sensible defaults, logged at startup.
  - **Silent truncation limits**: a hard cap on results/iterations/batch size (e.g. `LIMIT 0, 10000`) must be impossible-by-design, logged, or documented. Silent truncation that **drops caller data without any error or warning** is a correctness bug disguised as a perf safeguard — flag it as a data-loss risk, not merely a configurability suggestion. Extract to a named constant at minimum; make it configurable if users might need different values.

## Correctness & Functionality
- Logic errors, off-by-one, race conditions, deadlocks.
- Incorrect API/SDK usage (check official docs via web search if unsure).
- Edge cases: null/nil/None, empty collections, boundary values, unicode, large inputs.
- Does the code actually implement what the PR description and ticket say?
- **Completeness of known-value sets**: a static set (escape chars, enum mappings, allowed values) must be verified against the authoritative spec. Partial sets are silent correctness bugs.
- Error handling: are exceptions caught, wrapped, re-raised properly? Errors swallowed silently?
- **Batch/bulk error propagation**: when a method processes N items, partial failures must propagate to the caller, not just be logged — especially in upsert patterns where old data was already deleted. Watch for `try/except` inside a loop that only logs. Fix: collect failures, raise after the batch.
- Concurrency: thread safety, async correctness, locks/mutexes. Reason through parallel issues — they don't show up by running code.
- **Sync-over-async wrappers**: when async is wrapped in a sync interface (`loop.run_until_complete()`), verify behavior when called from within a running loop. The wrapper must detect the running loop and offload to a thread, else `RuntimeError`. Check for a `try: asyncio.get_running_loop()` guard.
- **Operator completeness across CRUD methods**: when a filter system supports operators (EQUAL, IN, NOT_EQUAL, NOT_IN, GT, LT), verify ALL are handled in ALL code paths (select, delete, update). Common bug: select handles NOT_EQUAL but delete silently ignores it.

## Resource Management
- Connections, file handles, clients, thread pools closed/released on all paths (including error paths)?
- Language-specific: Python context managers (`async with`), Java try-with-resources, C# `using`/`IAsyncDisposable`, Go `defer`, Rust RAII/Drop.
- Resources leaked if an exception is thrown mid-operation?
- Expensive resources (thread pools, event loops, TCP connections) reused, not recreated per call?
- In `close()`/`dispose()`, verify ALL resource fields are cleaned up, not just the primary one (e.g. a class with both `_sync_client` and `_async_client`). Trace every field assigned in `__init__` that holds an external resource.
- **Async cleanup**: if `close()`/`dispose()` calls an external client's cleanup that returns a Promise, it must be awaited, else half-open connections or premature exit.

## Language-Specific Best Practices
- **Python**: type annotations, async/await, context managers, dataclasses vs dicts, f-strings, pathlib; **truthiness vs identity for Optional numerics** (`if x:` is wrong for `Optional[int]` where 0 is a valid, meaningful value — it silently ignores a 0 argument and must use `if x is not None:` instead).
- **TypeScript/JS**: null checks, async error handling, type narrowing, avoiding `any`. For untyped library data (`Record<string, any>`), consider a local narrowed interface.
- **Go**: error wrapping, defer patterns, goroutine leaks, interface compliance.
- **Rust**: ownership, Result/Option error handling, unsafe justification.
- **Java**: null safety, try-with-resources, generics, stream API.
- **C#**: nullable reference types, IDisposable/IAsyncDisposable, LINQ, async patterns.
- General: naming clarity, DRY, appropriate abstraction level.

## API Consistency
- Matches patterns established by similar modules in the project?
- Constructor/factory signatures consistent across related classes?
- Public methods consistent with sibling implementations?
- Feature parity vs the equivalent existing implementation?
- Error types consistent with the rest of the project?
- **Same-pattern sibling sweep**: when a guard, fix, or idiom is applied to one method (iteration cap, tag/value escaping, name validation, `return_exceptions=True`, narrowed `except`, timeout), verify **every** sibling method that shares the pattern got the same treatment. Reviews (and fix commits) routinely patch one instance and leave an identical sibling untouched — after flagging or confirming a fix in method A, grep the file for the same call/loop/pattern and check B, C, D. This is one of the most common misses: the just-fixed method looks right while its twin two functions down still has the original bug.

## Performance
- Unnecessary network round-trips (batching opportunities); N+1 query patterns.
- Unnecessary allocations/copies; missing pagination for large result sets.
- Algorithmic complexity — more efficient data structures/algorithms?
- Connection pooling / reuse.
- Avoid premature optimization — flag only measurable impact or clear algorithmic concerns.

## Resilience & Operational Safety
- All external client configs (DB, cache, HTTP, gRPC) have explicit timeouts/deadlines? Missing timeouts cause cascading hangs.
- Do fallback/degradation paths log clearly enough for operators? A silent fallback from distributed to local storage is a correctness bug operationally.
- **Transient-failure handling on external calls**: any single network/IO operation to an external system (publish/enqueue, HTTP/RPC send, cache/DB write) that can fail transiently should have bounded retries with backoff, and a circuit breaker where load or dependency fragility warrants it. A one-shot call that propagates the first transient error with no retry is a resilience gap — flag it. Don't over-prescribe: a small bounded retry with backoff is usually enough; a full circuit breaker is only needed for hot paths or flaky dependencies. Distinguish retryable errors (timeouts, connection resets, 5xx) from non-retryable ones (validation, auth, 4xx) — never blindly retry the latter.
- In graceful shutdown (`close()`/`dispose()`/`__aexit__`), ALL held resources released — including lazily-created or alternate-path ones?
- Health/readiness probes aware of degraded states (e.g. running on fallback storage)?
- **Unbounded iteration over external data**: cursor iteration (SCAN, pagination, list-all) over unbounded data needs a safety limit (max iterations/items). Also: does it collect ALL results before applying limit/offset? It should terminate collection early once enough are gathered. Apply this to **every** method that iterates external data, not just the first one you notice — if one method caps its loop (e.g. `delete` uses `for _ in range(_MAX_ITER)`) but a sibling doing the same scan/list/paginate does not (e.g. `list_documents` still uses `while True:`), that unguarded sibling is the bug.
- **Partial-failure cleanup / idempotent recovery**: if a multi-step op fails halfway (index dropped, key cleanup fails → next call sees "index not found" and returns early, orphaning keys forever), cleanup steps must run unconditionally, not gated on prior success.
- **Cloud deployment readiness**: for cloud-targeted handlers/connectors, verify these are configurable (not just locally supported): TLS/SSL (ElastiCache, MemoryDB, Azure Cache, GCP Memorystore), token/cert auth (not just password), connection pooling, and request timeouts with production-suitable defaults.

## Security
> The full security pass is the **`security-review` skill** — both consumers delegate to a
> `security-reviewer` sub-agent that applies it. This section is the lightweight baseline to apply
> directly only when no sub-agent is available.
- Input validation and sanitization.
- Proper escaping for query construction (SQL / command / query injection); for search-engine DSLs (FT.SEARCH, Elasticsearch, Lucene), verify the escape set is complete per the engine's spec and each field type uses its correct escape function. For RediSearch/ValkeySearch specifically: TAG fields require escaping `,`, `.`, `<`, `>`, `{`, `}`, `[`, `]`, `"`, `'`, `:`, `;`, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `(`, `)`, `-`, `+`, `=`, `~`, `|`, `\`, `/` — interpolating user input without this full set allows query injection. TEXT phrase fields use a different escape function from TAG fields.
- Secret handling (no hardcoded credentials, proper env var usage, no secrets in logs).
- Authentication/authorization checks; never expose a network service without auth.
- Dependency security (known vulnerabilities in new deps).
- Data encryption in transit (TLS) and at rest where required.

For the complete checklist (escape contexts, token-separator behavior, deserialization, path traversal, weak crypto, severity rubric, and output format), use the `security-review` skill.

## Test Quality & Coverage
- Every public method covered by at least one test?
- Edge cases tested (empty, null, error conditions, boundaries)?
- Error paths tested (exception wrapping, connection failures, timeouts)?
- **Test quality** (not just coverage): do tests actually fail when the code breaks? Any false positives? Simple, useful assertions?
- **Sufficiency over completeness**: these test-quality checks exist to catch tests that assert *nothing* or the *wrong* thing — not to require exhaustive coverage. When the tests shown already assert observable behavior for the cases they target, treat them as adequate. Do NOT flag them for missing edge cases, parametrization, or extra scenarios unless a specific untested path is both visible in the code and materially risky. "Could add more tests" is not a finding.
- Tests independent of each other and external systems (proper mocking/isolation)?
- Test structure consistent with the project's patterns? Integration tests marked appropriately?
- Compare coverage with equivalent existing implementations. Tests are code too — no unnecessary complexity.

## Documentation & Comments
- Public classes/methods documented (docstrings/JSDoc/godoc)?
- Comments explain **why**, not **what** — if a comment explains what code does, simplify the code instead.
- Existing comments still accurate after the change? Resolvable TODOs?
- README accurate and complete? Code examples correct/runnable? Breaking changes documented?
- When fallback/degradation triggers, does the log communicate the **consequence** (not just the cause)? "Falling back to in-memory cache — NOT shared across nodes" beats "ImportError: valkey-glide".

## Dependencies, Build & Licensing
- New dependencies justified and version-pinned? Versions compatible with the project's requirements? Lighter alternatives?
- **License compatibility**: new dependency licenses compatible with the project's license (e.g. no GPL dep in an MIT project)?
- Build configuration updated correctly (workspace members, test configs)? CI/CD configs updated if needed?
