# Team Bootstrap — Shared Protocol

Injected into each worker's kickoff prompt by `/viper-team`. Each agent md references a short form of this.

## Architecture (Claude Code native)

- **Advisor (main Claude Code session) = team lead.** Per Claude Code agent-teams docs: "Lead is fixed — the session that creates the team is the lead for its lifetime. Teammates cannot spawn teammates; only the lead can manage the team."
- **You (reader of this bootstrap) = teammate.** You are one of the workers spawned for this team.
- Other teammates are your **peers**. You can message them directly via `SendMessage`.
- The Advisor is NOT in your team's `members[]` list. You cannot `SendMessage` the Advisor. Instead, your idle notifications + `TaskUpdate` status carry information back to the Advisor automatically.

## Primitives (Claude Code native only — no Viper JSON)

- `SendMessage({to: "<peer-name>", message: "..."})` — DM a peer teammate (not the Advisor)
- `SendMessage({to: "*", message: "..."})` — broadcast to all teammates (expensive; use sparingly)
- `TaskCreate({subject, description, activeForm?})` — create a task (you or another peer can own it)
- `TaskUpdate({task_id, status?, owner?, addBlocks?, addBlockedBy?})` — change status/ownership/deps
- `TaskList()` — see full team backlog
- `Read / Edit / Write / Bash / Grep / Glob` — local tools

## Work Loop

1. Advisor creates tasks and assigns you one via `TaskUpdate(owner=<your-name>)` (you'll see it when it arrives, or you can `TaskList()` at start)
2. When you pick up a task, `TaskUpdate(status="in_progress")`
3. Execute. Use `SendMessage` to peers for clarifications (architect for design, reviewer for early feedback, etc.)
4. On completion, `TaskUpdate(status="completed")` — this fires the natural "done" signal. Include any notable outcome in the last message.
5. Then go idle. Your idle notification + the summary of your last message reach the Advisor automatically.

## Signaling the Advisor (no direct SendMessage)

You cannot DM the Advisor. Patterns:

- **Blocker needs decision** — Set `TaskUpdate(status="in_progress")` with a **new task** created via `TaskCreate({subject: "DECISION NEEDED: <question>", description: "<context>"})`, then go idle. Advisor sees the new unowned task in the backlog on the next poll.
- **Role missing** — Same pattern: `TaskCreate({subject: "ROLE REQUEST: need <role>", description: "<why>"})` and go idle. Advisor can spawn a new teammate.
- **Task truly done** — `TaskUpdate(status="completed")` with a final summary in your last turn output. Idle notification carries a summary.

## External Model Consultation (self-service, no relay)

Call from your own Bash. PreToolUse hook auto-injects `*_CALLER` env so the statusline attributes usage to you.

- `pi-cc run "..."` — free cross-verify / exploration
- `codex-cc exec "..."` — GPT-5 tier cross-family perspective

Incorporate the output into your own answer; do not relay verbatim to peers.

## Quality Gate

- Before `TaskUpdate(status="completed")`: call `pi-cc run "verify this diff: ..."` (mandatory per viper-plugin-cc CLAUDE.md rules)
- Reviewer gates closure with `🟢`/`🔴` verdict; max 2 review rounds before escalating via `TaskCreate` (DECISION NEEDED)

## Prompt Caching

System prompt is static by design. Per-invocation content (task, peers, rationale) arrives only in the first user message. Don't quote the kickoff back into your prompts; reference by pointer only.
