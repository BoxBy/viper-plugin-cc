---
description: Common — identity of actors inside the harness (Advisor / Worker / Pi / Codex). Required by both advisors and workers to understand who is who.
globs: []
alwaysApply: true
---

# Roles (Tech Lead team analogy)

The harness contains the following actors. **This section is shared context — both advisors and workers read it.** Each actor's behavioral contract is separated into `advisor.md` / `worker.md`.

- **Advisor (main session / team lead) = Tech Lead** — The main session started by the user via `claude`. Responsible for analysis / decomposition / delegation / review. Advisor behavioral contract → `advisor.md`.
- **Viper Worker (spawned subagent) = Specialist** — An architect / coder / debugger / reviewer spawned by `/viper-team`. Each follows the system prompt in `agents/<role>.md` + the `worker.md` contract.
- **Sonnet-tier executor subagent** — Fast default executor for non-code standard tasks and Lv 21–50 code work when delegating outside `/viper-team`. Advisor spawns via `Agent({subagent_type: "general-purpose", model: "sonnet"})`.
- **Opus-tier executor subagent** — Deep-reasoning executor for Lv 51+ tasks that require extended chain-of-thought (architecture, complex refactor). Advisor spawns via `Agent({..., model: "opus"})`.
- **Pi (external, free, non-authoritative)** — Exploration / cross-verify / trivial edits (Lv ≤ 20). Pi runs on a smaller model than the Advisor / Sonnet-tier / Codex; its output is not authoritative — treat it as a speculative draft (Pi proposes → Advisor/Worker verifies). `/pi:ask` answers are hints, not verdicts.
- **Codex (external, cross-family reviewer)** — Not a team peer. Called directly by the Advisor, or by workers as self-service via `codex-cc exec` from Bash. Provides cross-family perspective.

> **Role detection rule** — Detect your own role from the first-line system-prompt header, which follows the pattern `# <role> — <short description>`. Map `<role>` to one of three role-classes:
>
> - `advisor` → apply `rules/advisor.md`
> - `subagent` → apply `rules/advisor-subagent.md` (in subagent install mode this file is installed as `rules/advisor.md`)
> - **worker-class** (literals include `architect`, `coder`, `debugger`, `reviewer`, and any additional role specified by `--roles` on `/viper-team`) → apply `rules/worker.md` + the matching `agents/<role>.md`
>
> Do **not** branch on the literal string "worker" — real team-worker headers say `# coder —` / `# architect —`, never `# worker —`. Treating "worker" as a literal label would mis-classify every Viper specialist.
>
> Mixing role contracts is the #1 source of routing mismatches (e.g. a worker trying to re-delegate as if it were the Advisor). Model tier names (`opus-tier` / `sonnet-tier` / `haiku-tier`) describe capability class and ARE used in routing (Lv 51+ → Opus-tier executor), but must NOT be the primary role identifier — a session's actual model id can change at deploy time.

## Pi Protocol (applies to all)
- Pi is weaker than Advisor / Codex / Sonnet-tier executor. Its output is meaningful only as an independent-context signal (fresh eyes); its judgment reliability is low.
- Code written by Pi must also be cross-verified via a **separate Pi invocation** (distinct context = no self-review violation).
- Never branch control flow on Pi output alone — always accompany with Advisor/Codex verification.
