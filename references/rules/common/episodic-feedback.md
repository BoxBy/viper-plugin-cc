---
description: Common — Operate Claude Code's native feedback memory type as an episodic-experience store. Record failure / rework / surprise episodes so the next session gets "senior intuition" automatically via the existing MEMORY.md inject path.
globs: []
alwaysApply: true
---

# Episodic Feedback Memory

Claude Code's native auto-memory system already provides four types (`user` / `feedback` / `project` / `reference`). This file defines **how to use the `feedback` type as an episodic experience log** without building any parallel storage.

The user-global CLAUDE.md already describes *what* feedback memory is. This file defines *when and how to write one* so the feedback store grows into an experiential corpus automatically.

---

## The core idea

Instead of a separate `.viper/episodes/*.json` store (which would duplicate the native memory inject path and risk cache invalidation), we treat each **notable outcome** (failure, rework, surprise) as a feedback entry. The MEMORY.md inject that already runs at session start delivers these as "senior intuition" for free.

Native auto-memory gives us:
- Session-start inject of all `feedback_*.md` entries — we don't need our own retrieval engine
- Stable cache key (Claude Code manages when MEMORY.md actually changes, not us)
- Per-project scoping (`~/.claude/projects/<proj>/memory/`)

What we add on top is **discipline**: when to write, what to write, how to structure.

---

## Write triggers — Advisor's job

Advisor SHOULD propose writing a feedback memory when any of the following happens in the session:

1. **Rework at Lv 21+** — Advisor reaches "done" then the user or a reviewer sends it back. Root cause + how to recognize next time = feedback material.
2. **Repeated mistake** — Same class of error happens twice in one session (or re-surfaces from a past session). The second occurrence is the signal.
3. **Non-obvious invariant discovered** — Something the code depends on that is not documented in CLAUDE.md / rules. Write it so next session doesn't re-discover.
4. **Cross-check disagreement converged** — Codex / pi / Advisor disagreed, then one side turned out right for a specific reason. That reason is reusable.
5. **User corrects an approach** — User redirects after Advisor's first attempt. The correction direction is feedback-worthy.

Advisor MUST NOT silently skip. When one of the above happens, say:

> "This looks like feedback-memory material: <one-line reason>. Draft? (y/n)"

User has final say. If yes, write the file with the structure below.

---

## Episode structure — adapted from Viper EpisodicMemory

Each feedback memory file must contain three blocks:

```markdown
---
name: <short imperative title>
description: <one-line hook for the MEMORY.md index>
type: feedback
originSessionId: <current session id>
---

## Rule

<The rule itself. Imperative. One sentence.>

## Why

<What happened. Include the specific failure / rework / surprise.
Mention any uncertainty markers present in the triggering log:
"assuming", "not sure", "not verified", "failed to", "don't know",
"가정했", "확실치 않", "잘 모르겠", "실패" etc. These are Viper's
uncertainty-trace patterns — flagging them in the Why section makes
the same mistake easier to recognize next time.>

## How to apply

<When does this rule fire? What signal triggers it? What's the
counter-behavior? Keep concrete — a future session should be able
to tell "yes, this applies to my current situation."
>
```

Contrast with "just write the rule" style: the `Why` block preserves the **triggering episode** (Viper's "ERROR fat" strategy — success slim, error fat). The next session reading the memory sees the story, not just the conclusion.

Existing `feedback_*.md` files in the memory store predate this convention. New ones follow it. Old ones don't need retrofitting.

---

## Uncertainty markers — don't just rephrase, preserve

Viper's EpisodicMemoryService scores uncertainty phrases (English regex: `not sure` 0.8 / `assuming` 0.6 / `not verified` 0.9 / `failed to` 0.7 / `don't know` 1.0). Viper's version is informal: if the triggering log or conversation contained any of those phrases (English or Korean equivalent), **quote it verbatim** in the Why block.

Example:
```markdown
## Why

Advisor said: "I'm not sure if the hook fires on PostToolUse vs
PreToolUse for this matcher" — then proceeded anyway. The hook
actually fired on neither (matcher syntax was wrong). The "not sure"
was a real signal, not a hedge.
```

The point of preserving the exact phrase: next session's Advisor sees it and thinks "I said 'not sure' again — should I verify first?". That's the learning loop.

---

## What NOT to record

Avoid feedback inflation — if every session writes 5 feedback entries, the MEMORY.md inject becomes too long and the signal-to-noise drops.

Skip recording when:

- **Environmental noise** — OS permissions, network flakes, transient API 500s. Not a behavioral lesson.
- **Explicit already-captured** — the rule is already in CLAUDE.md, rules/, or an existing feedback file. Update the existing file's frontmatter description if it's unclear, don't add a second one.
- **User-specific preference** — those go in `user` type, not `feedback`.
- **One-off task state** — "we're migrating auth this week" is `project` type.
- **External fact lookup** — "Anthropic pricing doc is at URL X" is `reference` type.

If in doubt, ask the user whether to record or skip.

---

## Review trigger — when MEMORY.md grows

Roughly every ~20 feedback entries in the store, Advisor should propose a review pass:

- Any entries superseded by a newer one? → mark obsolete or delete
- Any entries now captured in CLAUDE.md / rules? → promote and delete
- Any entries the user no longer agrees with? → user choice

This keeps the MEMORY.md inject lean. The review itself is a feedback-memory candidate if it surfaces a pattern.

---

## Relationship to other memory types

| Type | Holds | When to use |
|------|-------|-------------|
| `user` | Role, preferences, knowledge | User said "I'm a backend engineer, don't explain SQL" |
| `feedback` (this file) | Episodic lessons from outcomes | After rework / mistake / surprise |
| `project` | Current work state, deadlines, incidents | "Merge freeze starts Thursday" |
| `reference` | Pointers to external systems | "Bugs tracked in Linear project INGEST" |

If an entry could go in either `project` or `feedback`, ask: will this matter in 6 months after the current project is done? If yes → `feedback` (episodic lesson). If no → `project` (current state).

---

## Why we did NOT build `.viper/episodes/`

Considered and rejected (see `localdocs/learn.viper-review-2026-04-24.md` § 1.2):

- Claude Code already injects MEMORY.md at session start — we'd be building a parallel inject path
- Parallel inject = new cache invalidation trigger when we mutate it
- Viper's Jaccard + AST overlap retrieval doesn't translate: we can't override Claude Code's retrieval decision, and the LLM can already decide which memory to lean on from the inject
- 100-entry cleanup / uncertainty regex scoring are implementation details of Viper's custom store — native memory doesn't need them (user-driven cleanup)

The convention in this file gives us Viper-level episodic rigor **without** writing a single line of retrieval code.

---

## Related

- [roles.md](roles.md) — defines Advisor vs worker vs subagent
- [execution-contract.md](execution-contract.md) — declare-done evidence checks (feedback triggers)
- User-global `CLAUDE.md` — native auto-memory type definitions
- [learn.viper-review-2026-04-24.md § 1.2](../../../../../../localdocs/learn.viper-review-2026-04-24.md) — rationale for this design vs Viper's custom store (localdocs is gitignored; skip if absent)
