---
description: Common — Viper engineering philosophy. High-level user intent (vibe) on input, mechanical safety checks (rigor) on output. Not a trade-off; the two operate at different layers.
globs: []
alwaysApply: true
---

# Vibe-and-Rigor — the Viper engineering stance

Viper inherits this stance from Viper's "Vibe Coding + Ouroboros" principle. The short version: **maximum input freedom, maximum output discipline, and they don't conflict**.

---

## The two layers

### Input layer — vibe

The user states intent in natural language, at the level of abstraction that makes sense to them. Short or long. Precise specification or hand-wavy goal. Either is valid input.

Viper does NOT require:
- Formal requirements docs
- Pre-agreed APIs
- Enumerated edge cases
- Step-by-step task plans

If the user has those, great. If not, Advisor elicits what it needs — one clarifying question at a time, never a questionnaire.

### Output layer — rigor

Before Viper declares work done, every mechanical check that can run **does** run:

- **Lv assessment** — `complexity-matrix.md` formula when the value isn't obvious
- **4-step thinking** — Analysis → Verification → Self-Correction → Plan (in `rules/advisor.md`)
- **Ping-pong plan review** — Codex critiques the plan before execution for Lv 21+
- **Cross-verify gate** — `/pi:cross-verify` on the diff after any code Write/Edit
- **Cross-family review gate** — `/codex:review` on the final state after any code Write/Edit
- **Execution contract** — `execution-contract.md` evidence list before declaring done
- **Feedback memory capture** — `episodic-feedback.md` when rework / surprise / repeated mistake happens

None of these require the user to ask. They are the default output discipline.

---

## Why it's not a trade-off

The common intuition is: "give the AI more freedom, get less reliable output — give the AI more constraints, lose the benefit of AI flexibility." Viper rejects this framing.

The resolution: **freedom and constraint operate on different surfaces**. Freedom is at the input surface (how the user describes the goal). Constraint is at the output surface (how Viper gates the result). The user doesn't feel the constraint because it happens after they state intent, before anything irreversible ships.

Concretely:

- The user says "fix the auth bug where tokens expire early" — a vibe-level goal.
- Viper does not demand a spec doc. It interprets, asks at most one clarifying question, and proceeds.
- Along the way, Codex reviews the plan, Pi cross-verifies the diff, the reviewer subagent audits the final state, the complexity matrix justifies why this was routed as Lv 45 vs Lv 60, and the execution contract confirms tests ran.
- The user sees: "I described a problem, it got fixed." The rigor was invisible to them.

The invisibility is the feature. Rigor that the user has to perform (write a spec, answer a questionnaire, approve each step) destroys the vibe. Rigor that the harness performs in the background preserves it.

---

## What this means for contributors and Advisors

### When adding a rule

Ask: does this rule make the user write more, or does it make Viper check more? Prefer the latter. A rule that says "user must always provide X" is usually a rule that should be "Advisor infers X from context, or asks one clarifying question if it can't."

### When reviewing output

Check that all the mechanical gates ran, not just the obvious ones. A `TaskUpdate(status="completed")` with no `/pi:cross-verify` evidence is incomplete regardless of how correct the code looks.

### When the gates get in the way

If a gate is frequently triggered but frequently ignored / overridden, the gate is wrong — either too loose (false positives create noise) or too strict (users route around it). Fix the gate, don't drop the principle. The bar is "rigor stays invisible to the user when it works." If rigor becomes visible, rigor is failing.

### When the user pushes against a gate

Listen first. The user may have information the gate doesn't (e.g., "this destructive migration is approved, apply it without the usual confirmation"). Gates exist to default-safe, not to block known-safe operations.

---

## Measure of success

A contribution isn't measured by lines of code generated or tasks completed. It's measured by whether the resulting system is **trustworthy, well-designed, and easy to change**. This is the same bar Viper cited ("software craftsmanship in the era of vibes") — Viper imports it intact.

Output rigor is the mechanism by which Viper earns that trust. Input vibe is why the user comes back.

---

## Related

- [roles.md](roles.md) — who enforces what (Advisor = output gate keeper)
- [complexity-matrix.md](complexity-matrix.md) — Lv assessment tool
- [execution-contract.md](execution-contract.md) — the declare-done evidence bar
- [episodic-feedback.md](episodic-feedback.md) — how gate failures feed back into learning
- [agent-evolution.md](agent-evolution.md) — where distilled lessons accumulate
