---
description: Common — Cache-safe agent self-refinement. Accumulated failure patterns + corrective tips per role, injected at session start only. Never mutates mid-session to protect prompt cache.
globs: []
alwaysApply: true
---

# Agent Evolution Tips

Viper's `EvolutionService` tracks per-agent success rate and auto-generates corrective tips for future spawns. Viper cannot reproduce the dynamic version because **any mid-session mutation of system prompt or rules breaks the prefix cache** (`routing.md` invalidation list).

This file is the Viper adaptation: a **static, session-start-only** evolution log. Advisor curates it manually (or during review passes); it's injected automatically as part of `rules/common/*`, so workers see it on spawn without any extra plumbing.

---

## Shape of an evolution tip

Each tip is a few lines describing one repeated failure mode of one role, plus the corrective instruction. Structure:

```markdown
### <role> — <short failure-mode title>

**Observed pattern**: <what keeps going wrong, 1-2 sentences>

**Correction**: <what to do instead, imperative, 1-2 sentences>

**Source**: <session id or feedback-memory filename where this was first observed>
```

Roles follow the Viper taxonomy: `advisor`, `architect`, `coder`, `debugger`, `reviewer`, `subagent` (one-shot general-purpose), or the specific agent name for custom team members.

---

## Current tips

*No tips yet. This file exists so the first tip has a home.*

---

## When to add a tip

Advisor adds a tip when:

1. A `feedback_*.md` memory entry points at a **role's recurring behavior** rather than a one-off decision. Example: "architect keeps proposing DDD layers without checking the actual repo layout" → architect tip, not a rule.
2. Same role fails the same way across **2+ distinct sessions** (the feedback memory exists + user mentions it again).
3. A `/viper-team` post-mortem identifies a worker behavior that the agent md didn't address.

Do NOT add a tip for:

- One-off errors (those belong in feedback memory, not here)
- User preferences for tone / verbosity (those belong in `user` memory)
- Behavior already covered in the agent's own md (update that instead)

---

## Why static, not dynamic

Viper's `proposeInstructionRefinement()` reads the log at each spawn and returns a dynamic tip string. Three reasons Viper doesn't do this:

1. **Cache invalidation** — rules/ and agent/ md files are part of the system prompt. If a tip string changes between two spawns of the same role, the second spawn misses cache (full write cost).
2. **Reproducibility** — dynamically-generated tips make session behavior non-deterministic. Two runs of the same task see different rules, which hurts debugging.
3. **Review gate** — dynamic tips skip human review. A bad tip (wrong lesson drawn from noise) propagates silently. Manual curation is a guard.

The trade-off: Viper evolution is **slower** than Viper's auto-loop. That's the price of keeping the cache stable.

---

## Review cadence

Approximately every 50 completed `/viper-team` runs or every ~2 weeks of active use, Advisor reviews:

- Are any tips **no longer firing** (role has improved or the pattern has become rare)? → archive or delete
- Are any tips **over-specific** (they only applied to one session)? → delete
- Is a tip **generic enough to become a rule**? → promote to `rules/{advisor,worker}.md` or the role's agent md, then delete from here

Reviews themselves are feedback-memory candidates (see `episodic-feedback.md`).

---

## Relationship to agent md files

The agent md files (`plugins/viper-plugin-cc/agents/*.md`) are the **stable** description of a role — how the role should behave in general. This file is **corrective** — what to watch out for specifically.

If a tip in this file consistently changes worker output quality in a role, consider folding it into the role's agent md. Once folded in, delete it from here.

Keep this file short. If it's growing past ~20 tips, either roles are underspecified (fold several tips into agent md) or we're tracking too much noise (delete older tips).

---

## Related

- [episodic-feedback.md](episodic-feedback.md) — per-session episodes; evolution tips are a slower distillation
- [roles.md](roles.md) — role taxonomy for the "role" field
- `plugins/viper-plugin-cc/agents/*.md` — the stable role descriptions that tips here supplement
