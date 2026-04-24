---
description: Shared domain language across experts/PMs/engineers. Enforced in code, tests, docs, and commits. Project-specific glossary maintained separately.
---

# Ubiquitous Language

**Core principle**: Ubiquitous Language is the **single shared language** among domain experts, product managers, and engineers. It is not merely a glossary — it is a **tool** for accurately expressing domain knowledge.

---

## Why it matters

1. **Eliminates the domain expert ↔ developer language gap** — when planning, meetings, code, and docs all use the same words, translation costs (= the breeding ground for bugs) disappear
2. **Code ↔ domain alignment → maintenance efficiency** — when class/method/variable names match real business terminology, new team members can understand the domain just by reading the code
3. **Stronger collaboration** — terminology confusion in PR reviews, bug reports, and handoffs disappears

---

## Advisor behavioral rules

### When writing code (directly or delegating to a subagent)
- **Use terminology from PRDs, directives, and planning docs verbatim** for class/method/variable names. Even when translating to English, maintain **1:1 correspondence** (e.g., "Reserved Book" → `ReservedBook` ✅, `PendingItem` ❌).
- **No mixing multiple names for the same concept**: do not use `user` / `customer` / `member` interchangeably for the same entity. Standardize on one.
- Avoid abbreviations and contractions. Use `user`, `customerService` instead of `usr`, `custSvc`.

### When reviewing code (examining subagent output)
- **Mandatory naming audit**. When an ambiguous name is found (`Handler`, `Manager`, `Processor`, `Util`):
  1. Ask whether a more domain-accurate word exists → if so, propose a rename
  2. If not, search PRD/hot.md/domain docs for how that concept is expressed
  3. If still ambiguous, **ask the user**: "What do domain experts call this concept?"
- Multiple names found for the same concept → propose standardization + rename patch

### When writing PR/commit messages
- Use Ubiquitous Language in commit title and body too. `feat: Add ReservedBook cancellation` > `feat: Fix pending item cancel bug`.

---

## Practical checklist (self-check on every PR)

1. [ ] Do newly added class/method/variable names **match the terminology in PRD and domain docs**?
2. [ ] Are there **multiple names mixed** for the same concept? (grep regularly: `user|customer|member`)
3. [ ] If a name ends with a **generic noun** (Handler/Manager/etc.), can it be replaced with a domain term?
4. [ ] Do API paths, DB column names, log messages, and UI labels **all use the same terminology**?
5. [ ] If a **more accurate domain word** was found during refactoring, rename immediately + update the team glossary?
6. [ ] Is the **same term used** in meeting notes, spec docs, and code comments? (planning says "Reserved Book", code says "PendingItem" → ❌)

---

## Bounded Context caution

Ubiquitous Language must be consistent **within a Bounded Context**. If "the same word" means different things in different contexts, that is a signal of distinct contexts → **explicit context separation** is required.

- Example: `Order` means "payment order" in a payment context and "shipment record" in a delivery context — do not merge these into one class; instead **separate them into distinct classes** (+ translation layer = ACL)

---

## Tools and techniques

- **Maintain a glossary**: `docs/glossary.md` or a Confluence page with a `domain term → code term` mapping table. Register new terms immediately when introduced.
- **Periodic grep checks**: `rg 'user|customer|member' --type ts` to detect synonym mixing.
- **Lint rules**: add custom lint rules that warn on names containing specific generic nouns (Handler, Manager, Processor).

---

## Author (curiousjinan) emphasis

> "When we meet with mutual respect and understanding, approaching with 'perspective expansion', Ubiquitous Language truly becomes the team's rhythm and DDD succeeds."

In other words, it is not enough to just create a glossary — **continuous dialogue** and a **code refactoring loop** are essential. Advisor must always propose improvements when a "better domain word" is found during code review.

---

## Related

- [DDD Layers](ddd-layers.md) — layer dependency rules (Ubiquitous Language must be accurately reflected in each layer)
- [Code Quality](code-quality.md) — no thin wrappers, prefer domain methods (practical means of applying Ubiquitous Language)
