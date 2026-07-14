# How I evaluate my AI skills and agents

*A prompt is code that makes judgment calls. Here's why I test it like code, how I do it, what the tests actually caught (including a bug in one of my own tests), and where I'm taking it next.*

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
works, what it caught, and where it still falls short.

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
responds to CI, and negotiates review comments does not: evaluating that end to end is expensive
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

## What the control actually showed

Here's the head-to-head across 29 tests, same day, same model, skill on versus skill off:

| | Passed (≥4/5) |
|---|---|
| **Skill on** | 29 / 29 |
| **Skill off (bare model)** | 27 / 29 |

Two failures out of 29 doesn't sound like much until you look at *where* the bare model fell short
and by how much. The gap lands exactly on the checks the skill's checklist exists to enforce:

- **Retry and backoff on a transient call.** A snippet publishes to a queue with no retry. The bare
  model wrapped the exception and moved on, and the grader scored it **0.25**: it "never explicitly
  identifies that transient failures will cause outright failure with no retry or backoff." With the
  skill's resilience checklist, the same case scored **1.0**.
- **Silent truncation.** A query hardcodes `LIMIT 0, 10000`. The bare model flagged it, but framed
  it "entirely as a performance/memory risk," not as silent data loss that drops customer rows with
  no warning. **0.25** bare, **1.0** with the skill, which treats a silent cap as a correctness bug.
- **Over-flagging correct Rust.** On a *negative* test, the bare model invented a signed/unsigned
  concern about `max_connections` that the code already guards, "bordering on fabricating a
  vulnerability." **0.75** bare, **1.0** with the skill's verify-before-flag gate.

Averaged by dimension, the deltas are honest and pointed: resilience +0.14, false-positive-avoidance
+0.10, correctness +0.09, and a tie on security and the categories where a strong model already does
fine. Not a landslide. Real, and concentrated precisely on the rules I wrote.

That "tie on the easy stuff" is the important caveat. Both arms run the same model, so on textbook
cases (a plain SQL injection, an N+1 loop) the base model already scores a perfect 5 and the skill
cannot beat it. The skill earns its keep on the cases that need specific knowledge or discipline the
model won't reliably supply on its own. A control that ties on easy tests and separates on hard ones
is the control working, not failing.

## The graded rubric, catching incompleteness

In an earlier run, one skill-on security test came in at four out of five instead of five. The
review of a hardcoded API key "identifies the hardcoded live API key, explains the impact clearly,
and provides two correct fixes using environment variables," but "does not explicitly recommend
rotating the exposed key." A binary pass/fail would have called that a win and moved on. The graded
rubric docked it a point and told me the exact sentence to add. That is the whole reason I grade 1
to 5 instead of pass/fail: it sees the difference between good and complete.

## The test that was wrong (and why that's the point)

Here's the part I didn't plan for, and the best argument for the whole approach.

To measure precision, I added a "must not flag" test: a small pure function the reviewer should
leave alone. My first version was a `to_snake_case` helper. The bare model "failed" it by flagging
bugs, and I almost logged that as a precision win for the skill.

Then I actually read the grader's reasoning. The bare model had pointed out that the function
doubles underscores on input that already contains them (`foo_Bar` becomes `foo__bar`) and splits
acronyms character by character. It was right. My "correct" function wasn't correct. The bare model
had caught a real edge case, and my skill had "passed" the test by staying silent, which meant it
had *missed* the bug and my rubric had rewarded it for the miss.

The test didn't make sense, so I replaced the snippet with a genuinely bulletproof pure function (a
Celsius-to-Fahrenheit conversion, no edge cases, no I/O) and re-ran. Now the skill scores a clean
1.0 and the bare model a 0.75, docked for tacking on an optional type-check note the typed signature
made unnecessary. A fair result on a fair test.

I could have shipped the broken test and a flattering number. The eval, and the habit of reading the
reason instead of the score, stopped me. That is exactly what evaluation is for: not to manufacture
a win, but to keep me honest, including about my own tests.

## The bonus lesson: grade the grader

One test embarrassed the harness in a useful way earlier: a security case scored 0 with the note
"Could not extract JSON from llm-rubric response." Not a model miss, a grader parsing failure. On a
clean re-run the same answer scored 1.0.

That's why I have an eval *for the eval*. A separate skill,
[`grade-the-grader`](skills/grade-the-grader/SKILL.md), periodically audits the grader itself: too
lenient, too strict, wobbling run to run, or worst of all inverted on the negative tests so it
quietly rewards fabrication. An eval you never audit drifts just like a prompt does. If the grader
is broken, fix it before you believe a single trend line. That stray 0 would have looked like a real
regression if I'd trusted the number instead of reading the reason.

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
the rule is what turns it green. This is also how I handle the big agents that are too expensive to
unit-test end to end. I don't score the whole pipeline; I let real usage surface the gaps and feed
them back in.

## Where I'm taking it next

I'm not going to pretend this is finished.

The snippet tests still tie on the categories where the base model is strong, which caps how much
lift a single-file test can show. The real separation lives in cases a five-line snippet can't
carry: multi-file diffs, a bug whose twin two functions down went unpatched, escaping validated
against an actual query engine. When I added a sibling-parity test (one search method escapes user
input, its twin doesn't), both arms caught it, because the two methods still fit in one snippet. The
harder version, where the unescaped twin is in another file, is the next thing I owe the suite.

The green board stays a standing risk. Until the suite has cases the skill genuinely struggles with,
a perfect score says more about the exam than the student. The cure is adding failing tests on
purpose, drawn straight from real review misses.

And the loop only works if I run it. The whole feedback system is worthless the week I get busy and
stop logging gaps after the PRs I review. The mechanism is built; the discipline is on me.

## The takeaway

Evaluating a skill isn't about the 29 out of 29. A perfect score on an easy suite is a warning to
write harder tests, not a trophy. The value is in the specifics the eval surfaced: the bare model
missing a retry, softening a data-loss bug into a perf note, over-flagging correct Rust, a grader
that dropped a score for the wrong reason, and a "correct" test snippet that turned out to have a
real bug in it. Every one of those is a concrete thing I could fix or defend.

That's the difference between a prompt and production code. Not that it's perfect. That when it
breaks, whether it's the skill, the grader, or the test itself, you find out first, and you can point
at exactly what broke.
