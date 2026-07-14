# How I evaluate my AI skills and agents

*A prompt is code that makes judgment calls. Here's why I test it like code, how I do it, what the tests actually caught, and where I'm taking it next.*

---

## The prompt that quietly rots

The first version of my code-review skill was a prompt. A good one, I thought. It caught SQL
injection, spotted a missing timeout, wrote tidy comments. I shipped it and moved on.

Then a model update landed, and a week later the reviews felt thinner. Not broken, just softer.
Fewer real findings, a couple of confident remarks about code that was fine. I couldn't tell
whether the skill had regressed or whether I was imagining it, because I had never written down what
"good" meant. There was no *before* to compare the *after* to.

That is the trap with prompts, and with agents built out of prompts. They look like text, so we
treat them like text: write once, tweak by vibes, never test. But a skill is not a blog draft. It
makes the judgment calls a person would otherwise make, and those calls drift as the model
underneath them changes. If I would never ship application code without tests, why was I shipping
the thing that reviews the code with nothing behind it?

So I started treating my skills and agents like production code. The atomic ones get a real test
suite; the big multi-step agents get a different kind of check I'll come back to. This is how that
works, what it actually caught, and where it still falls short.

## Why evaluate skills and agents at all

Three reasons, in order of how much they've bitten me.

**Drift.** The model underneath every skill changes without warning. A prompt that was sharp last
month goes soft this month, and without a baseline you find out from a bad review you already
posted, not before.

**Two-sided failure.** A reviewer fails in two directions and most people only measure one. The
obvious one is *misses*: it skips the injection, waves past the race condition. The one everybody
forgets is *false positives*: it flags correct code, or pads a three-line snippet with irrelevant
nitpicks, and buries the two real issues under ten fake ones. The second failure is the one that
actually kills the tool, because a reviewer you can't trust is worse than no reviewer. One
hallucinated comment and the author stops reading.

**Not everything deserves the same test.** An atomic skill (review this code, escape this query)
has a checkable answer, so it earns a unit-style eval. A twelve-step agent that opens a PR,
responds to CI, and negotiates review comments does not — evaluating that end to end is expensive
and noisy, and the score wouldn't tell you which step broke. Those I improve through a
retrospective loop instead, driven by what real reviewers catch. Knowing which tool gets which
treatment is half the discipline.

## How I do it

For the atomic skills, the harness is [promptfoo](https://promptfoo.dev). Each test is a code
snippet and one specific expectation, like "identifies the race condition when `increment` is
called concurrently." Both halves run through `kiro-cli`: the skill generates the review, and a
second call grades it. No extra API keys, just my existing subscription acting as author and
examiner.

Grading is where most eval setups get lazy, so it's the part I care about most. Plain pass/fail
hides slow decay: a review that vaguely gestures at the bug "passes," and you never see quality
erode until it's bad. So every review is scored 1 to 5 and normalized to a 0-to-1 number. Five means
it named the issue precisely, explained the impact, and gave a correct fix with no noise. Three
means it half-mentioned the thing or gave a weak fix. One means it missed entirely, or, on a "must
not flag" test, invented the problem it was supposed to ignore. The pass line sits at 0.75, so a
review only clears the bar at a genuine four. A mediocre three fails the gate *and* shows up as a
sagging score, which is exactly the early warning I lacked when my prompt quietly rotted.

Every test carries a category tag, so results come back as a scorecard by dimension (security,
correctness, resilience, precision) instead of one averaged number that means nothing. And crucially
the suite ships two arms that differ by exactly one variable: the same tests, same grader, same
model, with the skill's checklist and precision gates switched **on**, then **off**. The "off" arm
is the control. Without it, a good score might just mean the base model is good and the skill is
decoration.

## What the tests actually caught

Here's a real run from July 3rd, skill on, across 27 tests. Twenty-seven for twenty-seven, every
dimension at or near 1.0, with security at 0.94.

Which is exactly when I get suspicious. An all-green board is also what a broken, too-lenient grader
produces. A perfect score isn't proof the skill is good; it might be proof the exam is easy. Two
things turned that suspicion into evidence.

**The control did its job.** I ran the "skill off" arm against the same 27 tests. The bare model
scored 25 of 27, and the gap landed exactly where the checklist carries knowledge a raw model
doesn't reliably have:

- *Retry and backoff on a transient call.* The snippet publishes to a queue with no retry. The bare
  model wrapped the exception and re-raised it, and the grader scored it **0.25**: "never
  specifically identifies the transient failure / retry / backoff problem." With the skill's
  resilience checklist, the same case scored **1.0**.
- *Silent truncation.* A query hardcodes `LIMIT 0, 10000`. The bare model flagged it, but as a
  performance and memory concern, and scored **0.75**: it "frames the issue purely as a
  performance/memory problem rather than a data truncation / silent data loss risk." The checklist
  treats a silent cap that drops caller data as a correctness bug, not a perf safeguard, so with the
  skill it scored **1.0**.
- *Escaping the right context.* Code strips only double quotes before building a search-engine
  phrase query. The bare model got partway and scored **0.75**; the skill's rule about distinct
  escape contexts for each field type took it to **1.0**.

So the per-dimension deltas, skill minus baseline, are real where it matters: resilience +0.11,
security +0.06, correctness +0.03, and a tie on the categories where a strong model already does
fine. Not a landslide, but honest, and pointed at precisely the checks I wrote the checklist for.

**The one imperfect skill score was the most useful cell on the board.** Security landed at 0.94,
not 1.0, because the "hardcoded credential" test scored a four. The grader's words: the review
"identifies the hardcoded live API key, explains the impact clearly, and provides two correct fixes
using environment variables," but "does not explicitly recommend rotating the exposed key." That's
the rubric working. A strong-but-incomplete review earns a four, not a rubber stamp, and it tells me
the exact sentence to add.

There's a precision story too, not just detection. On a negative test, a correct three-line
`Optional[int]` fragment, the bare model passed the criterion but couldn't stop itself: "Two issues:
1. Missing `self` parameter... 2. Missing import for `Optional`..." It invented two out-of-scope
nits about a fragment that was never meant to be a whole module. The skill, on the same snippet,
"concludes with no issues found." Multiply those two stray nits across every file in a real PR and
you get the noisy review nobody trusts. The precision gates exist to strip exactly that.

## The bonus lesson: grade the grader

One test embarrassed the harness in a useful way. On the first full baseline run, the tag-injection
security test scored **0** with the note "Could not extract JSON from llm-rubric response." Not a
model miss, a grader parsing failure. On a clean re-run the same answer scored **1.0**.

That's why I have an eval *for the eval*. A separate skill,
[`grade-the-grader`](skills/grade-the-grader/SKILL.md), periodically audits the grader itself: too
lenient, too strict, wobbling run to run, or worst of all inverted on the negative tests so it
quietly rewards fabrication. An eval you never audit drifts just like a prompt does. The rule I
follow: if the grader is broken, fix it before you believe a single trend line. That stray 0 would
have looked like a real regression if I'd trusted the number instead of reading the reason.

## The loop for the things a unit test can't reach

The eval is a gate, not a teacher. It tells me when I've regressed; it doesn't tell me what to learn
next, and it can't touch the full multi-file, multi-step review at all. For that I use the one
source of truth I can't fake: what other reviewers catch on the same pull requests I review.

When a maintainer flags something I missed, that miss is a real gap, not a synthetic one. A
companion skill logs it, along with false positives where someone pushed back on a comment of mine
and was right. Every few PRs, a retrospective step reads the log, finds the gaps that show up in more
than one PR, and only then edits the shared rulebook. A one-off stays a data point; a pattern becomes
a rule. Then the eval runs again to prove the change did what I claimed.

Two guardrails keep it from overfitting. The sensors that log gaps can't edit the rules; only the
retrospective does, and only on recurrence, so one reviewer's pet peeve never becomes doctrine. And
no rule change is trusted until the eval re-run backs it up: a miss becomes a failing test first, and
the rule is what turns it green. This is also how I "evaluate" the big agents that are too expensive
to unit-test end to end. I don't score the whole pipeline; I let real usage surface the gaps and
feed them back in.

## Where I'm taking it next

I'm not going to pretend this is finished.

The snippet tests are still too easy on the categories where the base model is strong, which is why
half my dimensions tie the baseline. The fix is harder cases: real multi-file diffs, a bug whose
twin two functions down went unpatched, escaping validated against an actual query engine, the
context a five-line snippet can't carry. That's where the skill should pull further ahead, and it's
the next batch of tests I owe the suite.

The green board stays a standing risk. Until the suite has cases the skill genuinely struggles with,
a perfect score says more about the exam than the student. The cure is adding failing tests on
purpose, drawn straight from real review misses.

And the loop only works if I run it. The whole feedback system is worthless the week I get busy and
stop logging gaps after the PRs I review. The mechanism is built; the discipline is on me.

## The takeaway

Evaluating a skill isn't about the 27 out of 27. A perfect score on an easy suite is a warning to
write harder tests, not a trophy. The value is in the specifics the eval surfaced: the bare model
missing a retry, softening a data-loss bug into a perf note, over-nitpicking a fragment, and a grader
that dropped a score for the wrong reason. Each of those is a concrete thing I can fix or defend.

That's the difference between a prompt and production code. Not that it's perfect. That when it
breaks, you find out first, and you can point at exactly what broke.
