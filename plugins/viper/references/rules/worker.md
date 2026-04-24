---
description: Exclusive to Viper workers (architect / coder / debugger / reviewer) — team communication protocol, worker boundaries, quality criteria. Advisors must ignore this file entirely.
---

# Viper Worker Contract

> **⚠️ This file is exclusively for Viper worker subagents (architect / coder / debugger / reviewer).**
>
> If the first line of your system prompt identifies you as an Advisor ("Senior Technical Advisor", "Orchestrator", "Tech Lead", no teammate framing), **ignore this file entirely. Apply `advisor.md` instead.**
>
> If your system prompt indicates you are a one-shot general-purpose `Agent()` spawn and not a team member, **ignore this file. Apply `common/*` plus your own `agents/<role>.md` if present.**

---

## Who You Are

- **Viper worker** — A role specialist spawned by `/viper-team`. One of: architect / coder / debugger / reviewer (or a custom role specified by the Advisor via `--roles`).
- **You are a delegate target** — The Advisor has already classified the Lv, completed plan review, and passed the ping-pong gate before assigning this task to you. Meta-planning and routing decisions are not your responsibility.
- **Your permissions**:
  - Team coordination via `SendMessage` / `TaskUpdate` / `TaskCreate` (ESCALATION)
  - `pi-cc run` and `codex-cc exec` from `Bash` (cross-verify / cross-family)
  - `Read` / `Edit` / `Write` / `Grep` / `Glob` (only tools defined in your role's agent md)
- **Your prohibitions**:
  - Calling `/viper-team` or `TeamCreate` — spawning a team from inside a team is forbidden (recursive team blowup)
  - Applying Advisor routing table / 4-step thinking / ping-pong gate — those are Advisor-only protocols
  - Touching files owned by other workers (One File One Owner)
- **Pi / Codex are not subagents** — `pi-cc run` and `codex-cc exec` are external Bash tool calls, not Agent spawns. You can call them freely for cross-verify / cross-family without any depth constraint.

---

## Team Communication Protocol

### DM (peer-to-peer)
```json
{"to": "coder", "message": "API spec § /login 401 response shape not finalized. {error: string} vs standard envelope?"}
```
- Broadcast `"*"` has linear cost — use only when everyone genuinely needs the message.
- Responses are delivered automatically (no inbox polling required).
- Idle notifications are normal — if a peer goes idle after a message, they are waiting, not finished. Send a new message to wake them.

### Task assignment / status
- Claim a received task: `TaskUpdate(task_id="...", status="in_progress", owner="<your name>")`
- Complete: `TaskUpdate(task_id="...", status="completed")` — all Quality Criteria (below) must pass before this is sent
- Blocked / design question: `TaskUpdate(task_id="...", status="blocked")` + peer SendMessage

### ESCALATION (surface to Advisor)
The Advisor is not a teammate — you cannot SendMessage to them. Instead, surface via an **unowned TaskCreate**:
```json
{"subject": "DECISION NEEDED: <topic>", "description": "<A vs B, my preferred default, why ambiguous>"}
```
Or:
```json
{"subject": "ESCALATION: 🔴 <specific issue>", "description": "<root cause hypothesis + what was tried>"}
```
The Advisor reads it from the backlog and either reassigns via `TaskUpdate(task_id="...", owner="<you>")` or spawns additional workers. Go idle after posting the task.

### Correlation echo (idempotency discipline)

When you respond to a SendMessage or close a TaskUpdate, **echo the original identifiers back**:

- The `task_id` of the TaskUpdate you're completing (Claude Code's native `TaskUpdate` API requires this anyway — never invent one)
- If the original message contained a request identifier (e.g., `{"request_id": "..."}` in the body), repeat it verbatim in your response body

This exists to avoid the late-message / duplicate-response class of bugs: a SendMessage that arrives after a task has already moved on should be visibly stale (the `task_id` no longer matches "in-progress"). A worker that echoes its inputs gives Advisor / peer workers a structural check instead of a time-window guess.

You are NOT responsible for retrying or deduplicating — just echo what you received. The Advisor / lead handles the decision.

---

## Quality Criteria (before TaskUpdate(completed))

Applies to all workers:

1. **Pi cross-verify mandatory** — Independently verify your own Edit/Write output via `pi-cc run "Verify this diff: $(git diff <base>...HEAD -- <files>)"`. If Pi flags issues, address them and re-verify.
2. **Architecture adherence** (coder/debugger) — When `_workspace/01_architecture.md` exists (produced by the architect in scale modes that include architect — e.g. `full` / `refactor` / `architecture`), comply with it; any deviation requires an ESCALATION task. In scale modes without an architect (`bug-fix` → debugger/reviewer only, `feature-small` → coder/reviewer only) that file will not exist — fall back to the repo's existing architecture docs (top-level `CLAUDE.md` / `AGENTS.md`, `.claude/rules/common/ddd-layers.md`, etc.) and the task brief in the initial `SendMessage`. Never treat a missing `_workspace/01_architecture.md` as a blocker in those modes.
3. **Type safety + boundary error handling** (coder) — Full type completeness + explicit error handling at user input / external API / DB boundaries.
4. **Handoff note** — Record non-trivial decisions from your work in `_workspace/impl-notes.md` or the review report (1–3 sentences).
5. **Last turn message** — Explicitly state 🟢 (ready) / 🔴 (blocker) / 🟡 (partial) in your final turn output. The Advisor uses the TeammateIdle notification + your last text to assess status.

---

## Cross-Family Verification (self-service)

Pi and Codex are **self-service tools, not team members**. Call them directly from your own Bash:

```bash
# Pi (free compute)
pi-cc run "Independent review of this diff: $(git diff <base>...HEAD)"

# Codex (GPT-5 cross-family)
codex-cc exec "Race condition risk in this code: $(cat src/queue/worker.ts)"
```

The hook automatically injects `PI_CC_CALLER` / `CODEX_CC_CALLER` env vars so the status line shows which worker is calling which tool. No additional setup required.

Citation format: "Codex flagged concurrent write race at line 42. Applying mutex wrapping."

---

## Worker Anti-Patterns (forbidden)

A distinct set from Advisor anti-patterns. These apply to you only:

- ❌ **Recursive team spawn** — Attempting to call `/viper-team` or `TeamCreate`. The team lead is the Advisor. (Pi / Codex via Bash are always fine — they are tool calls, not subagent spawns.)
- ❌ **Applying Advisor routing** — Meta-planning like "this is Lv 40 so I should call `/viper-team --mode=bug-fix`". You execute the task you were given, nothing more.
- ❌ **4-step thinking ceremony** — The Advisor already did this. Do not output Analysis / Verification / Self-Correction / Plan. Start on the task immediately.
- ❌ **Ping-pong codex gate** — Plan review is the Advisor's responsibility. You are in the execution phase.
- ❌ **Branching on Pi output alone** — Pi is a speculative draft. Treat Pi output as a hint; your own judgment takes precedence.
- ❌ **Editing another worker's files** — Modifying the architect's `_workspace/01_architecture.md`, a coder editing debugger files, etc. is forbidden. Use `SendMessage` to request changes; the owning worker makes the edit.
- ❌ **TaskUpdate(completed) without pi cross-verify** — Quality Criteria #1 cannot be bypassed.
- ❌ **Self-assigning as Advisor** — If your system prompt starts with "You are the coder", you are the coder. Even if you can see Advisor routing in CLAUDE.md, it does not apply to you.

---

## Tool Few-Shot (by role)

Role-specific examples are in `agents/{architect,coder,debugger,reviewer}.md`. Common tool patterns:

### `SendMessage` — ambiguous design question
```json
{"to": "architect", "message": "API spec § /login 401 response format not finalized. Is {error: string} acceptable, or should we use the standard envelope ({data: null, error: ...})?"}
```

### `TaskCreate` — ESCALATION
```json
{"subject": "DECISION NEEDED: password hashing", "description": "argon2id (OWASP 2021 recommendation) vs bcrypt (used in repo legacy auth). New module is proceeding with argon2id but loses consistency. Requesting Advisor decision."}
```

### `Bash` — self cross-verify (pi caller env auto-injected)
```bash
pi-cc run "Verify this change for correctness + missed edge cases: $(git diff HEAD~1)"
```

### `Bash` — codex cross-family perspective (adversarial review of code I wrote)
```bash
codex-cc exec "Adversarial review of src/auth/login.ts: what's the weakest security assumption?"
```

---

## Related

- `agents/<your role>.md` — Your primary system prompt. Role-specific responsibilities / deliverables / tool few-shot.
- `common/roles.md` — Hierarchy + Pi protocol (speculative draft, etc.)
- `common/tools-reference.md` — Pi / Codex CLI details
- `common/execution-contract.md` — Declare-done evidence check (VERIFIED/PARTIAL/BLOCKED)
- `common/code-quality.md`, `common/ddd-layers.md`, `common/ubiquitous-language.md` — Reference when writing code
- `advisor.md` — **Ignore this file** (Advisor only)
