# Skill-Readiness Assessment

## Command 1: pr-code-review

### Invocation Boundary Analysis

**1. What triggers a human to run this command?**

The user is looking at a PR — either one they need to review (someone asked for a review),
or their own PR that they want a pre-submission check on. They have the PR URL. They've
decided that a review should happen now. The trigger is specific: "I have a PR to review."

**2. Could the model identify that trigger from context alone?**

Partially. If the user says "review this PR" or shares a PR URL, the trigger is obvious.
But the model cannot determine: whether the PR is ready for review (might be a draft),
whether the user is the right reviewer, or whether the review should happen now vs later.
The model should not auto-trigger on seeing a PR URL in a different context (e.g., the user
mentions a PR while fixing a bug — that's not a review request).

**3. What is the harm if the model invokes at the wrong time?**

Moderate harm. The skill posts GitHub review comments. If invoked on the wrong PR, at the
wrong time, or with the wrong focus, it creates noise that the PR author must read and
dismiss. Worse: if the user hasn't approved the comments (the skill has an approval gate),
nothing is posted — but token cost and time are wasted. The approval gate is the safety net
that makes incorrect invocation annoying rather than harmful.

**4. What is the harm if the model fails to invoke when it should?**

Low harm. The failure mode is "the user types /pr-code-review explicitly" — they do the
invocation manually. No step gets skipped; the human always knows they need a review because
they were asked for one.

**5. What ambiguous cases exist?**

- User says "look at this PR" — could mean review, could mean just read it for context
- User pastes a PR URL while discussing a bug — is this a review request or context?
- User says "check this code" with a snippet — is this a full review or a quick question?
- Re-review vs fresh review — user says "check this again" (re-review mode?) vs "review this" (fresh?)

In these cases, `inclusion: manual` is correct — let the user explicitly invoke with
`/pr-code-review` to remove ambiguity.

### Skill-readiness verdict: READY

pr-code-review is ready for skill conversion because:
- The invocation trigger is clear and specific ("review this PR" + URL)
- The harm of incorrect invocation is bounded by the approval gate (no comments post without user OK)
- The `inclusion: manual` mode eliminates over-invocation risk entirely
- The output is well-defined and evaluable (findings with file:line + fix)

---

## Command 2: security-review

### Invocation Boundary Analysis

**1. What triggers a human to run this command?**

Either: (a) they want a security-focused pass as part of a PR review (delegated by
pr-code-review), or (b) they want a standalone security audit of a specific file or diff.
The trigger is a deliberate "I want security eyes on this."

**2. Could the model identify that trigger from context alone?**

Only in case (a) — when pr-code-review explicitly delegates. For case (b), the model
cannot reliably distinguish "user wants security review" from "user is working on
security-related code" (different intent). A user implementing auth doesn't necessarily
want a security review of their in-progress work.

**3. What is the harm if invoked at the wrong time?**

Low to moderate. Security review is read-only (no file modifications, no GitHub posts in
standalone mode). Wrong invocation wastes time and tokens. Could produce false alarm
fatigue if it runs on every file touched.

**4. What is the harm if it fails to invoke?**

As a sub-agent delegate: moderate — pr-code-review's security coverage drops to inline-only
(still happens, just less thorough). As a standalone: low — user invokes manually.

**5. Ambiguous cases?**

- User working on auth code — security review wanted? Probably not until they're done.
- User says "is this secure?" — might want a full review or a quick answer.
- Code has known vulnerabilities being actively fixed — reviewing mid-fix is noise.

### Skill-readiness verdict: READY (as delegated sub-agent)

security-review is ready as a delegated skill invoked by pr-code-review (clear trigger,
bounded scope, no autonomous invocation needed). As a standalone skill it should remain
`inclusion: manual` for the same reasons as pr-code-review.

---

## Team Consensus Simulation: pr-code-review

Two engineers, Alice and Bob, both use the pr-code-review command independently.

### Disagreement 1: When to invoke on draft PRs

Alice invokes on draft PRs to get early feedback before formal review. Bob only invokes on
PRs marked "ready for review" because draft PRs change too much and review comments become
stale. If this were a shared auto-skill, it might trigger on Bob's draft PRs — producing
comments he doesn't want yet and that the author finds premature.

**Consequence:** Author confusion ("why is there a review on my draft?"), wasted token cost,
stale comments that need to be dismissed.

### Disagreement 2: Focus areas and severity threshold

Alice configures the skill to focus on correctness + security only (she reviews large PRs
and wants signal, not noise). Bob runs it with all categories because he reviews smaller PRs
where design feedback is valuable. A shared skill must pick one default — either Bob gets
noise on large PRs, or Alice misses design issues on small ones.

**Consequence:** One engineer's review quality degrades (either too noisy or too narrow).

### What they'd need to agree on before sharing

- Explicit trigger condition: only on "ready for review" PRs (not drafts)
- Default focus: all categories, with per-invocation override for narrowing
- Severity threshold: what counts as "blocking" vs "suggestion" — a shared definition
- Comment tone: both must be comfortable with the tone the skill uses on their PRs
- Approval gate: always present (no auto-posting to either's PRs without their OK)
