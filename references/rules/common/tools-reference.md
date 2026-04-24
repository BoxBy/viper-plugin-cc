---
description: Common — Pi / Codex CLI usage reference. Shared by both Advisors and workers since both call pi-cc / codex-cc.
globs: []
alwaysApply: true
---

# Pi / Codex CLI Reference

Both Advisors and workers call the CLIs below. For "when/why to call them", see the role-specific contracts (`advisor.md` / `worker.md`).

---

## Pi Execution

### Skills (preferred)
`/pi:review`, `/pi:ask`, `/pi:explore`, `/pi:brainstorm`, `/pi:cross-verify`, `/pi:test`, `/pi:rescue`, `/pi:super-pr`, `/pi:adversarial-review`

### CLI
- `pi-cc run "prompt"` — async execution, returns an id
- `pi-cc run "prompt" --bg` — background execution
- `pi-cc status` — show current status
- `pi-cc result <id>` — fetch result
- `pi-cc cancel <id>` — cancel a task
- `pi -p "prompt"` — clean text output (non-interactive)

### Pi is a harness, not a tier

Pi is a **harness** the user configures with a single backend model, similar in spirit to how Claude Code exposes Opus/Sonnet/Haiku — but with a twist: Pi's backend is picked **once** by the user's local setup and stays fixed across the session. This harness makes no assumption about *which* model that is; it could be a small local model, a mid-tier remote API, or a frontier-class backend.

That means:
- **Pi's raw capability** (context window, cost, reasoning depth) is determined by the user's backend choice, not by this harness.
- **Pi's protocol characteristics** are invariant regardless of backend:
  - Pi runs **outside the Claude session** → cannot read `CLAUDE.md` / `rules/*`.
  - Pi carries **no Claude conversation history** → fresh, independent context every call.
  - Pi's **output format stability** and **tool-use reliability** vary by backend; even capable backends can drift on long chained tool calls because Pi's protocol is a thin wrapper.

Routing decisions therefore key off **Pi's protocol characteristics + the user's known-good task types for their backend**, not off an assumed tier relationship with Haiku/Sonnet/Opus.

### Opt-in size guard (`PI_CC_MAX_SAFE_TOKENS`)

Users who know their Pi backend has a small context window can stop oversized prompts from silently truncating:

```bash
# e.g., 55000 if the backend is a 64k-window model (leaves ~10k margin)
export PI_CC_MAX_SAFE_TOKENS=55000
```

When set, `pi-cc` estimates prompt tokens (`bytes / 4`) and escalates oversized prompts by exec'ing `claude -p --model claude-haiku-4-5-20251001`. Unset → no size check (default). Override per-invocation with `pi-cc run ... --force-pi`.

Haiku is the default escalation target because it's Claude-family (predictable fallback, 200k window). Users who prefer a different fallback can wrap `pi-cc` in a shell alias.

### When to prefer Pi

- `/pi:ask` — quick single-shot Q&A / second opinion from an independent context
- `/pi:brainstorm` — fan-out ideas; exact format not critical
- `/pi:cross-verify` on focused work — fresh eyes outside the Claude session
- Any task the user has verified their backend handles well
- "Tool-light" prompts: at most 1–2 tool calls expected

### When to prefer a Claude-native subagent instead

A Claude-native subagent (Haiku/Sonnet/Opus, picked by task complexity) is the better choice when:
- The work must respect `CLAUDE.md` / `rules/*` (Pi runs outside the Claude env)
- Format strictness matters (JSON schema, MD tables, structured review output)
- Tool-use loops are long or complex (many chained Read/Grep/Edit — Pi's protocol tends to drift here)
- You need guaranteed model-tier behavior for the task (Pi's tier depends on the user's backend, which this harness doesn't know)

Pick the Claude subagent model by task complexity:
- Simple review / exploration / format-strict summary → Haiku (`model: "haiku"`)
- Mid-complexity coding / debugging → Sonnet (`model: "sonnet"`)
- Architecture / adversarial review / deep reasoning → Opus (`model: "opus"`)

Explicit invocation:
```bash
# One-shot
claude -p --model claude-haiku-4-5-20251001 "<prompt>"
# Or as subagent
# Agent({subagent_type: "general-purpose", model: "haiku", ...})
```

### Pi principle (revised): match task to Pi's protocol, not to a tier

Use Pi when you want an **independent, outside-the-session view** and the task type is one your backend handles well. For anything requiring Claude-environment awareness, format strictness, or long tool-chain reliability, prefer a Claude-native subagent at the tier that matches the task.

---

## Codex Execution

Codex (GPT-5 tier, resolved via `which codex` — typically `/opt/homebrew/bin/codex` on macOS, `/usr/local/bin/codex` on Linux) is a coding-specialized contractor from OpenAI. Different family from Claude → valuable for cross-model coding, stuck bugs, adversarial review, and write-heavy tasks.

### Execution methods (priority order)

Same structure as Pi: skill → exec → background.

1. **Skill-first**: `/codex:rescue`, `/codex:review`, `/codex:adversarial-review`, `/codex:status`, `/codex:result`, `/codex:cancel`, `/codex:setup`
2. **Direct exec**: `codex exec --skip-git-repo-check "prompt"` — non-interactive clean output (equivalent to `pi -p` / `claude -p`)
3. **Background / parallel**: `node "$CODEX_COMPANION" task "prompt" --background` (when skill is unavailable)

**Note**: If `/codex:*` skills fail with 401 auth errors but `codex exec` works, the companion script is stale — fall back to `codex exec` directly.

### Codex usage principle

- The Codex CLI defaults to a **read-only sandbox** — file writes require explicit activation via `--full-auto` or `--sandbox workspace-write`. Write-required skills such as `/codex:rescue` apply the appropriate flag internally.
- Background by default: `/codex:rescue --background`
- **Ping-pong rounds 2+ MUST use `--resume <session-id>`** — round 1 spawns fresh with the full prompt; subsequent rounds reference prior context ("Round N: applied X/Y/Z. Re-check."). Skipping wastes ~1 min per round on re-initialization.
- Only explicitly pass `--model` / `--effort` when tuning; otherwise let Codex choose.

### Codex unresponsive / hang fallback

When `codex exec` hangs >10 min, returns a 401 auth error, or silently dies:
- **Ping-pong reviewer role** → Opus subagent (`subagent_type="general-purpose", model="opus"`) acting as critic. Cross-family benefit is lost, but same-family adversarial review beats skipping entirely. Log: `"codex unresponsive at Round N — Opus critic fallback, cross-family verification degraded"`.
- **`/codex:rescue` code writer role** → Opus executor fallback (see advisor routing rules).
- **`/codex:review` on final state** → `/pi:review` + Opus self-review. Risk note required.
- **Max retry budget**: 2 retries with exponential backoff (60s, 180s). After the 2nd failure → switch to fallback automatically.
- **Recovery**: once Codex is responsive again, re-run the degraded gate with Codex. Do not silently accept degraded review as final.
