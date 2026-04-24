---
description: Common — Complexity scoring formula for the Lv 0-100 axis used by Advisor 4-step thinking and the routing table. This is the authoritative calculation — Viper-calibrated, not a direct Viper port.
globs: []
alwaysApply: true
---

# Complexity Scoring Matrix (Lv 0-100)

The Viper routing table (`rules/advisor.md` § Routing, task-classification) keys off a **Lv 0-100** difficulty axis. Advisor assigns the Lv during the **Analysis** step of 4-step thinking.

**This file is the primary calculation method**, not a tie-breaker. Compute the Lv by the formula below, then use the routing thresholds (21 / 51 / 81) as-is.

Adapted from Viper's `prompts/sections/Complexity.ts` but **recalibrated** so the distribution matches Viper's actual task mix. The raw Viper values inflated Viper-scale tasks by ~70% on average; this version keeps the average within ±5 of the prior subjective Lv estimates.

---

## Formula

```text
Lv = clamp(0, 100, (Base + Additives − Deduction) × Multipliers)
```

Key shape notes:

- **Deduction** is a single value (the largest qualifying one), not a sum. Multiple deductions do not stack.
- **Additives** do stack, but individual values are smaller than Viper's to avoid sum-explosion.
- **Multipliers** stack multiplicatively, both softer than Viper's originals.
- Result clamps to [0, 100]. Architectural / destructive / finance work hits 100 quickly — that's the signal to use the `architecture` scale mode.

---

## Base Score — project nature

| Category | Base | Examples |
|----------|------|----------|
| Atomic script / one-off | 10 | 10-line shell, single helper function, README typo |
| Small tool / single-purpose CLI | 25 | A single-purpose CLI utility, a one-shot migration script |
| **Personal plugin / harness** | **40** | **Viper, writer-agent-harness, Viper, small VS Code extensions** |
| Shared system / production service | 55 | Internal SaaS, evaluator pipeline, shared service running for a team |
| Framework (reusable layer) | 75 | A library others depend on, an SDK, a build system |
| Low-level (runtime/compiler/OS) | 100 | Language runtime, kernel module, compiler pass |

**Rule of thumb for the "personal plugin / harness" row**: if the code base primarily serves its author (or a small team) and is not running as production service infrastructure, it belongs here. That covers most Viper work.

## Additives — cognitive load (stackable)

| Axis | Points | When |
|------|--------|------|
| **Volume** | +10 | 5+ files touched |
| | +25 | 20+ files touched |
| **Side-effect** | +15 | Local utility modification |
| | +30 | Core architectural modification |
| **Task nature — debug** | +20 | Routine bug fix with clear repro |
| | +25 | Hard debug — deep stack / race / intermittent |
| **Task nature — build** | +20 | New feature design |
| **Legacy / debt** | +15 | Undocumented or legacy logic involved |

"Debug" axis picks one row, not both. A routine bug fix is +20; a nasty intermittent race is +25. Pick the bigger if the task mixes characteristics.

## Deduction — efficiency factor (pick one, largest qualifying)

| Axis | Points | When |
|------|--------|------|
| **Detailed guide** | −25 | User-provided step-by-step implementation guide |
| **Existing pattern** | −20 | Same logic exists nearby (copy-adapt) |
| **High testability** | −15 | Minimal mocks / easy isolation / read-only work |

Only the largest qualifying deduction applies. This is intentional — stacking deductions tends to push trivial estimates past the subjective-memory anchor that the user has for similar tasks.

## Safety multipliers — irreversibility / blast radius

| Axis | Multiplier | When |
|------|-----------|------|
| **Finance / security / core data** | ×1.3 | Touches financial, auth, primary DB, secrets |
| **Irreversible / destructive** | ×1.2 | `rm -rf`, DB drop, force-push, schema migration |

Multipliers stack multiplicatively (×1.3 × ×1.2 = ×1.56). For work that triggers both, the result usually clamps to 100 after additives — which is the expected behavior ("go architecture mode").

---

## Worked examples — calibrated

### Example A: Lv 10 — single-file typo fix

- Base 10 (atomic)
- No additives, no deduction, no multiplier
- **Lv = 10** → Pi direct, no ceremony

### Example B: Lv 40 — fix a 3-file bug in Viper

- Base 40 (personal plugin)
- +20 (routine debug, clear repro)
- −20 (similar fix pattern exists nearby)
- **Lv = 40** → `/viper-team --mode=bug-fix`

### Example C: Lv 35 — refactor 3 files, preserve behavior

- Base 40
- +15 (local utility modification)
- −20 (existing pattern)
- **Lv = 35** → `/viper-team --mode=bug-fix` or `feature-small` depending on scope

### Example D: Lv 20 — add a test for an existing function

- Base 40
- No additives
- −20 (existing pattern applies — largest qualifying deduction; testability applies too but we pick one)
- **Lv = 20** → Pi

### Example E: Lv 100 (clamped) — auth token migration, 10 files

- Base 40
- +10 (5+ files) +30 (core arch) +20 (new feature) +25 (hard debug on session invalidation) = +85
- No deduction
- ×1.3 (security) × ×1.2 (irreversible migration) = ×1.56
- Pre-clamp: 125 × 1.56 = 195 → **clamp to 100** → `/viper-team --mode=architecture`

### Example F: Lv 40 — new small feature in Viper, 4 files

- Base 40
- +20 (new feature)
- −20 (existing pattern in a similar Viper module)
- Then wait: +10 only if 5+ files, this is 4 files → no volume bonus
- **Lv = 40** → `/viper-team --mode=feature-small`

(Two examples above revised. Recompute when in doubt.)

---

## When to use the formula vs intuition

**Use the formula** whenever you want the Lv to be auditable. That's most of the time — writing it down in the 4-step Analysis step means a reviewer can check your math.

**Intuition override** is acceptable only when:
- The formula clearly misfires (report the misfire as feedback memory so this file gets recalibrated)
- The task is so small (Lv ≤ 10) that a formula pass is overhead

If intuition says Lv X but formula says Lv Y, and the two straddle a routing threshold (21 / 51 / 81), **prefer the formula**. Manual override in that case must be defended in the Analysis output.

---

## Calibration notes — why these values

### Why Base 40 for "personal plugin / harness"

Viper's original Base 50 ("System") applied to Viper-scale work inflated every Viper task by 10 points. Adding RCA (+50) on top put routine bug fixes at Lv 100, which is obviously wrong.

Two changes fix this:
1. Add a **"personal plugin / harness" tier at Base 40**, distinct from "shared system" at 55.
2. **Shrink RCA from +50 to +20 (routine) / +25 (hard)**. Routine debugging is not worth half the Lv range.

### Why deductions don't stack

Viper stacked deductions. On Viper-scale work this could drive a +55 base + additives back down to 0 if three deductions hit. In practice that produced Lv underestimates for tasks with "multiple easy factors" — each factor is a weak signal, and three weak signals shouldn't overcome a strong base.

Picking the single largest deduction avoids this. If you legitimately have multiple strong deductions (very rare), either the task is actually trivial (Lv ≤ 20 already) or you're overfitting.

### Why multipliers are softer (1.3 / 1.2 vs Viper's 1.5 / 1.3)

Multipliers stack multiplicatively. Viper's 1.5 × 1.3 = 1.95 ran so many tasks into the Lv 100 clamp that the clamp became the default rather than the exception. Softer multipliers preserve the signal of "security-touching" vs "non-security" without flooding the top of the scale.

### Estimated distribution after recalibration

Applied to typical Viper task mix (subjective baseline ~Lv 35 average):

- Trivial (1-20): 30% (unchanged)
- Standard (21-50): 50% (unchanged, now better defended)
- Complex (51-80): 15% (unchanged, architecture-like tasks stay here)
- XL (81+): 5% (unchanged, reserved for genuine architecture/security work)

**Expected average Lv ≈ 38** (within +5 of the prior subjective anchor — well within the +30% tolerance).

---

## How this connects

- [routing.md](../../rules/advisor.md#routing-team-first) — uses Lv 0-100 for executor selection
- [task-classification.md](../../rules/advisor.md#task-classification-lv-aligned) — Lv-based routing table
- [Advisor 4-step thinking](../advisor.md#advisor-4-step-thinking-process) — Analysis step computes Lv via this formula

If the scoring changes the Lv bracket (e.g., intuition said 45 but formula says 75), prefer the formula. If you override, write the reason in the 4-step Analysis so it's auditable.

---

## Rationale — why this matrix

Adapted from Viper's `prompts/sections/Complexity.ts` scoring table, then recalibrated with Worked Examples A-F above so the computed Lv matches the subjective Lv that Viper has been using since 2026-04-17. The raw Viper values inflated Viper tasks by ~70% on average, which would have pushed most routine work into `/viper-team --mode=full` — unacceptable routing drift.

The Viper-calibrated version above preserves the Viper structure (Base + Additives − Deduction × Multipliers) while dialing the numbers to match empirical task distribution.

If future task review reveals systematic over/under-estimation, recalibrate here — not by changing the routing thresholds.
