# The code reviewer that reviews itself

*Why I put a test suite behind an AI code-review skill, how it works, and what it still can't tell me.*

---

## The prompt that quietly rots

The first version of my code-review skill was a prompt. A good one, I thought. It caught SQL
injection, spotted a missing timeout, wrote tidy comments. I shipped it and moved on.

Then a model update landed, and a week later I noticed the reviews felt thinner. Not broken,
just... softer. Fewer real findings, a couple of confident remarks about code that was fine. I had
no way to know whether the skill had actually gotten worse or whether I was imagining it, because I
had never written down what "good" meant. There was no before to compare the after to.

That is the problem with prompts. They look like text, so we treat them like text: write once,
tweak by vibes, never test. But a review skill is not a blog draft. It makes judgment calls that a
human would otherwise make, and those calls drift as the model underneath it changes. If I would
never ship application code without tests, why was I shipping the thing that reviews the code
without any?

So I stopped treating the skill like a prompt and started treating it like production code. It has
a test suite, a measured baseline, a graded rubric, and a feedback loop. This is the story of how
that fits together, and, just as importantly, where it falls short.

## What a reviewer is actually being graded on

Before writing a single test, I had to be honest about how a reviewer fails, because it fails in
two directions and most people only measure one.

The obvious one is **misses**. The review skips the injection, waves past the race condition,
doesn't notice the connection that never gets closed. Low recall. Easy to understand, easy to test
for.

The one everybody forgets is **false positives**. The review flags correct code, or pads a
three-line snippet with irrelevant nitpicks, and now the two real issues are buried under ten fake
ones. Low precision. This is the failure that actually kills a review tool, because a reviewer you
can't trust is worse than no reviewer at all. One hallucinated comment and the author stops reading
the rest.

So the whole eval is built around both axes. For every category of bug the skill *should* catch,
there is a matching test of correct code it must *not* touch. Recall and precision get equal
billing, because in the real world they trade off against each other and you have to watch both.

## How it works

The harness is [promptfoo](https://promptfoo.dev). Each test is a small code snippet and a single,
specific expectation, like "identifies the race condition when `increment` is called concurrently."
The nice part is that both halves run through `kiro-cli`: the skill generates the review, and a
second `kiro-cli` call grades it. No extra API keys, no separate billing, just my existing
subscription doing double duty as author and examiner.

The grading is where most eval setups get lazy, so this is the part I care about most. A plain
pass/fail hides slow decay: a review that vaguely gestures at the bug "passes," and you never see
quality erode until it's bad. Instead every review is scored on a **1 to 5 scale** and normalized
to a 0-to-1 number. Five means it named the issue precisely, explained the impact, and gave a
correct fix with no noise. Three means it sort of mentioned the thing or gave a weak fix. One means
it missed entirely, or, on a "must not flag" test, fabricated the problem it was supposed to ignore.
The pass line sits at 0.75, so a review only clears the bar at a genuine four out of five. A
mediocre three fails the gate *and* shows up as a sagging score, which is exactly the early warning
I was missing when my prompt quietly rotted.

Every test also gets a category tag, so the results come back as a scorecard by dimension
(security, correctness, resilience, precision, and so on) rather than one averaged number that
means nothing.

## Why I trust it (and why I still don't fully)

Here is a real run, from July 3rd, across 27 tests:

| Metric | Tests | Avg |
|---|---|---|
| correctness | 8 | 1.00 |
| resilience | 7 | 1.00 |
| security | 4 | 0.94 |
| false-positive-avoidance | 4 | 1.00 |
| resource-management | 2 | 1.00 |
| performance | 1 | 1.00 |
| licensing | 1 | 1.00 |

Twenty-seven for twenty-seven. Which is precisely when I get suspicious, because an all-green board
is also what a broken, too-lenient grader produces. A perfect score is not proof the skill is good.
It might be proof the exam is easy.

Two things keep me honest here.

The first is that the one imperfect score is the most useful data point on the board. Security came
in at 0.94 because the "hardcoded credential" test scored a four, not a five. The grader's own words:
the review "identifies the hardcoded live API key, explains the impact clearly, and provides two
correct fixes using environment variables," but "does not explicitly recommend rotating the exposed
key." That is the rubric working as intended. A strong-but-incomplete review gets a four, not a
rubber-stamp five, and it tells me the exact sentence to add if I want that dimension green.

The second is that I built an eval for the eval. A separate skill,
[`grade-the-grader`](skills/grade-the-grader/SKILL.md), periodically audits the grader itself: is it
too lenient, too strict, wobbling run to run, or, worst of all, inverted on the negative tests so it
quietly rewards fabrication? An eval you never audit drifts just like a prompt does. The rule I
follow is simple: if the grader is broken, fix the grader before you believe a single trend line.

## The control that told me the truth

A score on its own doesn't prove the *skill* did anything. Maybe the base model is just good and the
skill is decoration. The only way to know is a control, so the suite ships two arms that differ by
exactly one variable: same model, same tests, same grader, with the skill's checklist and precision
gates switched on, and then off.

I ran the "off" arm on July 13th, expecting to show a comfortable lift. Instead the bare model tied
the skill: seven for seven, every dimension at 1.00. No detection lift at all.

I could have buried that. I kept it, because it is the most instructive result I have. These test
snippets are deliberately clean, single-bug cases, and a strong modern model already solves those on
its own. A baseline that ties isn't a failure of the skill. It's the eval telling me these
particular tests don't discriminate on detection, so if the skill adds value, the value lives
somewhere these tests aren't looking.

And it does show up, just not in the pass/fail column. It shows up in the *shape* of the answers. On
the negative `Optional[int]` test, a bare three-line fragment, the raw model passed the criterion
but couldn't help itself:

> *"Two issues: 1. Missing `self` parameter... 2. Missing import for `Optional`... No other issues,
> the None guard before assignment is correct."*

It got the real question right, then invented two out-of-scope nits about a fragment that was never
meant to be a complete module. The skill, graded on the same snippet, "concludes with no issues
found." That gap is the whole point. On easy cases the difference between the skill and the raw
model isn't recall, it's the noise the skill refuses to emit. And noise is exactly what erodes trust
at scale.

So the baseline reframed my own eval for me: on trivial snippets its job is regression detection and
precision protection, not proving lift. Proving lift needs harder material, which brings me to the
part that isn't a unit test at all.

## The loop that actually improves it

The eval is a gate, not a teacher. It tells me when I've regressed; it doesn't tell me what to learn
next. For that I use the one source of truth I can't fake: what other reviewers catch on the same
pull requests I review.

When I review a PR and a maintainer flags something I missed, that miss is a real gap, not a
synthetic one. A companion skill logs it, along with the false positives where someone pushed back
on a comment of mine and was right. Every few PRs, a retrospective step reads the accumulated log,
looks for gaps that show up in *more than one* PR, and only then edits the shared rulebook. A
one-off stays a logged data point; a pattern becomes a rule. Then the eval runs again to prove the
change did what I claimed.

Two guardrails keep this from turning into overfitting. The sensors that log gaps are not allowed to
edit the rules; only the retrospective does that, and only on recurrence, so one reviewer's pet
peeve never becomes permanent doctrine. And no rule change is trusted until the eval re-run backs it
up: a miss becomes a failing test first, and the rule is what turns it green.

## Where this still needs to get better

I'm not going to pretend this is finished.

The unit tests are too easy, and the tied baseline proved it. The honest fix is harder cases:
multi-file diffs, bugs that only show up when you compare a change against its sibling code, the
kind of context a snippet can't carry. Those are the cases where a skill should beat a bare model,
and I'm not testing them yet.

The green board is a standing risk. Until the suite has cases the skill genuinely struggles with, a
perfect score tells me more about the difficulty of the exam than the strength of the student.
Adding failing tests on purpose, straight from real review misses, is the cure.

And the loop only works if I actually run it. The whole feedback system is worthless the week I get
busy and stop logging gaps after the PRs I review. The mechanism is built; the discipline is the
hard part, and it's on me.

## The takeaway

None of this is about the 27 out of 27. A perfect score on an easy test suite is not an
achievement, it's a warning to write harder tests. The real win is much smaller and much more
valuable: the next time the skill regresses, because of a model bump or a rule that got too
aggressive, I'll see it as a specific number dropping on a specific dimension, and I'll catch it in
an eval run instead of discovering it in a review I already posted.

That's the difference between a prompt and production code. Not that it's perfect. That when it
breaks, you find out first.
