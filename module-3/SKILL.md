---
name: pr-code-review
description: Performs a thorough code review of any GitHub PR — local workspace or fully remote. Supports any language/framework. Posts inline comments as a pending review for user approval before submission.
inclusion: manual
---

# PR Code Review

You perform thorough, professional code reviews on GitHub pull requests. You work with any
language, any framework, any project — whether it's open in the current workspace or a fully
remote repo you've never seen before. You produce actionable inline comments posted as a
pending GitHub review that the user approves before submission.

> This is the full workflow skill. The Module 1 command form (snippet-in / findings-out,
> used by the eval) lives at `../module-1/pr-code-review.md`; it shares the same rulebook
> (`../_shared/review-checklist.md`) and precision discipline, minus the GitHub workflow.

## How to Use

When this skill runs, provide:

### Minimal (remote PR, no local project)
```
/pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
```

### With related issue/ticket
```
/pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
Ticket: https://github.com/owner/repo/issues/456
```

### With focus areas
```
/pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
Focus: correctness, API consistency, test coverage
Compare with the Redis implementation in the project.
```

### Re-review (verify previous comments were addressed, get an approve/not verdict)
```
/pr-code-review
Re-review: https://github.com/owner/repo/pull/123
```
Other phrasings that trigger this mode: "check comments", "did they address my feedback", "round 2".

## Input Parsing

Extract from the user's message:
- **PR URL** (required) — parse `owner`, `repo`, `pullNumber` from the URL
- **Issue/ticket URLs** (optional) — one or more GitHub issue URLs, Jira links, or other references
- **Focus areas** (optional) — specific review concerns (security, performance, test coverage, etc.)
- **Comparison targets** (optional) — existing implementations to compare against
- **Additional context URLs** (optional) — design docs, specs, related PRs

## Process

### Phase 1: Gather Context

#### 1a. Read the PR
- Use `pull_request_read` with method `get` — title, description, author, base/head branches
- Use `pull_request_read` with method `get_files` — list of changed files with stats
- Use `pull_request_read` with method `get_diff` — full diff

#### 1b. Read related issues/tickets (if provided)
- For GitHub issues: use `issue_read` with method `get` and `get_comments`
- For external tickets (Jira, Linear, etc.): use `web_fetch` if a URL is provided
- Extract: requirements, acceptance criteria, motivation, constraints

#### 1c. Determine project context

**If the PR repo matches the open workspace:**
- Use your provider's local file reading/search tools — faster and more complete
- Read project config files locally (pyproject.toml, package.json, Cargo.toml, pom.xml, .csproj, etc.)
- Read comparable implementations locally
- Read test files locally

**If the PR is for a remote repo (not open locally):**
- Use `get_file_contents` from GitHub MCP to read files from the repo
- Read the repo root to understand structure: `get_file_contents` with path `/`
- Read project config files: pyproject.toml, package.json, Cargo.toml, go.mod, pom.xml, build.gradle, .csproj, Makefile, etc.
- Read CONTRIBUTING.md if it exists

#### 1d. Detect language and ecosystem

Auto-detect from the changed files and project config:
- **Python**: pyproject.toml, setup.py, requirements.txt → ruff, mypy, pyright, pytest conventions
- **JavaScript/TypeScript**: package.json, tsconfig.json → eslint, prettier, jest/vitest conventions
- **Go**: go.mod → golint, go vet conventions
- **Rust**: Cargo.toml → clippy conventions
- **Java/Kotlin**: pom.xml, build.gradle → checkstyle, spotbugs conventions
- **C#/.NET**: .csproj, Directory.Build.props → editorconfig, analyzers
- **C/C++**: CMakeLists.txt, Makefile → clang-tidy, cppcheck conventions

Adapt review criteria to the detected language's idioms and best practices.

#### 1e. Read changed files in full context
- For each changed file, read the complete file (not just the diff) to understand surrounding context
- Use local tools if workspace matches, otherwise `get_file_contents` with the PR head ref

#### 1f. Read comparable implementations (if applicable)
- If the PR adds a new module/provider/package, find the existing equivalent in the project
- Compare patterns, API surface, error handling, test structure
- This is critical for consistency reviews

### Phase 2: Analyze the Code

#### Optional: fan out the lenses to sub-agents (deeper reviews)
For a large or high-risk change, and **where sub-agent delegation is supported**, you may run
the review as parallel fresh-context reviewers instead of one linear pass — one sub-agent per
lens, using the four canonical lenses defined in
[`../_shared/review-findings-schema.md`](../_shared/review-findings-schema.md): **codebase
alignment & design fit** (primary), **correctness & security**, **requirements alignment**, and
**testability**. The deep security half is delegated to the `security-reviewer` sub-agent (see
below). Each lens still applies the relevant categories from
[`../_shared/review-checklist.md`](../_shared/review-checklist.md). Each sub-agent returns
findings with `file:line` and a quoted code `evidence` snippet. Merge their findings, then
continue to Phase 3, where verification and the nitpick filter consolidate them.

Skip the fan-out and review all categories inline yourself when sub-agents are unavailable
(headless/eval runs, or a provider without sub-agents) or the change is small. The review
criteria are identical either way — fan-out only changes *who* applies them. Note in your
summary whether you fanned out or reviewed inline.

**Domain reviewers (optional, self-gating).** If the change uses a specialized library (e.g.
Valkey GLIDE) and a matching domain sub-agent is available, also delegate a focused pass to it.
It **self-gates** — for out-of-domain code it reports "not applicable" and adds nothing — so
this stays safe for general reviews and never makes this skill domain-specific.

#### Review criteria — the shared rulebook
Review each changed file against **every check in
[`../_shared/review-checklist.md`](../_shared/review-checklist.md)** — the shared,
language-agnostic review rulebook covering the library-API pre-check, Design & Architecture,
Correctness, Resource Management, Language-Specific Best Practices, API Consistency,
Performance, Resilience & Operational Safety, Security, Test Quality & Coverage, Documentation,
and Dependencies/Build/Licensing. Weight categories by user-specified focus areas if provided;
otherwise review all equally.

This is the **same rulebook the Module 1 command form uses** (and, in the live toolkit, the
Valkey self-reviewer), so the checks stay identical across reviewers. When a review rule is
added or sharpened, edit that shared file — not this skill.

#### Security

> **Delegate the security pass to the `security-reviewer` sub-agent (where supported).**
> Before working through the security checklist yourself, delegate to a `security-reviewer`
> sub-agent for a focused, fresh-context security review — its own dedicated set of eyes
> instead of one item among many.
>
> - **How:** invoke `security-reviewer` and tell it to **apply the `security-review` skill**,
>   in **Mode B (pr-code-review / ad-hoc)** so it returns findings inline and writes no files.
>   Give it the PR URL, title, ticket link, and any user-specified security focus. It has GitHub
>   MCP access, so for a remote PR it fetches the diff/files itself; for a local PR, pass the
>   changed-file paths so it reads them locally.
> - **What it returns:** findings grouped by severity (CRITICAL / WARNING / INFO) with
>   `file:line`, exploit, and a suggested fix — injection (SQL / command / query DSL / XSS /
>   path / deserialization), authn/authz, secrets/credentials, insecure data handling.
> - **Fold the results in:** merge into the numbered issue list in Phase 3 under **Security**,
>   keeping severity and `file:line`. De-duplicate against your own findings. You remain
>   responsible — sanity-check each finding against the actual code before posting; drop or
>   downgrade any that don't hold up.
> - **Fallback:** if sub-agents are unavailable, perform the Security section of the shared
>   checklist yourself and note that the dedicated pass was skipped.

Whether produced by the sub-agent or by you, the security baseline is the **Security** section
of [`../_shared/review-checklist.md`](../_shared/review-checklist.md). Fold any security
findings into the numbered issue list in Phase 3 under the **Security** category.

### Phase 3: Build the Numbered Issue List

Before numbering, run two precision gates over the raw findings from Phase 2 (whether produced
by an inline pass or by fan-out sub-agents).

#### 3a. Verify-then-include (precision gate)
For every candidate finding, confirm it against the actual code before it earns a number:
- Read the real file at the reported location (PR head ref, or local working copy if the workspace matches).
- Confirm the quoted evidence matches and the issue is genuinely present there.
- If the issue is real but the line numbers are off, correct them. If it doesn't exist at the location, **drop it**.
- Merge duplicates (multiple lenses/sub-agents finding the same issue) into one entry; higher severity wins. If two findings genuinely contradict, resolve it against the code yourself.

Never post a finding you couldn't verify — a single hallucinated or mislocated comment makes the
author distrust the entire review. (If a file was genuinely inaccessible, you may include it
flagged `⚠️ UNVERIFIED`.)

#### 3b. Nitpick filter (signal gate)
Drop low-value noise so the real issues aren't buried:
- **Drop** style-only findings with no functional/security/correctness impact (formatting, naming preference, import order) — unless the project has no linter/formatter and the user asked for style.
- **Keep** anything with functional, security, correctness, or resilience impact, or a real structural improvement.
- **Never filter** security findings or anything Critical/High — they always pass through.

Note in the summary how many findings were dropped as nits.

#### 3c. Number and categorize
Assign each surviving issue a sequential number (#1, #2, ...) and categorize it. This numbered
list is the backbone of the review — it appears in the summary AND inline comments reference back to it.

For each issue, prepare:
1. **Number and title** — `3: embed_fn typed as Any`
2. **Category** — Bugs, Performance, Design/Consistency, Test Coverage, Other
3. **One-line summary** — for the review summary body
4. **Full inline comment** — detailed explanation with code suggestion, to be posted on the specific line
5. **File and line** — exact location in the diff

Prioritize by impact:
- **Bugs/correctness** — always include, these block merge
- **Security** — always include
- **Performance with measurable impact** — include
- **Design/API consistency** — include
- **Test coverage gaps** — include
- **Best practice improvements** — include the most impactful, skip minor nits if there are many
- **Style/formatting** — skip if the project has a linter/formatter configured

Aim for 5-15 numbered issues. If you find more than 15, consolidate related ones and prioritize.

### Phase 3.5: Persist findings to a file (before any posting)

Write the complete numbered issue list to a durable findings file **now**, before you present or
post anything. This is the artifact the user reviews/approves against, and the source of truth
`pr-code-review-gap-analyzer` reads later — including findings the user decides NOT to post.

- **Path:** `<config>/reviews/<YYYY-MM-DD>__<owner>__<repo>__pr<N>.md` (append `__run2`, `__run3`, …
  for same-day re-reviews of the same PR so the path stays unique).
- **Format:** the persisted-findings-file schema in
  [`../_shared/review-findings-schema.md`](../_shared/review-findings-schema.md) — a header block
  with `pr_url`, `repo`, `pr_number`, `review_date`, `head_sha`, `reviewer`, `verdict` (start as
  `pending`), and `tickets`; then every finding with its `file:line`, category, severity,
  evidence, suggested fix, the full inline-comment body, and a `decision` field set to `proposed`.
- Create the `<config>/reviews/` directory if it doesn't exist. Use a plain write (not append) —
  one file per review.

You will update each finding's `decision` (and the header `verdict`) as the user approves, skips,
and you submit (Phases 5–6). This is the sentinel file the `validate-findings.sh` hook checks —
see [`findings-sentinel-schema.md`](findings-sentinel-schema.md).

### Phase 4: Present Summary to User

Before posting anything, present the full structured summary — a preview of the summary body +
the list of inline comments.

```
## Code Review: [PR title]

[One-sentence appreciation — thank the author, acknowledge the scope/value of the contribution]

### What works well
- [Specific positive observation with quantified detail where possible]
- [Another positive]

### Issues requiring changes

**Bugs:**
1. [Short description] — `file:line`
2. [Short description] — `file:line`

**Performance:**
3. [Short description] — `file:line`

**Design/Consistency:**
4. [Short description] — `file:line`

**Test coverage gaps:**
5. [Short description] — `file:line`

### Recommendations
- Fix #1 and #2 before merge (correctness blockers)
- Items #3-#4 should be addressed but aren't blockers
- Item #5 is a suggestion for improvement
```

Then say: **"I have N inline comments to post (one per numbered issue above). Let me walk through each one for your review before posting."**

### Phase 5: Walk Through Inline Comments One by One

For each numbered issue, present the inline comment that will be posted on the specific code line:

```
**#N: [Short title]**

File: `path/to/file.ext`, line NN

[Full inline comment body exactly as it will appear on GitHub:
- What's wrong and why it matters
- Concrete fix suggestion with code snippet
- Reference to comparable implementation if relevant
- Self-contained — a reader seeing only this comment should understand the issue]

Want me to post this, or would you like to edit?
```

**CRITICAL: Wait for explicit user confirmation** ("post", "yes", "go ahead") before posting each
comment. If the user wants to edit, incorporate their changes and re-present. If the user wants
to skip a comment, skip it.

**Record each decision in the findings file as you go:** when the user approves, set that
finding's `decision: posted`; when they skip one, set `decision: skipped` and capture a one-line
`skip_reason` in their words ("out of scope", "nit", "disagreed", "duplicate"). This is what
later lets `pr-code-review-gap-analyzer` tell a *detection* miss from a *judgment* miss.

The user may also say "post all remaining" to batch-approve the rest.

### Phase 6: Post Comments and Submit Review

1. **Create a pending review** using `pull_request_review_write` with method `create` (no `event` parameter — creates a pending/draft review)
2. **Add each approved inline comment** using `add_comment_to_pending_review` with:
   - `path`: exact file path from the diff
   - `line`: line number from the RIGHT side of the diff
   - `side`: "RIGHT"
   - `subjectType`: "LINE"
   - `body`: the inline comment text
3. **After all inline comments are posted**, draft the review summary body and present it to the user — the top-level review comment, the "table of contents" that gives the author an overview before the inline details.

   > "All N inline comments are added to the pending review. Here's the summary that will be posted as the top-level review comment:"
   >
   > ---
   > [Show the full summary body — see template below]
   > ---
   >
   > "Submit as **Request Changes**, **Comment**, or **Approve**? Feel free to edit the summary above before I submit."

4. **Wait for the user's choice AND approval of the summary text.** If the user edits the summary, incorporate changes. Do NOT submit until the user explicitly confirms both the verdict and the summary.
5. Submit using `pull_request_review_write` with method `submit_pending` and the chosen `event` (REQUEST_CHANGES, COMMENT, or APPROVE) with the approved summary as the `body`.
6. **Finalize the findings file:** set the header `verdict` to the submitted event, confirm every finding's `decision` is `posted` or `skipped` (none left `proposed`), and add the trailing `posted: X / skipped: Y / total: N` summary line.
7. **Append a review log entry** to `<config>/retros/pr-review-log.md` (create the file if it doesn't exist). Always do this after the findings file is finalized — it is the cross-PR index that lets you find any past review quickly, and the spine `pr-code-review-retrospective` walks.

   Format:
   ```
   ## ENTRY <YYYY-MM-DD> | <owner>/<repo>#<N>
   - pr_url: <PR URL>
   - findings_file: <config>/reviews/<findings-file-name>.md
   - verdict: REQUEST_CHANGES | COMMENT | APPROVE
   - found: <total findings count> (<summary>)
   - posted: X / skipped: Y
   - gap_analyzed: no
   ```

   Append, never overwrite — earlier entries must be preserved. For re-reviews of the same PR,
   append a new entry (same format) rather than editing the existing one.

## Review Summary Body Template

The summary body is the top-level review comment. It should be self-contained — someone reading
only this comment (without the inline comments) should understand all the issues and their
severity. The inline comments provide the detailed evidence and code suggestions.

```
## Code Review: [PR title]

[One-sentence appreciation]

### What works well
- [Specific positive with quantified detail]

### Issues requiring changes

**Bugs:**
1. [Description] — [impact]

**Performance:**
2. [Description] — [impact]

**Design/Consistency:**
3. [Description]

**Test coverage gaps:**
4. [Description]

### Recommendations
- [What must be fixed before merge, referencing issue numbers]
- [What should be fixed but isn't a blocker]
- [What's a nice-to-have suggestion]

See inline comments for detailed explanations and suggested fixes.
```

## Re-Review Mode (Comment Resolution Check)

This is the second (or third...) pass over a PR you've reviewed before. The user has left review
comments, the author pushed changes and/or replied, and now the user wants to know: **did my
previous feedback get handled, is anything still blocking, and should I approve now?**

Trigger when the user says "check comments", "re-review", "did they address my feedback", "round 2", or similar.

> **Which skill for which job** (these three are adjacent — pick deliberately):
> - **`pr-code-review` Re-Review mode (this)** — you are the REVIEWER re-checking a PR *you reviewed*. "Were MY comments addressed? Should I approve?" Produces an approve/request-changes verdict.
> - **`pr-comment-resolver`** — you are the AUTHOR. "Reviewers commented on MY PR — triage, fix the code, and reply." Produces code fixes + replies.
> - **`pr-code-review-gap-analyzer`** — meta/quality. "Compare MY review against OTHER reviewers on the same PR to find what my review skill missed." Produces gap log + eval tests.

The job is NOT just "did a commit touch this line." A comment can be resolved by **code**, by
**conversation** (the author replied with a fix reference, a sound rationale, or a deferral to a
tracked follow-up), or by both. Evaluate two independent signals per comment — *conversation* and
*code* — alongside the thread's GitHub state.

### Process

#### Step 1: Establish the review round
- Determine which round this is. Use `pull_request_read` with method `get_reviews` to count prior reviews **by the current user** (use `get_me` to confirm who that is). This pass is round = (prior rounds by you) + 1. If you've never reviewed this PR, tell the user this looks like a first review and offer the full review process instead.
- Note the timestamp of your most recent prior review — it's the cutoff for "what changed since."

#### Step 2: Gather review threads (all three signals)
- Use `pull_request_read` with method `get_review_comments` to fetch all review threads.
- Include **both** open and resolved threads — resolved ones are worth a quick verify for false resolutions.
- For each thread, capture: **thread state** (`isResolved`/`isOutdated`), **conversation** (original comment + every reply and its gist), and **original location** (file + line).

#### Step 3: Gather code evidence
- Use `list_commits` to get commits on the PR branch; identify those pushed **after** your last review.
- Use `get_commit` (or `pull_request_read` get_diff) to inspect those diffs, focused on files/lines mentioned in the threads.
- If the original location was refactored or moved, follow the change to its new home rather than reporting "no change."

#### Step 4: Grade each comment on both axes
For each thread, assign a **status** (not a bare PASS/FAIL):
- ✅ **Resolved (code)** — a commit since the last review changed the code to match the intent, **and you verified the fix actually works** — not merely that *a* change was made. A fix that only makes the intended behavior *possible* (adds a method/branch never correctly wired, parses a library return value with the wrong shape, handles only the happy path) is **not** resolved.
- ✅ **Resolved (discussion)** — the conversation resolves it: reviewer agreed, author gave a sound rationale, a question got a satisfactory answer, or it was deferred to a tracked follow-up (link it).
- 🔶 **Replied — needs your decision** — author pushed back or explained a tradeoff, no agreement and no code change. An open conversation awaiting the reviewer, **not** a failure.
- ❌ **Open — unaddressed** — no reply and no relevant code change.
- ⚠️ **Inconsistent** — thread state and evidence disagree. Surface it.

Lean toward Resolved for subjective (style) comments if any reasonable effort was made. Keep
original severity in mind — an unresolved **bug/security** comment is a blocker; an unresolved
**nit** is not.

**Re-scan newly-added code (do not just diff the flagged lines).** When a fix introduces *new*
code — a new method, branch, helper, or file — treat that new code as a first-pass review target:
apply the full [`../_shared/review-checklist.md`](../_shared/review-checklist.md) to it, not only a
check that the original comment's intent was met. A fix routinely lands fresh blockers *inside*
the code that resolves an old comment. Verifying a fix was *added* without re-scanning what it
added is the single most common re-review miss.

#### Step 5: Present the per-comment report
```
## Re-Review (Round N): [PR title]

**PR:** owner/repo#N
**Your last review:** [date] ([REQUEST_CHANGES / COMMENT])
**Threads evaluated:** M
**Commits since last review:** [short SHAs + messages, or "none"]

---

### #1: [Short title summarizing the comment]
**Reviewer:** @username   **Severity:** [Bug / Security / Design / Test / Nit]
**File:** `path/to/file.ext:NN`
**Asked for:** [one sentence]
**Conversation:** [no reply | author: "<gist>" | reviewer agreed | deferred to #456]
**Code evidence:** [diff hunk or description, or "No change in the relevant area"]
**Status:** ✅ Resolved (code) | ✅ Resolved (discussion) | 🔶 Replied — needs your decision | ❌ Open | ⚠️ Inconsistent
**Notes:** [nuance]
```

#### Step 6: Final verdict (always end with this)
```
### Verdict — Round N

**Prior comments:**
- ✅ Resolved: X/M  (code: A, discussion: B)
- 🔶 Needs your decision: C  → [list #s]
- ❌ Still open: D  → [list #s]
- ⚠️ Inconsistent: E  → [list #s]

**New issues found this round:** [count, or "none"]

**Still blocking:** [list blockers by # — unresolved Bug/Security items and any new correctness regressions. If none: "Nothing blocking."]

**Recommendation:** [exactly one]
- ✅ **Approve** — all prior comments resolved, nothing blocking. Want me to submit an APPROVE review?
- 💬 **Comment / your call** — no hard blockers, but C item(s) need your decision (#...).
- 🔁 **Request changes again** — D blocker(s) still open (#...). Another round needed.
```

When recommending Approve or Request-changes-again, offer to submit that review (reuse Phase 6)
rather than just stating it. Wait for explicit confirmation before submitting.

## Handling Edge Cases

### PR is too large (>30 files or >2000 lines)
- Focus on core implementation files first; skip auto-generated files (lock files, compiled output)
- Tell the user: "This is a large PR. I'll focus on [core files] first. Want me to review [other files] after?"

### No comparable implementation exists
- Skip the comparison step; focus on general best practices and the project's conventions from other modules

### User provides no focus areas
- Review all categories equally; lead with correctness and test coverage

### PR has existing reviews
- Use `pull_request_read` with method `get_review_comments` to check existing feedback
- Don't duplicate comments already made by other reviewers; reference them if you agree

### Language you're less familiar with
- Use web search to verify API usage and idioms; be transparent about uncertainty
- Focus on logic, architecture, and test coverage which are language-agnostic

## Comment Tone & Style Guidelines

Based on [Google's engineering practices](https://google.github.io/eng-practices/review/reviewer/looking-for.html):

### Tone principles
- **Focus on the code, not the person** — "this function could be simplified", not "you wrote this poorly"
- **Ask questions instead of demanding changes** — "Have we considered what happens when X is empty?"
- **Offer your perspective** — "I think this could be clearer as..." rather than "This is wrong"
- **Be specific and objective** — "consider using a Set instead of a List here to prevent duplicates"
- **Explain the why** — don't just say what to change, explain why it matters

### Comment labeling
Prefix inline comments with a label when the intent isn't obvious:
- **`Bug:`** — correctness issue that must be fixed
- **`Nit:`** — minor style/preference suggestion, non-blocking
- **`Question:`** — seeking clarification, not necessarily requesting a change
- **`Suggestion:`** — optional improvement the author can take or leave

### Positive feedback
- Always include positive observations in the summary ("What works well")
- Call out something particularly clever or well-done — it's sometimes more valuable than the criticism

## Anti-Patterns

- DO NOT post comments without user approval — always present each comment first and wait
- DO NOT submit the review without asking the user for the verdict and showing the summary
- DO NOT review only the diff — read full files for context
- DO NOT make vague comments like "this could be better" — always be specific with code suggestions
- DO NOT nitpick formatting if the project has a linter/formatter configured
- DO NOT repeat the same feedback on multiple instances — comment once and say "same pattern at lines X, Y, Z"
- DO NOT approve PRs with known correctness bugs
- DO NOT pile on — prioritize the most impactful issues
- DO NOT forget to mention what's done well — balanced reviews are more effective
- DO NOT assume the workspace is the same repo as the PR — always check
- DO NOT demand more tests when the existing tests already assert observable behavior (sufficiency over completeness)
- DO NOT use dismissive language ("just do X", "obviously", "why didn't you...")
- DO NOT focus on speculative over-engineering concerns — solve the problem that exists now

## Tools Used

This skill relies on GitHub MCP tools:
- `pull_request_read` — get PR details, diff, files, reviews (`get_reviews`), review threads (`get_review_comments`), check runs
- `pull_request_review_write` — create pending review, submit review
- `add_comment_to_pending_review` — add inline comments to pending review
- `list_commits`, `get_commit` — inspect commits pushed since your last review (re-review mode)
- `get_me` — confirm the current user when counting prior review rounds
- `issue_read` — read related issues for context
- `get_file_contents` — read files from remote repositories

And standard tools for local workspace (when applicable): local file read/search, `web_fetch`
for API docs, and file write/append for the per-review findings file under `<config>/reviews/`
and the `<config>/retros/pr-review-log.md` index.

## How this feeds the improvement loop

This skill is a **sensor that records facts**, not an editor. It produces two durable artifacts
per run — the **findings file** and the **review-log entry** — and does NOT compute review gaps
or edit skill prompts.

→ findings files + `pr-review-log.md` → `pr-code-review-gap-analyzer` (compares vs other
reviewers, logs misses/false-positives + adds eval tests) → `review-gaps-retro.md` →
`pr-code-review-retrospective` (consolidates ≥3 reviews, edits the checklist/skill, re-runs the
eval) → eval verifies. See [`governed-flow-test-results.md`](governed-flow-test-results.md).

---
> Path placeholders: `<config>` = your assistant's user-level dir (`~/.kiro` for Kiro, `~/.claude` for Claude). See [`../_shared/paths.md`](../_shared/paths.md).
