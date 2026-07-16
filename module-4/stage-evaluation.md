# AI Adoption Stage Evaluation

Scored against "what someone would observe watching me work the past 30 days" — actual, not
aspirational. A = 1, B = 2, C = 3, D = 4.

## Per-Question Scores

### Dimension 1: Prompt Engineering & AI Interaction
- **Q1** (last 3 unshippable outputs): **D** — I encode fixes into persistent artifacts. When
  the reviewer missed a class of bug, I added a checklist rule + eval test so it would not recur
  (2026-07-02 commit), then verified on similar inputs via the eval.
- **Q2** (instruction setup): **D** — version-controlled skill files + shared checklist;
  `_shared/review-checklist.md` distinguishes real rules from domain debt not to replicate.
- **Q3** (times modified an instruction artifact in 30 days for quality): **D** — 6+; the
  iteration log and retro commits show repeated skill/checklist edits.
- **Sum: 12 → avg 4.0**

### Dimension 2: Task Agents & Single-Box Automation
- **Q4** (workflow as boxes/arrows): **D** — documented as the sensor → orchestrator →
  sensor flow; gap-analyzer is an agent box with defined done.
- **Q5** (most frequent AI task): **C** — I hand review to a skill with defined standards and
  review against a definition of done. Not fully D (not *every* box has a dedicated agent).
- **Q6** (last wrong delegated output): **D** — I can name specific failure modes (missed
  fix-verification in re-review, silent-truncation miss) each encoded into rules, not memory.
- **Sum: 11 → avg 3.67**

### Dimension 3: Workflow Orchestration & Coordination
- **Q7** (handoff between steps): **C** — the retrospective orchestrates gap-analyzer per
  entry; output feeds forward via the findings file + log contract. Not D (I still trigger the
  retro manually and review each stage).
- **Q8** (automated transitions): **C** — 1–2 reliably automated (retro → gap-analyzer
  dispatch, findings file → consumer). Working on more.
- **Q9** (quality checks): **C** — the promptfoo eval runs as an automated gate before I accept
  a prompt change. Not D (not multiple agents checking each other pre-review in the live flow).
- **Sum: 9 → avg 3.0**

### Dimension 4: Output Evaluation & Quality Judgment
- **Q10** (is output good enough): **C** — I evaluate against a defined rubric (the eval's
  recall + false-positive assertions). Approaching D but I do not yet track scores over time
  systematically across all work.
- **Q11** (documented "good enough"): **C** — written acceptance criteria in the test file and
  rubric assertions, applied consistently. Not fully D (not every output runs through automated
  eval — only the review skill).
- **Q12** (detecting quality drift): **C** — I have specific test cases I re-run; the eval is a
  repeatable harness. Edges toward D but I run it on change, not on a regular schedule.
- **Sum: 9 → avg 3.0**

### Dimension 5: Governance, Trust & Safety Nets
- **Q13** (three anti-patterns AI might replicate): **D** — maintained in
  `_shared/review-checklist.md` as explicit counter-rules; I have caught and prevented
  replicated debt (false-positive guards for Rust/async-CM patterns).
- **Q14** (what happens on sub-standard output): **C** — the eval gate runs on prompt changes;
  the findings-file hook validates structure. Not D (agents do not yet challenge each other's
  output automatically in the live flow before it reaches me).
- **Q15** (gate catches in 30 days): **C** — 1–3; the eval caught regressions during iteration
  (widened rubrics, resilience gaps). Honest: these were during program iteration, not
  independent production catches.
- **Sum: 10 → avg 3.33**

### Dimension 6: Trust & Working Identity
- **Q16** (output passes checks — then what): **C** — I spot-check key areas and trust gated
  output more than I used to; I do not re-read every line of a review that passed. Not D (still
  not fully hands-off).
- **Q17** (what do you do all day): **C** — I define tasks for skills, review output, focus on
  judgment calls. Not D (I still do plenty of direct work).
- **Q18** (how AI changed planning): **C** — I decompose work around what skills can handle vs
  what needs me. Not D (throughput increase is real but not "agents handle entire stages" across
  the board).
- **Sum: 9 → avg 3.0**

### Dimension 7: Team & Organizational Practices
- **Q19** (could a teammate pick up my setup): **C** — the skills are version-controlled with
  clear definitions; a competent teammate could use them with minimal explanation. The handoff
  checklist pass (Module 4 Step 1) was done specifically to make this true.
- **Q20** (team coordination on AI work): **B** — honestly, my setup is individual. I share
  approaches informally but there is no team-shared definition of done enforced by tooling.
- **Q21** (org governance tooling in workflow): **B** — guidelines/policy exist but are not
  automated checks plugged into my AI workflow.
- **Sum: 7 → avg 2.33**

## Score Table

| Dimension | Q# | Sum (3–12) | Average |
|---|---|---|---|
| 1. Prompt Engineering & AI Interaction | Q1–Q3 | 12 | 4.0 |
| 2. Task Agents & Single-Box Automation | Q4–Q6 | 11 | 3.67 |
| 3. Workflow Orchestration & Coordination | Q7–Q9 | 9 | 3.0 |
| 4. Output Evaluation & Quality Judgment | Q10–Q12 | 9 | 3.0 |
| 5. Governance, Trust & Safety Nets | Q13–Q15 | 10 | 3.33 |
| 6. Trust & Working Identity | Q16–Q18 | 9 | 3.0 |
| 7. Team & Organizational Practices | Q19–Q21 | 7 | 2.33 |
| **TOTAL** | | **67** | **3.19** |

## Stage Mapping

Total **67** falls in the **59–74 band → "Approaching Workflow" (~Stage 4)**.

A caveat on honesty: the DLP target is Stage 3 (43–58), and I want to be careful not to
over-claim. My total sits above that band, driven mostly by Dimension 1 (4.0) and Dimension 2
(3.67), which reflect genuine long-standing practice with the review skill family — this
predates the program. But the guide is explicit that Stage 4 "cannot be meaningfully
self-assessed" because it requires team-context evaluation. My Dimension 7 score (2.33) is the
honest counterweight: my orchestration and governance are real but *individual*, not team-shared.
So I read my result as "solid Stage 3 personal practice with some Stage 4 orchestration habits,
gated by a genuine team-adoption gap" — not as a claim to Stage 4.

## Two-Paragraph Reflection

**Which dimension surprised me most?** Dimension 5 (Governance), which scored higher than I
expected at 3.33. I had thought of my anti-pattern counter-rules and eval gates as just "part of
the review skill," but the assessment made me see them as genuine governance: I maintain an
explicit list of debt patterns the AI should not replicate (the false-positive guards), and I
have caught real instances of the reviewer about to replicate them. What kept it from being
higher is honest — Q14/Q15 want *automated agents challenging each other* before output reaches
me, and my live flow does not do that yet; the eval gate fires on prompt changes, not on every
review output. The surprise was realizing I was underselling the governance I already have while
correctly identifying the automation ceiling I have not reached.

**What single behavior change would move my lowest dimension (7, Team) up a letter?** Sharing
the review skill family as a *team-owned* artifact with a collective definition of done — putting
the skills and shared checklist somewhere my delivery team pulls from, with changes going through
team review rather than living as my personal configuration. That one change would move Q19 to
solid C/D (already close), Q20 from B toward C (shared standards, even if not yet tooling-
enforced), and begin on Q21. Everything technical is in place; the gap is purely that adoption
stops at me. That is the meaningful signal the low score reveals — the program built personal
practice, and team adoption is the next investment, exactly as the guide predicts.
