---
description: Pre-completion contract — tool_use log-based verification across 4 profiles (code_change/research/file_task/text_answer). Applied before claiming "done".
---

# Execution Contract — Required before declaring "done"

**Source**: Adopted via `/geek-digest` 2026-04-20 (GeekNews id=28652, Bracket library).
**Plan**: `localdocs/plan.geek-digest-2026-04-20-idea-C.md`

Blocks "said it was done but wasn't" cases. Instead of LLM self-report, **collect objective evidence from tool_use logs → compare against contract rules → code rules decide**.

## 4 Profiles

### code_change (bug fix, feature implementation, refactor)
- [ ] `Read` was actually called and the target file was read before modification (read-before-write)
- [ ] `Edit` or `Write` tool_use exists for the resulting file
- [ ] Verification command (`pytest`, `make test`, `bun test`, `npm test`, etc.) ran with exit 0
- [ ] When declaring a commit: `git commit` tool_use exists and HEAD moved
- [ ] **Comprehension anchor (2026-04-21 idea-3)**: Is the WHY of the change recorded in at least one place — code comment / commit message / conversation summary? Defends against the "70% problem" — accumulated code where AI matched the form but the intent evaporated. Basis: Addy Osmani "Comprehension Debt" (id=28716). See also: `routing.md` Rule 7 signal measurement.

### research (investigation, analysis)
- [ ] Minimum 2 `Read`, `Grep`, or `WebFetch` tool_use calls
- [ ] At least 1 file:line citation or URL reference per conclusion claim

### file_task (file creation/conversion)
- [ ] `Write` tool_use exists
- [ ] Output path stated in stdout or final response

### text_answer (Q&A, explanation)
- [ ] `Read` called before referencing an actual file
- [ ] External factual claims carry a verifiable source — **one of**: (a) a `Read` on the exact file/line being cited, (b) a `WebFetch` result with URL, (c) an explicit authoritative citation (doc URL, RFC, spec section) — **plus** a stated confidence level (e.g. `~90% confident` or `verified`). A bare "training data" disclosure is NOT sufficient (unverifiable, decays without notice).

## Verdict rules

- **VERIFIED**: all checkboxes for the relevant profile pass
- **PARTIAL**: 1–2 core (required) items missing
- **BLOCKED**: majority of core checkboxes missing — "done" declaration is blocked

## Application points

1. **`/pi:cross-verify` prompt**: extract tool_use metadata from subagent transcript → compare against checklist above → include result.
2. **`/codex:review`**: confirm read-before-write evidence when reviewing code changes.
3. **Stop hook (optional, v2)**: `~/.claude/hooks/verify-execution-contract.sh` auto-evaluates recent transcript at session end. Manual in v1.

## Profile selection

The profile is selected from evidence across the **whole session**, not from the first keyword alone. Evaluate in this priority order:

1. **Explicit override** — If the user prompt or session metadata contains a directive like `profile: code_change` (or a directives entry that names a profile), use it and stop.
2. **Tool-use / artifact evidence (primary signal)** — Inspect the session's `tool_use` log and the shape of the final artifact. Any of the following flips the profile:
   - `Edit` / `Write` on source files + a test-run command (`pytest`, `npm test`, `bun test`, `make test`, etc.) → **code_change**, regardless of surface phrasing like "write a test" or "add validation"
   - `Write` producing a net-new file with no accompanying source-file `Edit` and no verification run → **file_task**
   - `Grep` / `Read` / `WebFetch` dominate, few or no `Edit` / `Write`, and the answer is prose → **research** (if multiple sources consulted) or **text_answer** (if single source / general knowledge)
3. **Mixed sessions** (e.g. "investigate and fix") — Apply the profile whose evidence is present; when both `research` and `code_change` evidence exist, **code_change** supersedes (its checks are strictly stronger).
4. **Fallback (keyword hint, weakest signal)** — Use only when tool-use evidence is still ambiguous:
   - `fix|bug|implement|refactor` → **code_change**
   - `analyze|investigate|trace|research` → **research**
   - `generate|write|create|make` (and no source edits observed) → **file_task**
   - everything else → **text_answer**

Profile selection is re-evaluated when declaring done, not frozen at session start. A session that opened as `research` but produced edits is judged under **code_change**.

## Direct Bracket library integration (optional, v2)

In Python 3.12+ environments, after `pip install bracket`, hook scripts can parse `.bracket/runs/*` JSON logs for more rigorous verification. In v1, tool_use logs alone are sufficient.

## Related

- [../advisor.md](../advisor.md) § "Routing" — executor selection
- [../advisor.md](../advisor.md) § "Anti-patterns" — "confidence is the problem"
- [../advisor.md](../advisor.md) § "Subagent Token Diet" — token savings must not cause fewer contract checks to pass
