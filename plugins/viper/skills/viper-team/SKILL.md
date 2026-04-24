---
name: viper-team
description: "Spawn a Viper multi-agent coding team on Claude Code's native TeamCreate/SendMessage primitives. The Advisor (main Claude Code session) is the team lead per docs — this skill spawns only worker specialists (architect, coder, debugger, reviewer) and the Advisor coordinates them directly via SendMessage + TaskUpdate + idle notifications. Scale Modes: Full/Bug-Fix/Feature-Small/Refactor/Architecture. Required for coding tasks at Lv 21+."
argument-hint: "[--mode=full|bug-fix|feature-small|refactor|architecture] [--roles=architect,coder,...] [--rationale='<why>'] '<task>'"
user-invocable: true
---

# /viper-team — Spawn Worker Specialists for the Advisor-led Team

**Architecture note (fixed by Claude Code docs)**:
- **Advisor = team lead** (main Claude Code session is the lead for its lifetime)
- **Workers = teammates** spawned by this skill (architect, coder, debugger, reviewer)
- Only the Advisor can spawn additional workers (teammates cannot spawn)
- Workers message each other peer-to-peer; communicate with Advisor via idle notifications (automatic) + TaskUpdate status

This skill is primarily invoked programmatically by Advisor. User-direct invocation is allowed but rare.

## Arguments

```text
/viper-team [options] '<task description>'
```

- `--mode=<mode>` — Scale Mode. One of `full | bug-fix | feature-small | refactor | architecture`. Default: `full`.
- `--roles=<csv>` — Explicit roster override (e.g., `architect,coder,coder,reviewer`). Duplicate roles auto-numbered (`coder-1`, `coder-2`). If set, `--mode` is ignored.
- `--rationale='<text>'` — **MANDATORY for non-default mode OR --roles override**. 1 sentence explaining why this composition fits the task. Injected into each worker's initial task description so they understand the picked scope.
- `<task>` — Natural-language task. Becomes the team description.

## Scale Modes (Advisor is lead — workers only)

| Mode | Spawned Workers | Use when |
|---|---|---|
| **full** (default) | architect, coder, debugger, reviewer (4) | Complexity unclear / architecture touching |
| **bug-fix** | debugger, reviewer (2) | Fix existing behavior, no design change |
| **feature-small** | coder, reviewer (2) | Add feature to single module |
| **refactor** | architect, coder, reviewer (3) | Restructure with same functionality |
| **architecture** | architect, coder-1, coder-2, debugger, reviewer (5) | Multi-module, significant design |

## Roles

**Predefined roles** (full agent md with Responsibilities / Principles / Tool Few-Shot / Deliverable / Team Protocol / Quality Criteria):
- `architect`, `coder`, `debugger`, `reviewer`

**Custom roles** — any other name Advisor invents to fit the task. Examples:
- `security-reviewer`, `test-engineer`, `performance-optimizer`, `data-scientist`, `api-designer`, `ux-researcher`, `ml-evaluator`, `devops-engineer`, `doc-writer`, `accessibility-auditor`, ...

Custom roles are spawned as `subagent_type=general-purpose` with an inline role-specific system prompt built from Advisor's `--rationale` (MANDATORY).

**Forbidden names**: `lead`, `team-lead`, `main`, `advisor` — all refer to the main Claude Code session which cannot be spawned as a teammate.

### Custom role spawn template

```python
Agent(
  subagent_type="general-purpose",
  team_name="<team>",
  name="<custom-role-name>",
  model="<opus | sonnet>",
  run_in_background=True,
  prompt="""You are the <custom-role-name> for team <team>.

Your responsibility: <rationale excerpt — what Advisor wants this role to do>

Task: <task>

Protocol (Claude Code native primitives only):
- Peers are in ~/.claude/teams/<team>/config.json. SendMessage them by name.
- You cannot SendMessage the Advisor (main session). Surface blockers via
  TaskCreate({subject: "DECISION NEEDED: ..."}) and go idle — Advisor reads
  the unowned task.
- Claim work: TaskUpdate(status="in_progress", owner="<your-name>").
- Before TaskUpdate(status="completed"): pi-cc run "<self-verify>" (Rule 7).
  Use codex exec for cross-family perspective when appropriate.

Deliverable: <whatever the task requires>
"""
)
```

## Execution Steps (Claude follows when invoking)

### 0. Argument parsing + validation

Parse `$ARGUMENTS` for `--mode`, `--roles`, `--rationale`, remaining quoted task.

**Validation (all enforced — reject before TeamCreate):**
- If `--mode` absent AND `--roles` absent → default `mode=full`, `--rationale` optional
- If `--mode` present AND `mode != full` AND `--rationale` absent → **REJECT** with: "Non-default mode requires --rationale. State why this mode fits the task."
- If `--roles` present AND `--rationale` absent → **REJECT**: "Custom --roles override requires --rationale. State why this roster + what any custom roles do."
- If `--roles` contains a forbidden name (`lead` / `team-lead` / `main` / `advisor`) → **REJECT**: "Advisor (main session) fills that role — cannot spawn."
- Custom role names (outside predefined 4) are **allowed** — skill spawns them as `general-purpose` subagents using the custom-role template above. The `--rationale` text is inlined into each custom role's prompt, so Advisor should describe each custom role's responsibility clearly in the rationale.

### 1. Resolve Roster

If `--roles` given, use verbatim (after whitelist check). Else map mode → table above. Duplicate role names get `-N` suffix:
- `coder,coder,reviewer` → `coder-1`, `coder-2`, `reviewer`

### 2. TeamCreate

```
TeamCreate(
  team_name="viper-<slug-of-task>",
  description="<task>"
)
```

Slug: lowercase, replace spaces/punctuation with `-`, max 30 chars, match `^[a-z0-9][a-z0-9-]{0,29}$`.

### 3. Prepare Worker Kickoff Messages

Read `${CLAUDE_PLUGIN_ROOT}/references/team-bootstrap.md` content. For each worker, build a prompt:

```text
# <Worker Role> — <team-name>

**Advisor (main Claude Code session) is team lead.** You are a teammate; coordinate with peers via SendMessage and surface progress/questions via idle notifications to Advisor.

**Mode:** <mode> (rationale: <rationale-text, or "default Full composition">)
**Team members:** <list of other workers' names>
**Task:** <original task>

---

<team-bootstrap.md body>
```

Each worker gets the SAME team-bootstrap body but a different role label. They load their own system prompt (from the agent .md) separately.

### 4. Spawn Workers (single message, parallel)

In ONE assistant message, issue N `Agent` tool calls. **`model` 은 호출 시 명시**
— agent.md frontmatter 에 있어도 Agent() 호출 파라미터가 최종 결정. 누락하면
Claude Code 가 parent session 의 모델을 상속해서 의도치 않은 비용/성능 불일치.

Role → model 매핑 (agent.md frontmatter 와 일관):

| Role | Model |
|------|-------|
| `architect` | `opus` |
| `coder` | `sonnet` |
| `debugger` | `sonnet` |
| `reviewer` | `sonnet` |
| custom (general-purpose) | Advisor 판단 (기본 `sonnet`, 심층 추론이면 `opus`) |

```python
Agent(
  subagent_type="<role>",   # architect | coder | debugger | reviewer
  team_name="viper-<slug>",
  name="<name>",             # role name, with -N suffix if duplicated
  model="<opus | sonnet>",   # ← 위 매핑대로 반드시 명시
  prompt="<kickoff message>",
  run_in_background=True
)
```

Subagent_type mapping: role name === subagent_type (architect, coder, debugger, reviewer).

### 5. Advisor Takes Over (as lead)

After spawning, the Advisor:
1. Creates initial tasks via `TaskCreate` for each subtask
2. Assigns via `TaskUpdate(owner=<name>)`
3. SendMessage first workers to kick off
4. Monitors `TeammateIdle` notifications
5. Responds to blockers / questions surfaced via idle
6. If a role is missing mid-task, spawns additional teammate via `Agent()` (Advisor only)
7. Reviews final diff + reviewer verdict; closes team

## Error Handling

| Error | Response |
|---|---|
| `--mode != full` + missing `--rationale` | Reject, request rationale |
| `--roles` override + missing `--rationale` | Reject, request rationale |
| Forbidden name (`lead` / `team-lead` / `main` / `advisor`) in `--roles` | Reject with architectural note (Advisor = main session cannot be spawned) |
| Custom role name in `--roles` (outside predefined 4) | **Allow** — spawn as `subagent_type=general-purpose` with `--rationale` inlined into worker prompt (see "Custom role spawn template" above) |
| `TeamCreate` fails | Report error, suggest team cleanup |
| `Agent` spawn fails | Report which role, proceed without it, note in description |
| Task < 10 words | Proceed but Advisor should clarify via SendMessage to a teammate on first substantive turn |

## Test Scenarios

### Normal — Bug-Fix Mode
```text
/viper-team --mode=bug-fix --rationale='Off-by-one in pagination, single file, existing test covers it' 'Fix pagination showing wrong page count'
```
Expected: Team `viper-fix-pagination-...` with 2 workers (debugger, reviewer). Advisor drives the task list.

### Full (default)
```text
/viper-team 'Build REST API for comment module with auth, CRUD, moderation'
```
Expected: Default Full 4-worker team (architect, coder, debugger, reviewer). Advisor drives.

### Custom Roster
```text
/viper-team --roles=coder,coder,reviewer --rationale='Two independent modules parallelizable' 'Implement auth and billing modules in parallel'
```
Expected: `coder-1`, `coder-2`, `reviewer`. Advisor assigns auth→coder-1, billing→coder-2.

### Error — Missing Rationale
```text
/viper-team --mode=architecture 'Migrate monolith to microservices'
```
Expected: Rejection requesting `--rationale`.

### Error — `lead` role
```text
/viper-team --roles=lead,coder,reviewer --rationale=test 'task'
```
Expected: Rejection — "Advisor is the lead. Workers only."

## Relationship to Other Skills

| Skill | Use When |
|---|---|
| `/viper-team` | Multi-role coding, Lv 21+ |
| `/pi:rescue` / `/pi:explore` | Single Pi task |
| `/codex:rescue` / `/codex:review` | Advisor direct, no team |
| `/self-improve` | PRD-driven evolution loop |

## Limitations (native Claude Code constraints)

- No nested teams (only Advisor can spawn)
- Advisor is fixed lead for team lifetime
- Codex is NOT a teammate — each worker invokes `codex exec` from their own Bash
- Pi is NOT a teammate — each worker invokes `pi-cc run` from their own Bash (caller auto-injected by hook)
- Workers cannot SendMessage the Advisor directly; they communicate via `TaskUpdate` status + idle notifications (Advisor receives automatically)
