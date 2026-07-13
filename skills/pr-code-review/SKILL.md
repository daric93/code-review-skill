---
name: pr-code-review
description: Performs a thorough code review of any GitHub PR — local workspace or fully remote. Supports any language/framework. Posts inline comments as a pending review for user approval before submission.
inclusion: manual
---

# PR Code Review

You perform thorough, professional code reviews on GitHub pull requests. You work with any language, any framework, any project — whether it's open in the current workspace or a fully remote repo you've never seen before. You produce actionable inline comments posted as a pending GitHub review that the user approves before submission.

## How to Use

When this skill runs, provide:

### Minimal (remote PR, no local project)
```
#pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
```

### With related issue/ticket
```
#pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
Ticket: https://github.com/owner/repo/issues/456
```

### With focus areas
```
#pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
Ticket: https://github.com/owner/repo/issues/456
Focus: correctness, API consistency, test coverage
Compare with the Redis implementation in the project.
```

### Multiple context sources
```
#pr-code-review
Review this PR: https://github.com/owner/repo/pull/123
Ticket: https://github.com/owner/repo/issues/456
Also see: https://github.com/owner/repo/issues/789
Design doc: https://github.com/owner/repo/blob/main/docs/design/feature-x.md
```

### Re-review (verify previous comments were addressed, get an approve/not verdict)
```
#pr-code-review
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
- Use your provider's local file reading/search tools (in Kiro: `readFile`, `readCode`, `grepSearch`) — faster and more complete
- Read project config files locally (pyproject.toml, package.json, Cargo.toml, pom.xml, .csproj, etc.)
- Read comparable implementations locally
- Read test files locally

**If the PR is for a remote repo (not open locally):**
- Use `get_file_contents` from GitHub MCP to read files from the repo
- Read the repo root to understand structure: `get_file_contents` with path `/`
- Read project config files: look for pyproject.toml, package.json, Cargo.toml, go.mod, pom.xml, build.gradle, .csproj, Makefile, etc.
- Read CONTRIBUTING.md if it exists

#### 1d. Detect language and ecosystem

Auto-detect from the changed files and project config:
- **Python**: pyproject.toml, setup.py, requirements.txt → check for ruff, mypy, pyright, pytest conventions
- **JavaScript/TypeScript**: package.json, tsconfig.json → check for eslint, prettier, jest/vitest conventions
- **Go**: go.mod → check for golint, go vet conventions
- **Rust**: Cargo.toml → check for clippy conventions
- **Java/Kotlin**: pom.xml, build.gradle → check for checkstyle, spotbugs conventions
- **C#/.NET**: .csproj, Directory.Build.props → check for editorconfig, analyzers
- **C/C++**: CMakeLists.txt, Makefile → check for clang-tidy, cppcheck conventions

Adapt review criteria to the detected language's idioms and best practices.

#### 1e. Read changed files in full context
- For each changed file in the PR, read the complete file (not just the diff) to understand surrounding context
- Use local tools if workspace matches, otherwise `get_file_contents` with the PR head ref

#### 1f. Read comparable implementations (if applicable)
- If the PR adds a new module/provider/package, find the existing equivalent in the project
- Compare patterns, API surface, error handling, test structure
- This is critical for consistency reviews

### Phase 2: Analyze the Code

#### Optional: fan out the lenses to sub-agents (deeper reviews)
For a large or high-risk change, and **where sub-agent delegation is supported** (e.g. `invokeSubAgent`),
you may run the review as parallel fresh-context reviewers instead of one linear pass — one
sub-agent per lens, using the four canonical lenses defined in
[`_shared/review-findings-schema.md`](../_shared/review-findings-schema.md): **codebase alignment &
design fit** (primary), **correctness & security**, **requirements alignment**, and **testability**.
The deep security half of the correctness-&-security lens is already delegated to the
`security-reviewer` sub-agent (see below), so that reviewer covers it. Each lens still applies the
relevant categories from [`_shared/review-checklist.md`](../_shared/review-checklist.md) (e.g.
performance, resource management, and resilience checks fold into the correctness and codebase-fit
lenses). Each sub-agent returns findings with `file:line` and a quoted code `evidence` snippet (per
the findings schema). Merge their findings, then continue to Phase 3, where verification and the
nitpick filter consolidate them.

Skip the fan-out and review all categories inline yourself when sub-agents are unavailable
(Supervised mode, headless/eval runs, or a provider without sub-agents) or the change is small. The
review criteria are identical either way — fan-out only changes *who* applies them. Note in your
summary whether you fanned out or reviewed inline.

**Domain reviewers (optional, self-gating).** If the change uses Valkey GLIDE client code and a
`glide-reviewer` sub-agent is available, also delegate a GLIDE pass to it (Mode B → inline findings).
It **self-gates** — for non-GLIDE code it reports "not applicable" and adds nothing — so this stays
safe for general reviews and never makes this skill domain-specific. Fold its findings into Phase 3
exactly like the security findings. Other domains can plug in their own self-gating reviewers the
same way.

#### Review criteria — the shared rulebook
Review each changed file against **every check in [`_shared/review-checklist.md`](../_shared/review-checklist.md)** — the shared, language-agnostic review rulebook covering the library-API pre-check, Design & Architecture, Correctness, Resource Management, Language-Specific Best Practices, API Consistency, Performance, Resilience & Operational Safety, Security, Test Quality & Coverage, Documentation, and Dependencies/Build/Licensing. Weight categories by user-specified focus areas if provided; otherwise review all equally.

This is the **same rulebook the Valkey `valkey-integration-subagent-self-reviewer` uses**, so the checks stay identical across both reviewers. When a review rule is added or sharpened, edit that shared file — not this skill.

The deep Security pass is still delegated to the dedicated sub-agent (next):

#### Security

> **Delegate the security pass to the `security-reviewer` sub-agent (where sub-agent delegation is supported).**
> Before working through the checklist below yourself, delegate to the `security-reviewer` sub-agent
> using your provider's sub-agent mechanism (in Kiro, `invokeSubAgent`) and have it do a focused,
> fresh-context security review. This gives security its
> own dedicated set of eyes instead of being one item among many.
>
> - **How:** invoke the `security-reviewer` sub-agent with `name: "security-reviewer"` and tell it to
>   **apply the `security-review` skill**. In the prompt, tell it this is
>   **Mode B (pr-code-review / ad-hoc)** so it returns findings inline and writes no files. Give it
>   the PR URL (owner/repo/number), the PR title, ticket link, and any user-specified security
>   focus areas. The sub-agent runs with GitHub MCP access, so for a **remote PR** it can fetch the
>   diff and read changed files itself (`pull_request_read` get_diff/get_files, `get_file_contents`
>   at the head ref) — you don't need to paste the diff. For a **local workspace** PR, pass the
>   changed-file paths via `contextFiles` so it reads them locally.
> - **What it returns:** findings grouped by severity (CRITICAL / WARNING / INFO) with `file:line`,
>   exploit, and a suggested fix, covering injection (SQL / command / query DSL / XSS / path /
>   deserialization), auth & authorization, secrets/credentials, and insecure data handling.
> - **Fold the results in:** merge the sub-agent's findings into the numbered issue list in Phase 3
>   under the **Security** category, keeping its severity and `file:line`. De-duplicate against
>   anything you also found. You remain responsible for the final review — sanity-check each
>   finding against the actual code before posting it as an inline comment; drop or downgrade any
>   that don't hold up.
> - **Fallback:** if sub-agents are unavailable (e.g. Supervised mode) or the sub-agent can't run,
>   perform the checklist below yourself and note that the dedicated pass was skipped.

Whether produced by the sub-agent or by you, the security baseline to cover is the **Security** section of [`_shared/review-checklist.md`](../_shared/review-checklist.md) (input validation, query/DSL escaping completeness, multiple escape contexts, token-separator behavior, secret handling, authn/authz, dependency CVEs, encryption in transit/at rest). Fold any security findings into the numbered issue list in Phase 3 under the **Security** category.

### Phase 3: Build the Numbered Issue List

Before numbering, run two precision gates over the raw findings from Phase 2 (whether produced by an inline pass or by fan-out sub-agents).

#### 3a. Verify-then-include (precision gate)
For every candidate finding, confirm it against the actual code before it earns a number:
- Read the real file at the reported location (PR head ref, or local working copy if the workspace matches).
- Confirm the quoted evidence matches and the issue is genuinely present there.
- If the issue is real but the line numbers are off, correct them. If it doesn't exist at the location, **drop it**.
- Merge duplicates (multiple lenses or sub-agents finding the same issue) into one entry; higher severity wins. If two findings genuinely contradict, resolve it against the code yourself.

Never post a finding you couldn't verify — a single hallucinated or mislocated comment makes the author distrust the entire review. (If a file was genuinely inaccessible, you may include it flagged `⚠️ UNVERIFIED`.)

#### 3b. Nitpick filter (signal gate)
Drop low-value noise so the real issues aren't buried:
- **Drop** style-only findings with no functional/security/correctness impact (formatting, naming preference, import order) — unless the project has no linter/formatter and the user asked for style.
- **Keep** anything with functional, security, correctness, or resilience impact, or a real structural improvement.
- **Never filter** security findings or anything Critical/High — they always pass through.

Note in the summary how many findings were dropped as nits.

#### 3c. Number and categorize
Assign each surviving issue a sequential number (#1, #2, ...) and categorize it. This numbered list is the backbone of the review — it appears in the summary AND inline comments reference back to it.

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
  [`_shared/review-findings-schema.md`](../_shared/review-findings-schema.md) — a header block with
  `pr_url`, `repo`, `pr_number`, `review_date`, `head_sha`, `reviewer`, `verdict` (start as
  `pending`), and `tickets`; then every finding with its `file:line`, category, severity, evidence,
  suggested fix, the full inline-comment body, and a `decision` field set to `proposed`.
- Create the `<config>/reviews/` directory if it doesn't exist. Use a plain write (not append) —
  one file per review.

You will update each finding's `decision` (and the header `verdict`) as the user approves, skips,
and you submit (Phases 5–6).

### Phase 4: Present Summary to User

Before posting anything, present the full structured summary. This is a preview of what the review will look like — the summary body + the list of inline comments.

```
## Code Review: [PR title]

[One-sentence appreciation — thank the author, acknowledge the scope/value of the contribution]

### What works well
- [Specific positive observation with quantified detail where possible, e.g., "~400 lines of tests with good edge case coverage"]
- [Another positive]

### Issues requiring changes

**Bugs:**
1. [Short description] — `file:line`
2. [Short description] — `file:line`

**Performance:**
3. [Short description] — `file:line`

**Design/Consistency:**
4. [Short description] — `file:line`
5. [Short description] — `file:line`

**Test coverage gaps:**
6. [Short description] — `file:line`

**Other:**
7. [Short description] — `file:line`

### Recommendations
- Fix #1 and #2 before merge (correctness blockers)
- Items #3-#5 should be addressed but aren't blockers
- Items #6-#7 are suggestions for improvement
```

Then say: **"I have N inline comments to post (one per numbered issue above). Let me walk through each one for your review before posting."**

### Phase 5: Walk Through Inline Comments One by One

For each numbered issue, present the inline comment that will be posted on the specific code line:

```
**#N: [Short title]**

File: `path/to/file.ext`, line NN

[Full inline comment body exactly as it will appear on GitHub. This should include:
- What's wrong and why it matters
- Concrete fix suggestion with code snippet
- Reference to comparable implementation if relevant
- Note: the inline comment should be self-contained — a reader seeing only this comment (not the summary) should understand the issue]

Want me to post this, or would you like to edit?
```

**CRITICAL: Wait for explicit user confirmation** ("post", "yes", "go ahead") before posting each comment. If the user wants to edit, incorporate their changes and re-present. If the user wants to skip a comment, skip it.

**Record each decision in the findings file as you go:** when the user approves a comment, set that
finding's `decision: posted`; when they skip one, set `decision: skipped` and capture a one-line
`skip_reason` in their words ("out of scope", "nit", "disagreed", "duplicate"). This is what later
lets `pr-code-review-gap-analyzer` tell a *detection* miss from a *judgment* miss.

The user may also say "post all remaining" to batch-approve the rest.

### Phase 6: Post Comments and Submit Review

1. **Create a pending review** using `pull_request_review_write` with method `create` (no `event` parameter — this creates a pending/draft review)
2. **Add each approved inline comment** using `add_comment_to_pending_review` with:
   - `path`: exact file path from the diff
   - `line`: line number from the RIGHT side of the diff
   - `side`: "RIGHT"
   - `subjectType`: "LINE"
   - `body`: the inline comment text
3. **After all inline comments are posted**, draft the review summary body and present it to the user. The summary body is what appears as the top-level review comment on GitHub — it's the "table of contents" that gives the author an overview before they read the inline details.

   Use the numbered format from Phase 4, adapted into the final submission body:

   > "All N inline comments are added to the pending review. Here's the summary that will be posted as the top-level review comment:"
   >
   > ---
   > [Show the full summary body — see template below]
   > ---
   >
   > "Submit as **Request Changes**, **Comment**, or **Approve**? Feel free to edit the summary above before I submit."

4. **Wait for the user's choice AND approval of the summary text.** If the user edits the summary, incorporate changes. Do NOT submit until the user explicitly confirms both the verdict and the summary.
5. Submit using `pull_request_review_write` with method `submit_pending` and the chosen `event` (REQUEST_CHANGES, COMMENT, or APPROVE) with the approved summary as the `body`.
6. **Finalize the findings file:** set the header `verdict` to the submitted event, confirm every
   finding's `decision` is `posted` or `skipped` (none left `proposed`), and add the trailing
   `posted: X / skipped: Y / total: N` summary line.
7. **Append a review log entry** to `<config>/retros/pr-review-log.md` (create the file if it
   doesn't exist). This must always be done after the findings file is finalized — it is the
   cross-PR index that lets you find any past review quickly.

   Format:
   ```
   ## ENTRY <YYYY-MM-DD> | <owner>/<repo>#<N>
   - pr_url: <PR URL>
   - findings_file: <config>/reviews/<findings-file-name>.md
   - verdict: REQUEST_CHANGES | COMMENT | APPROVE
   - found: <total findings count> (<summary, e.g. "2 security/blocking, 1 correctness, 3 suggestions">)
   - posted: X / skipped: Y
   - gap_analyzed: no
   ```

   Append, never overwrite — earlier entries must be preserved. For re-reviews of the same PR,
   append a new entry (same format) rather than editing the existing one.

## Review Summary Body Template

The summary body is the top-level review comment. It should be self-contained — someone reading only this comment (without the inline comments) should understand all the issues and their severity. The inline comments provide the detailed evidence and code suggestions.

```
## Code Review: [PR title]

[One-sentence appreciation — thank the author, acknowledge the contribution's value]

### What works well
- [Specific positive with quantified detail]
- [Another positive]

### Issues requiring changes

**Bugs:**
1. [Description] — [impact]
2. [Description] — [impact]

**Performance:**
3. [Description] — [impact]

**Design/Consistency:**
4. [Description]
5. [Description]

**Test coverage gaps:**
6. [Description]

**Other:**
7. [Description]

### Recommendations
- [What must be fixed before merge, referencing issue numbers]
- [What should be fixed but isn't a blocker]
- [What's a nice-to-have suggestion]

See inline comments for detailed explanations and suggested fixes.
```

## Re-Review Mode (Comment Resolution Check)

This is the second (or third, fourth...) pass over a PR you've reviewed before. The user has already left review comments, the author has pushed changes and/or replied, and now the user wants to know: **did my previous feedback get handled, is anything still blocking, and should I approve now?**

Trigger this mode when the user says "check comments", "re-review", "did they address my feedback", "round 2", or similar.

> **Which skill for which job** (these three are adjacent — pick deliberately):
> - **`pr-code-review` Re-Review mode (this)** — you are the REVIEWER re-checking a PR *you reviewed*. "Were MY comments addressed? Should I approve?" Produces an approve/request-changes verdict.
> - **`pr-comment-resolver`** — you are the AUTHOR. "Reviewers commented on MY PR — triage, fix the code, and reply." Produces code fixes + replies.
> - **`pr-code-review-gap-analyzer`** — meta/quality. "Compare MY review against OTHER reviewers on the same PR to find what my review skill missed." Produces gap log + eval tests.
> If the user wants a verdict on their own prior review → this mode. If they want to fix comments on their own PR → comment-resolver. If they want to measure/improve the review skill itself → gap-analyzer.

The job is NOT just "did a commit touch this line." A comment can be resolved by **code**, by **conversation** (the author replied with a fix reference, a sound rationale, or a deferral to a tracked follow-up), or by both. Evaluate two independent signals per comment — *conversation* and *code* — alongside the thread's GitHub state. A reply with good reasoning and no code change can be a valid resolution; a code change with no reply can also be a valid resolution. Show both signals; never collapse them into a single diff-only check.

### Process

#### Step 1: Establish the review round

- Determine which round this is. Use `pull_request_read` with method `get_reviews` to count prior reviews **by the current user** (use `get_me` if you need to confirm who that is). This pass is round = (prior rounds by you) + 1. If you've never reviewed this PR, tell the user this looks like a first review and offer to run the full review process instead.
- Note the timestamp of your most recent prior review — it's the cutoff for "what changed since."

#### Step 2: Gather review threads (all three signals)

- Use `pull_request_read` with method `get_review_comments` to fetch all review threads on the PR.
- Include **both** open (unresolved) and resolved threads — resolved ones are worth a quick verify for false resolutions.
- For each thread, capture all three signals that feed the grade:
  1. **Thread state** — `isResolved` / `isOutdated` flags from GitHub.
  2. **Conversation** — the original comment (body + author), plus every reply: who replied and the gist (agreement, disagreement/pushback, "done in `<sha>`", deferred to a tracked issue, or a question that got answered).
  3. **Original location** — file path and line(s) referenced.

#### Step 3: Gather code evidence

- Use `list_commits` to get commits on the PR branch; identify those pushed **after** your last review (Step 1 cutoff).
- Use `get_commit` (or `pull_request_read` get_diff) to inspect those diffs, focused on files/lines mentioned in the threads.
- If the original location was refactored or moved, follow the change to its new home rather than reporting "no change."

#### Step 4: Grade each comment on both axes

For each thread, read what was asked, then assign a **status** from this set (not a bare PASS/FAIL):

- ✅ **Resolved (code)** — a commit since the last review changed the code to match the intent, **and you verified the fix actually works** — not merely that *a* change was made. Reasonable alternative implementations count. A fix that only makes the intended behavior *possible* (e.g. adds a method/branch that is never correctly wired, parses a library return value with the wrong shape, or handles only the happy path) is **not** resolved.
- ✅ **Resolved (discussion)** — the conversation resolves it without (or in addition to) code: reviewer agreed, author gave a sound rationale for not changing, it was a question that got a satisfactory answer, or it was deferred to a tracked follow-up issue/PR (link it).
- 🔶 **Replied — needs your decision** — author pushed back or explained a tradeoff, no agreement reached and no code change. This is an open conversation awaiting the reviewer, **not** a failure.
- ❌ **Open — unaddressed** — no reply and no relevant code change. Still needs work.
- ⚠️ **Inconsistent** — thread state and evidence disagree (marked resolved but nothing supports it, or code changed but thread left open). Surface it so the user can reconcile.

Guidance: lean toward Resolved for ambiguous/subjective (style) comments if any reasonable effort was made. Keep the original severity in mind — an unresolved **bug/security** comment is a blocker; an unresolved **nit** is not.

**Re-scan newly-added code (do not just diff the flagged lines).** When a fix introduces *new* code — a new method, branch, helper, or file — treat that new code as a first-pass review target: apply the full [`_shared/review-checklist.md`](../_shared/review-checklist.md) to it, not only a check that the original comment's intent was met. A fix routinely lands fresh blockers *inside* the code that resolves an old comment (wrong library return-shape assumptions, default-limit truncation, swallowed errors, missing edge cases). Fold any new issues you find into "New issues found this round" (Step 6) and the "Still blocking" line. Verifying a fix was *added* without re-scanning what it added is the single most common re-review miss.

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
**Conversation:** [no reply | author: "<gist of reply>" | reviewer agreed | deferred to #456]
**Code evidence:** [diff hunk or description, or "No change in the relevant area"]
**Status:** ✅ Resolved (code) | ✅ Resolved (discussion) | 🔶 Replied — needs your decision | ❌ Open | ⚠️ Inconsistent
**Notes:** [nuance — e.g., "null check added but error message differs from the suggestion"]

---

### #2: [Short title]
...
```

#### Step 6: Final verdict (always end with this)

After the per-comment rows, close with the verdict the user is actually asking for:

```
### Verdict — Round N

**Prior comments:**
- ✅ Resolved: X/M  (code: A, discussion: B)
- 🔶 Needs your decision: C  → [list #s]
- ❌ Still open: D  → [list #s]
- ⚠️ Inconsistent: E  → [list #s]

**New issues found this round:** [count, or "none" — see note below]
- [Only if a full review was also requested or you spotted new regressions in the new commits]

**Still blocking:** [list the blockers by # — unresolved Bug/Security items and any new correctness regressions. If none: "Nothing blocking."]

**Recommendation:** [exactly one]
- ✅ **Approve** — all prior comments resolved, nothing blocking. Want me to submit an APPROVE review?
- 💬 **Comment / your call** — no hard blockers, but C item(s) need your decision (#...). Approve once you've weighed in.
- 🔁 **Request changes again** — D blocker(s) still open (#...). Another round needed.
```

When recommending Approve or Request-changes-again, offer to submit that review (reuse Phase 6) rather than just stating it. Wait for explicit confirmation before submitting, same as a first-round review.

### Combining with a fresh review pass

If the user wants both a resolution check AND a fresh look at the new commits, run Steps 1–6 first, then scan the post-last-review diffs for **new** issues (regressions, problems introduced by the fixes). Fold those into "New issues found this round" and the "Still blocking" line. Don't re-raise comments already resolved — focus on what changed.

## Handling Edge Cases

### PR is too large (>30 files or >2000 lines)
- Focus on the core implementation files first
- Skip auto-generated files (lock files, compiled output, etc.)
- Tell the user: "This is a large PR. I'll focus on [core files] first. Want me to review [other files] after?"

### No comparable implementation exists
- Skip the comparison step
- Focus on general best practices and the project's conventions from other modules

### User provides no focus areas
- Review all categories equally
- Lead with correctness and test coverage

### PR has existing reviews
- Use `pull_request_read` with method `get_review_comments` to check existing feedback
- Don't duplicate comments already made by other reviewers
- Reference existing comments if you agree: "Echoing @reviewer's point on line X — additionally..."

### Language you're less familiar with
- Use web search to verify API usage and idioms
- Be transparent: "I'm less certain about this [language] idiom — worth double-checking"
- Focus on logic, architecture, and test coverage which are language-agnostic

## Comment Tone & Style Guidelines

Based on [Google's engineering practices](https://google.github.io/eng-practices/review/reviewer/looking-for.html) and industry best practices for constructive code review feedback:

### Tone principles
- **Focus on the code, not the person** — say "this function could be simplified" not "you wrote this poorly"
- **Ask questions instead of demanding changes** — "Have we considered what happens when X is empty?" opens dialogue better than "Handle the empty case"
- **Offer your perspective** — "I think this could be clearer as..." rather than "This is wrong"
- **Be specific and objective** — instead of "this approach is bad", say "consider using a Set instead of a List here to prevent duplicates"
- **Explain the why** — don't just say what to change, explain why it matters

### Comment labeling
Prefix inline comments with a label when the intent isn't obvious:
- **`Bug:`** — correctness issue that must be fixed
- **`Nit:`** — minor style/preference suggestion, non-blocking
- **`Question:`** — seeking clarification, not necessarily requesting a change
- **`Suggestion:`** — optional improvement the author can take or leave
- No prefix needed for standard issues that clearly need addressing

### Positive feedback
- Always include positive observations in the summary ("What works well")
- If you see something particularly clever or well-done, call it out — it's sometimes more valuable to tell a developer what they did right than what they did wrong
- Quick praise in inline comments is fine too: "Nice approach here" or "Good edge case handling"

## Anti-Patterns

- DO NOT post comments without user approval — always present each comment first and wait
- DO NOT submit the review without asking the user for the verdict and showing the summary
- DO NOT review only the diff — read full files for context, and think about the change in the context of the whole system
- DO NOT make vague comments like "this could be better" — always be specific with code suggestions
- DO NOT nitpick formatting if the project has a linter/formatter configured
- DO NOT repeat the same feedback on multiple instances — comment once and say "same pattern at lines X, Y, Z"
- DO NOT approve PRs with known correctness bugs
- DO NOT pile on — prioritize the most impactful issues
- DO NOT forget to mention what's done well — balanced reviews are more effective
- DO NOT assume the workspace is the same repo as the PR — always check
- DO NOT skip reading comparable implementations when the PR adds a new module/provider
- DO NOT use dismissive language ("just do X", "obviously this should be Y", "why didn't you...")
- DO NOT focus on over-engineering concerns speculatively — solve the problem that exists now, not hypothetical future problems
- DO NOT accept complexity in tests just because they aren't production code — tests are code that must be maintained too

## Tools Used

This skill relies on GitHub MCP tools:
- `pull_request_read` — get PR details, diff, files, reviews (`get_reviews`), review threads (`get_review_comments`), check runs
- `pull_request_review_write` — create pending review, submit review
- `add_comment_to_pending_review` — add inline comments to pending review
- `list_commits`, `get_commit` — inspect commits pushed since your last review (re-review mode)
- `get_me` — confirm the current user when counting prior review rounds
- `issue_read` — read related issues for context
- `get_file_contents` — read files from remote repositories

And standard tools for local workspace (when applicable — tool names below are Kiro's; use your provider's equivalents):
- `readFile`, `readCode`, `readMultipleFiles` — read local files
- `grepSearch`, `fileSearch` — search local codebase
- `web_fetch`, `remote_web_search` — verify API usage, check docs
- file write/append (in Kiro, `fs_write` / `fs_append`) — write the per-review findings file under `<config>/reviews/` and append the index entry to `<config>/retros/pr-review-log.md`


## Review log (append one entry after every run)

After the review is submitted (or after the findings file is finalized, even if you posted
nothing), **append** one entry to the review log: `<config>/retros/pr-review-log.md`. This log is
the **index** of every review you've done — it's the spine `pr-code-review-retrospective` walks to decide which
reviews still need gap analysis. It does NOT contain gap analysis itself (that's
`pr-code-review-gap-analyzer`'s job) — it just records that a review happened and where its findings live.

**Append rules (mandatory):**
- ALWAYS append — never overwrite. Use an append operation (e.g. `fs_append`). Preserve prior entries.
- If the file does not exist, create it with the header `# PR Review Log`, then add the entry.
- Each entry MUST start with a stable, unique entry-ID header so `pr-code-review-retrospective` can track which
  reviews it has already processed:

```markdown
## ENTRY 2026-06-29 | owner/repo#123
- pr_url: https://github.com/owner/repo/pull/123
- findings_file: <config>/reviews/2026-06-29__owner__repo__pr123.md
- verdict: REQUEST_CHANGES
- found: 7 (Bugs: 2, Security: 1, Design: 2, Tests: 1, Other: 1)
- posted: 5 / skipped: 2
- gap_analyzed: no
```

The entry-ID is `ENTRY <YYYY-MM-DD> | <owner>/<repo>#<PR>` — calendar date of the run + repo#PR keeps
it unique across same-day runs. For a same-day re-review of the same PR, append a `(run 2)` suffix
(and point `findings_file` at the matching `__run2` file).

`gap_analyzed: no` means `pr-code-review-gap-analyzer` hasn't yet compared this review against other
reviewers. `pr-code-review-retrospective` flips it to `yes` once it has. Writing this entry is NOT optional —
write it every time, because a review that isn't logged is invisible to the improvement loop.

### How this feeds the improvement loop

This skill is a **sensor that records facts**, not an editor. It produces two durable artifacts per
run — the **findings file** (what we found + what we posted vs skipped) and the **review-log entry**
(the index pointing at it). It does NOT compute review gaps and does NOT edit skill prompts.

The loop downstream:
- `pr-code-review-gap-analyzer` reads a review's `findings_file` + the live PR, compares against other
  reviewers, and logs misses/false-positives to `review-gaps-retro.md`. Because the findings file
  records `skipped` decisions, it can tell a **detection miss** (we never found it) from a
  **judgment miss** (we found it but chose not to post).
- `pr-code-review-retrospective` walks `pr-review-log.md`, and once ≥3 reviews are unprocessed since the last
  retro, drives `pr-code-review-gap-analyzer` over each, consolidates the patterns across the batch, edits
  the checklist/skill, and re-runs the eval.

→ findings files + `pr-review-log.md` → `pr-code-review-gap-analyzer` → `review-gaps-retro.md` →
`pr-code-review-retrospective` improves the skill → eval verifies.

---
> Path placeholders: `<config>` = your assistant's user-level dir (`~/.kiro` for Kiro, `~/.claude` for Claude); `<workspace-config>` = the per-project dir (`.kiro` / `.claude`). See `_shared/paths.md`.
