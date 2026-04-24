---
description: Meta — listing order and intended composition of the files in `rules/common/`. Claude Code injects all `rules/*.md` at session start; the listing here documents the conceptual inject order so new files slot in predictably.
globs: []
alwaysApply: true
---

# rules/common — composition index

All files in `rules/common/` are auto-injected by Claude Code at session start. The filesystem order is alphabetical, not semantic. This file documents the **intended conceptual order** — a new reader should read the files in this order to understand Viper rules.

The ordering is also a guide for where to add new rules: pick the category that matches, don't invent a new one without thinking about the slot.

---

## Conceptual inject order

### 1. Foundational context (who / why)

- **`roles.md`** — Advisor / worker / subagent / Pi / Codex identities. Everything else references these names.
- **`vibe-and-rigor.md`** — The Viper engineering philosophy (input vibe + output rigor). Sets the tone for everything below.

### 2. Task assessment (how to grade a request)

- **`task-classification.md`** — Lv-band routing table (if present; currently inside `rules/advisor.md`).
- **`complexity-matrix.md`** — Base + Additives − Deductions × Multipliers formula for Lv 0-100.
- **`thinking-guidelines.md`** — General reasoning discipline.

### 3. Execution standards (how to do the work)

- **`execution-contract.md`** — Evidence requirements before declare-done.
- **`code-quality.md`** — Generic code-quality rules.
- **`ddd-layers.md`** — Layered architecture rules.
- **`ubiquitous-language.md`** — Naming + terminology discipline.

### 4. Tools + integrations

- **`tools-reference.md`** — Pi / Codex CLI usage.

### 5. Learning loop (how Viper improves)

- **`episodic-feedback.md`** — How to write feedback memory entries that serve as episodic experience.
- **`agent-evolution.md`** — Per-role tip accumulation (static, cache-safe).

### 6. Housekeeping

- **`document-management.md`** — `localdocs/` conventions, worklog files.

---

## Adding a new rule

Decide the category first. Files in the same category should be readable in any order; files across categories build on earlier categories.

If a new rule doesn't fit any category above, you're probably either:
- restating something that already exists (check first), or
- introducing a new category — pause and discuss with the Advisor / user before adding.

Keep filenames short and descriptive. No `my-new-rules-v2.md` — if you need v2, the old one is wrong and should be fixed or deleted.

---

## Cache considerations

Every time any file in `rules/common/` changes, the prefix cache is invalidated the next time it's injected. Consequence: treat rules as **stable contracts**, not a scratchpad.

- Small wording fixes are fine (you pay one cache rewrite on the next session)
- Structural reorganization should batch — one big commit, not a drip feed
- Avoid conditional content that varies by session state; cache hits depend on identical bytes
- `agent-evolution.md` is curated manually for exactly this reason — it looks dynamic but updates infrequently, on human timing

See `localdocs/plan.prompt-caching-analysis-2026-04-24.md` (gitignored — may not be present in distribution) for the detailed analysis.

---

## Why this file exists

Composition ordering is invisible in an alphabetical directory listing. Without this index, a new contributor (or the Advisor in a fresh session) has no way to tell whether `agent-evolution.md` comes before or after `roles.md` conceptually. The filesystem says A < R; the concept says R first.

This is a documentation file, not a loader — Claude Code still injects everything in alphabetical order. The humans / AI reading the rules use this index to build their mental model.
