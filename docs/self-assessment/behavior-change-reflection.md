# Behavior Change Reflection

Honest answers to: is each artifact in my actual workflow, when did I last use it outside a
program exercise, and would I use it without this program?

## Per-Artifact

### pr-code-review skill

1. **Daily workflow or built-for-program?** Daily workflow. It predates this program — the
   version in `skills/pr-code-review/` has been my review tool for months. The certification
   `module-1/pr-code-review.md` is a re-derivation of it through EDD, not a new invention.
2. **Last used outside a program exercise?** The git history shows a retro-driven edit on
   2026-07-02 (commit 27b8e8a), two weeks before this program's first exercise (2026-07-15).
   That commit tightened the re-review "Resolved (code)" rule based on a real miss.
3. **Would I use it without the program?** Yes — I already did, and will continue. The program
   changed how I *maintain* it (test-first), not whether I use it.

### pr-code-review-gap-analyzer + pr-code-review-retrospective

1. **Daily workflow or built-for-program?** Daily workflow. These are the improvement engine I
   run on real PRs. They are not certification artifacts — they are the reason the review skill
   has improved over time.
2. **Last used outside a program exercise?** The 2026-07-02 commit is literally a retrospective
   output: "measure recurrence across the retained review-gaps-retro.md history." That is the
   retrospective skill doing its job on real review data.
3. **Would I use it without the program?** Yes. This loop existed before and drives real
   improvements independent of certification.

### promptfoo eval harness (module-1/pr-code-review-promptfoo.yaml)

1. **Daily workflow or built-for-program?** Mixed — honestly. I had an eval at
   `evals/pr-code-review/` before the program, but the program made me *expand* it (27 cases,
   two providers) and take the false-positive half seriously. The two-provider Model Ladder
   setup is new behavior from this program.
2. **Last used outside a program exercise?** The pre-program eval was used in the 2026-07-02
   tuning commit ("sharpen operator-parity rubric"). The expanded version is program-driven.
3. **Would I use it without the program?** The single-provider version, yes (I did). The
   two-provider Model Ladder discipline is a new habit I am still forming.

### Sentinel schema + hook (module-3)

1. **Daily workflow or built-for-program?** Built for the program. The *concept* maps to my
   real findings-file + review-log contract, but the standalone `validate-findings.sh` hook is
   a certification artifact, not something wired into my live setup yet.
2. **Last used outside a program exercise?** Not used outside the program.
3. **Would I use it without the program?** Possibly — formalizing the findings-file structure
   check would catch real corruption. But I have not adopted it into the live flow, and I
   should not claim I have.

## The Four Key Behaviors — Honest Assessment

### Do I write the test before the prompt?

**Now, mostly yes — but this program is what made it a default.** Before, I edited the review
skill first and backfilled eval cases when I remembered. The structural proof I have adopted it:
my gap-analyzer skill is *forbidden from editing prompts* and only adds failing tests, and
retrospective edits prompts only after those tests exist. I encoded test-first into the
architecture so I cannot skip it. But when I make a quick one-off prompt outside the review
domain, I still sometimes write prompt-first. Honest gap.

### Do I perform the load-bearing audit?

**On the review skill, yes. On everything else, not yet.** The Module 1 audit (removed 4
instructions) was genuinely useful — it cut dead weight I had accumulated. But I have not made
this a reflex for every prompt I write. It is a deliberate step I take on important artifacts,
not an instinct on all of them.

### Do I run the Model Ladder check?

**This is my weakest adopted behavior.** The program is the first time I ran the review prompt
against Haiku as well as Sonnet. The delta was 0 on the tuned test set, which I initially
found reassuring and then realized was mostly a sign the tests were tuned to those exact
inputs. I have NOT yet made two-provider evaluation a default when I build something new. This
is the behavior I most need to keep practicing.

### Has any artifact become part of a real workflow?

**Yes, unambiguously — the review family (pr-code-review + gap-analyzer + retrospective).**
This is not a workflow I built for the program; it is a workflow that existed and that the
program helped me formalize and test better. The 2026-07-02 retro commit is evidence it was
running on real work before the program began.

## Summary

The most honest framing: this program did not create my adoption — it *formalized and tested*
tools I already used. The review skill and its improvement loop are genuinely daily. What the
program newly instilled: test-before-prompt as an architectural rule, and the beginnings (not
yet the habit) of two-provider Model Ladder evaluation. The sentinel/hook is the one artifact I
built for the program and have not adopted — I say so rather than inflate it.
