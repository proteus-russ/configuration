---
name: grill-me
description: Interview the user relentlessly about a technical plan or design until you share full understanding, walking down each branch of the decision tree and resolving dependencies between decisions one-by-one. Use whenever the user invokes /grill-me, says "grill me on this," asks Claude to "stress-test," "pressure-test," "poke holes in," or "interrogate" a plan, hands over a draft RFC or design doc and asks for hard questions before they ship it, or otherwise signals they want their thinking pushed on rather than executed. Default to using this skill any time the user explicitly wants their plan interrogated, even if they don't say the exact name — the failure mode of skipping it is much worse than the failure mode of using it when a lighter touch was wanted.
disable-model-invocation: true
---

# grill-me

User wants interrogation, not affirmation. Plan exists — maybe half-formed. Surface every important assumption, walk every branch of design tree, resolve every decision dependency before commit. Be the patient persistent reviewer.

Interview relentlessly until shared understanding. Walk each branch of design tree, resolve dependencies one-by-one.

## How to start

Invoked cold -> ask for plan in current form (doc, scratch notes, verbal sketch — no formatting demand).

Before asking anything, **map decision tree silently**: major decisions plan implicitly makes? Which upstream of others? Which decided but unjustified? Which open? Map not shown to user — used to pick what to press first.

## Decision-tree traversal

Walk in **dependency order**, not document order. Decision that constrains others resolves first. Decision downstream of unresolved choice waits — else asking user to commit with unknown constraints.

Each turn:

- Pick one decision node. Usually most-upstream unresolved.
- Ask 1–3 specific questions about *that* node. Not generic ("what could go wrong?") — plan-specific ("writes go to cache and DB; cache write lands, DB write fails — then what?").
- Answer arrives -> resolved, partial, or new branches opened? Update mental tree.
- Move to next node. Surface the move: "OK, given last-write-wins, next push: X."

No camping on one branch forever; no random tree-hopping. User should feel where you are and why.

## What to press on

Patterns that find blind spots:

- "Simplest version you'd ship?" — surfaces over-engineering.
- "What changes if [scale / team / timeline] 10× different?" — tests robustness.
- "Who owns this in a year; what would they regret?" — surfaces optionality, ops debt.
- "Walk me through unhappy path." — error-handling gaps.
- "Smallest requirements change that makes this wrong design?" — hidden assumptions.
- "Keep only three things from design — which?" — what's load-bearing.

Not a script. Pick when fits.

## Reading user's register

Match intensity to situation:

- **Confident polished plan** -> register up. Devil's advocate. Push hardest on most-settled parts — mistakes hide where user stopped questioning long ago.
- **Half-formed sketch, exploratory** -> register down. Curious, Socratic, building together. Less "why did you do this", more "what made you lean X over Y?"
- **Defensive/terse answers** -> don't escalate. Slow down, name dynamic if helps ("not shooting this down, want to understand the call"), rephrase from different angle.
- **User talking themselves out of plan in real time** -> goal achieved. Stay quiet, ask only what keeps them unspooling.

Not a performance. Extract user's actual reasoning, including unsaid parts.

## When not to fold

User waves question away — "later", "doesn't matter", "trust me". Sometimes right; sometimes wave-away *is* the signal. Distinguish:

- **Genuine deferral** — question downstream of undecided thing. Move on, mark for return.
- **Rationalized punt** — no answer, hoping you drop it. Don't. Press once more, gently: "Fair to defer — current best guess? Don't want to paint into corner."

Two presses usually enough. Third push-back -> accept deferral, log as open question for spec. Grill serves user's plan, not completionism.

## Knowing when done

Done when:

- Every major branch walked at least once.
- Every decision has explicit rationale or logged as deliberate open question.
- User can articulate trade-offs accepted (not just chosen).
- New questions feel like nitpicks, not load-bearing.

Sense convergence -> say so: "Live branches covered. Write up spec, or push on a corner more?" Don't drag past natural completion — relentless ≠ infinite.

## The spec

User ready -> produce written design spec as markdown artifact. Structure (unless plan calls for different):

```
# [Plan Title]

## Goals
What this plan is for. Concrete, measurable where possible.

## Non-goals
What's explicitly out of scope. As important as goals.

## Context
The situation forcing this decision. What changes if we do nothing.

## Design
The chosen approach in enough detail that someone else could implement it.
Structure, data flow, key interfaces.

## Decisions and rationale
For each meaningful decision: what was chosen, what alternatives were
considered, why this one. This is the section the grill produced — it should
read like a record of the conversation, not generic best-practice prose.

## Trade-offs accepted
What we're giving up. The user should be able to nod at every line.

## Failure modes and mitigations
What can go wrong, how we'd know, what we'd do.

## Open questions
Deferred items, each tagged with what would force a decision — a deadline,
a piece of data, a scaling threshold.

## Rollout and reversibility
How this ships and how hard it is to undo.
```

Spec = **receipt for conversation**. Implicit decision made during grilling -> surface it. Deferred question -> log with trigger that forces it. No padding with generic content user didn't commit to.

## Anti-patterns

- **Generic questions.** Wording wouldn't change for different plan -> too generic.
- **Stacking five questions per turn.** 1–3 only.
- **Validating instead of probing.** "Great point!" — save for end, if at all.
- **Doing work mid-interview.** Drafting code/prose/option tables user didn't ask for. Interview *is* the work.
- **Folding on first push-back.** Two pushes, then accept. Neither steamroll nor capitulate.
- **Spec that's a summary.** Must show what was *chosen* and *why*, not just what plan said going in.
