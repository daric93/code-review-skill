# pr-code-review — Skill Invocation and Quality Tests

Written BEFORE the skill file. These test invocation correctness (when should the skill
trigger and not trigger) and output quality (given it triggers, does the output meet the bar).

---

## Positive Invocation Cases (SHOULD invoke)

### P1: Explicit review request with PR URL

**Context:** User says: "/pr-code-review Review this PR: https://github.com/owner/repo/pull/123"

**Expected:** Skill invokes, gathers PR context, produces a review with findings.
**Signals:** Explicit `/pr-code-review` invocation + PR URL present.

### P2: Re-review request

**Context:** User says: "/pr-code-review Re-review: https://github.com/owner/repo/pull/123"

**Expected:** Skill invokes in re-review mode, checks previous comments' resolution status.
**Signals:** Explicit invocation + "re-review" keyword + PR URL.

### P3: Review with focus areas

**Context:** User says: "/pr-code-review Review this PR: https://github.com/owner/repo/pull/456 Focus: security, correctness"

**Expected:** Skill invokes with focus areas parsed, weights security and correctness higher.
**Signals:** Explicit invocation + PR URL + focus directive.

---

## Negative Invocation Cases (SHOULD NOT invoke)

### N1: User mentions a PR while working on something else

**Context:** User says: "I'm fixing the bug from PR #123. Can you help me write the test?"

**Expected:** Skill does NOT invoke. The user wants help writing code, not a review.
**Failure mode if invoked:** Wastes time reviewing a PR when the user wanted coding help.

### N2: User asks about code without a PR

**Context:** User says: "Is this code correct?" followed by a raw code snippet (no PR URL).

**Expected:** Skill does NOT invoke. This is a question, not a review request. The model
should answer directly. The skill requires a PR URL for its workflow (posting comments).
**Failure mode if invoked:** Skill fails at Phase 1 (no PR to fetch), confusion about intent.

### N3: User requests code generation on a similar topic

**Context:** User says: "Write a code review tool that checks for SQL injection."

**Expected:** Skill does NOT invoke. The user wants code written, not a review performed.
**Failure mode if invoked:** Complete mismatch — produces a review of nothing instead of
generating code.

---

## Quality Cases (given correct invocation, does output meet the bar)

### Q1: Structured findings with location and fix

**Given:** The skill invokes on a PR with a SQL injection bug.
**Expected output:** Finding includes: file path + line number, what is wrong (SQL injection
via string interpolation), production impact (data exfiltration/modification), and a concrete
parameterized-query fix with the actual code.
**Failure if:** Finding is vague ("there might be a security issue"), lacks location, or
provides no actionable fix.

### Q2: Correct silence on clean code

**Given:** The skill invokes on a PR that contains only correct, well-structured code.
**Expected output:** Review states the code is correct and well-structured. "What works well"
section has specific positives. No fabricated issues.
**Failure if:** The skill invents problems to fill the review, flags style issues as bugs,
or performs speculative threat modeling.

### Q3: Precision gate — does not post unverified findings

**Given:** The skill invokes on a PR where one file has a bug and another is correct.
**Expected output:** Finding on the buggy file only. No findings fabricated on the correct
file. The verify-before-flag precision gate catches any drift.
**Failure if:** The skill produces findings on the correct file (precision failure).
