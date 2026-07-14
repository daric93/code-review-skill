# The code reviewer that reviews itself

*Why I put a test suite behind an AI code-review skill, how it works, and how I keep myself honest about what it's worth.*

---

## The prompt that quietly rots

The first version of my code-review skill was a prompt. A good one, I thought. It caught SQL
injection, spotted a missing timeout, wrote tidy comments. I shipped it and moved on.

Then a model update landed, and a week later the reviews felt thinner. Not broken, just softer.
Fewer real findings, a couple of confident remarks about code that was fine. I had no way to know
whether the skill had actually regressed or whether I was imagining it, because I had never written
down what "good" meant. There was no *before* to compare the *after* to.

That is the trap with prompts. They look like text, so we treat them like text: write once, tweak
by vibes, never test. But a review skill is not a blog draft. It makes the judgment calls a human
reviewer would otherwise make, and those calls drift as the model underneath them changes. If I
would never ship application code without tests, why was I shipping the thing that reviews the code
with nothing behind it?

So I stopped treating the skill like a prompt and started treating it like production code. It has
a test suite, a measured baseline, a graded rubric, and a feedback loop. This is how that fits
together, what it proves, and what it honestly can't.

## What the skill is actually for

It's worth being clear up front about what this skill is, because it changes what "does it work?"
even means.

The skill is not a cleverer way to ask a model "is there a bug here." Any strong model will find an
obvious bug in a five-line snippet. The skill is the machinery *around* that: it pulls the full PR
and the linked ticket, reads the changed files in context, applies the same written rulebook on
every single run, delegates a dedicated security pass, then runs each candidate finding through
precision gates (verify it against the real code, drop the style nitpicks, never post something it
can't prove) before it posts inline comments as a pending review I approve. Then it logs what it
found so the whole thing can learn from what it missed.

In other words, the value proposition was never "beat a base model at spotting textbook SQL
injection." It's consistency, precision, a complete review workflow, and a skill that improves from
real reviewer feedback instead of my mood that day. Keep that in mind, because it's exactly what a
naive eval fails to measure.

## What a reviewer is graded on

A reviewer fails in two directions, and most people only measure one.

The obvious one is **misses**. The review skips the injection, waves past the race condition,
doesn't notice the connection that never gets closed. Low recall. Easy to understand, easy to test.

The one everybody forgets is **false positives**. The review flags correct code, or pads a
three-line snippet with irrelevant nitpicks, and now the two real issues are buried under ten fake
ones. Low precision. This is the failure that actually kills a review tool, because a reviewer you
can't trust is worse than no reviewer at all. One hallucinated comment and the author stops reading
the rest.

So the eval gives both equal billing. For every category of bug the skill *should* catch, there is
a matching test of correct code it must *not* touch. Recall and precision trade off against each
other in the real world, and you have to watch both at once.

## How it works

The harness is [promptfoo](https://promptfoo.dev). Each test is a code snippet and one specific
expectation, like "identifies the race condition when `increment` is called concurrently." Both
halves run through `kiro-cli`: the skill generates the review, and a second call grades it. No
extra API keys, just my existing subscription acting as both author and examiner.

Grading is where most eval setups get lazy, so it's the part I care about most. Plain pass/fail
hides slow decay: a review that vaguely gestures at the bug "passes," and you never see quality
erode until it's bad. So every review is scored 1 to 5 and normalized to a 0-to-1 number. Five
means it named the issue precisely, explained the impact, and gave a correct fix with no noise.
Three means it half-mentioned the thing or gave a weak fix. One means it missed entirely, or, on a
"must not flag" test, invented the problem it was supposed to ignore. The pass line sits at 0.75, so
a review only clears the bar at a real four out of five. A mediocre three fails the gate *and* shows
up as a sagging score, which is exactly the early warning I lacked when my prompt quietly rotted.

Every test also carries a category tag, so results come back as a scorecard by dimension (security,
correctness, resilience, precision, and so on) instead of one averaged number that means nothing.

## Why I trust it, and why I still don't fully

Here's a real run from July 3rd, across 27 tests:

| Metric | Tests | Avg |
|---|---|---|
| correctness | 8 | 1.00 |
| resilience | 7 | 1.00 |
| security | 4 | 0.94 |
| false-positive-avoidance | 4 | 1.00 |
| resource-management | 2 | 1.00 |
| performance | 1 | 1.00 |
| licensing | 1 | 1.00 |

Twenty-seven for twenty-seven, which is precisely when I get suspicious. An all-green board is also
what a broken, too-lenient grader produces. A perfect score is not proof the skill is good; it might
be proof the exam is easy.

Two things keep me honest. First, the one imperfect score is the most useful cell on the board.
Security landed at 0.94 because the "hardcoded credential" test scored a four, not a five. The
grader's words: the review "identifies the hardcoded live API key, explains the impact clearly, and
provides two correct fixes using environment variables," but "does not explicitly recommend rotating
the exposed key." That's the rubric doing its job. A strong-but-incomplete review earns a four, not
a rubber stamp, and it tells me the exact sentence to add to make that dimension green.

Second, I built an eval for the eval. A separate skill,
[`grade-the-grader`](skills/grade-the-grader/SKILL.md), periodically audits the grader itself: too
lenient, too strict, wobbling run to run, or worst of all inverted on the negative tests so it
quietly rewards fabrication. An eval you never audit drifts just like a prompt does. The rule: if
the grader is broken, fix it before you believe a single trend line.

## The control, and the limit I'll own

A score on its own doesn't prove the *skill* did anything rather than the base model. The only way
to know is a control, so the suite ships two arms that differ by exactly one variable: same model,
same tests, same grader, with the skill's checklist and precision gates switched on, then off.

I ran the "off" arm on July 13th expecting a comfortable lift, and the bare model tied the skill:
seven for seven, every dimension at 1.00.

That result is not "the skill is useless." It's "these seven tests are too easy to tell the two
apart." They're clean, single-bug snippets, and a strong modern model solves those on its own. That
is a limitation of my test set, not a verdict on the skill, and it points straight at where the eval
needs harder material. Where the skill actually earns its keep, full multi-file diffs, a bug whose
twin two functions down went unpatched, escaping that's only wrong against the engine's real spec,
is exactly what a five-line snippet can't express.

And even on these trivial cases, the difference was visible in the *shape* of the answers, not the
score. On the negative `Optional[int]` test, a bare three-line fragment, the raw model passed the
criterion but couldn't stop itself:

> *"Two issues: 1. Missing `self` parameter... 2. Missing import for `Optional`... No other issues,
> the None guard before assignment is correct."*

It answered the real question correctly, then invented two out-of-scope nits about a fragment that
was never meant to be a complete module. The skill, on the same snippet, "concludes with no issues
found." That gap is the point. Multiply those two stray nits across every file in a real PR and you
get the noisy review nobody trusts. The precision gates exist to strip exactly that, and here is the
control showing, in the model's own output, what they strip.

So the baseline did its job. It stopped me from claiming a detection win I didn't earn, and it
proved the one thing I can measure at snippet scale, precision, is real. The rest of the skill's
value, the workflow and the consistency, lives in the loop below, where the real evidence is.

## The loop that actually improves it

The eval is a gate, not a teacher. It tells me when I've regressed; it doesn't tell me what to learn
next. For that I use the one source of truth I can't fake: what other reviewers catch on the same
pull requests I review.

When I review a PR and a maintainer flags something I missed, that miss is a real gap, not a
synthetic one. A companion skill logs it, along with false positives where someone pushed back on a
comment of mine and was right. Every few PRs, a retrospective step reads the log, finds the gaps that
show up in more than one PR, and only then edits the shared rulebook. A one-off stays a data point; a
pattern becomes a rule. Then the eval runs again to prove the change did what I claimed.

Two guardrails stop this from overfitting. The sensors that log gaps can't edit the rules; only the
retrospective does, and only on recurrence, so one reviewer's pet peeve never becomes doctrine. And
no rule change is trusted until the eval re-run backs it up: a miss becomes a failing test first, and
the rule is what turns it green.

## Where it needs to get better

I won't pretend this is finished.

The unit tests are too easy, and the tied baseline proved it. The fix is harder cases: multi-file
diffs, sibling-parity bugs, escaping validated against a real query engine, the context a snippet
can't carry. That's where the skill should beat a bare model, and it's where I need to be running the
comparison next.

The green board is a standing risk. Until the suite has cases the skill genuinely struggles with, a
perfect score says more about the difficulty of the exam than the strength of the student. The cure
is adding failing tests on purpose, drawn straight from real review misses.

And the loop only works if I run it. The feedback system is worthless the week I get busy and stop
logging gaps. The mechanism is built; the discipline is on me.

## The takeaway

The skill's job was never to out-detect a base model on a five-line snippet. It's to turn a
one-off, mood-dependent prompt into a consistent, precise, full-workflow reviewer that gets better
from real feedback, and the eval is how I keep that honest instead of hopeful.

The 27 out of 27 isn't the achievement, and the tied baseline isn't the failure. Both are the
system working: one telling me to write harder tests, the other stopping me from claiming a win I
didn't earn. The real payoff is quiet. The next time the skill regresses, from a model bump or a
rule that got too aggressive, I'll see it as a specific number dropping on a specific dimension and
catch it in an eval run, instead of discovering it in a review I already posted.

That's the difference between a prompt and production code. Not that it's perfect. That when it
breaks, you find out first.
