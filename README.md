# viper-plugin-cc

[**한국어**](README_ko.md)

Claude Code orchestration harness built on native primitives (`TeamCreate` / `SendMessage` / `Agent`) — multi-agent coding team for Claude Code.

Port of [Viper](https://github.com/BoxBy/Viper/tree/develop)'s orchestrate harness to the Claude Code plugin system.

## Quick Start

**Step 1: Install**

```bash
/plugin marketplace add BoxBy/viper-plugin-cc
/plugin install viper@viper-plugin-cc
/reload-plugins
```

**Step 2: Deploy harness**

```bash
/harness-install
```

**Step 3: Just use Claude Code**

```
Fix the pagination bug in the comment module
```

That's it. The Advisor auto-detects task difficulty and orchestrates accordingly — no special commands needed.

### How it works under the hood

| What you type | What happens |
|---|---|
| "Fix this typo" (trivial) | Advisor handles directly → done |
| "Add login API" (standard) | Advisor → `/viper-team --mode=feature-small` (coder + reviewer) |
| "Refactor the auth module" (complex) | Advisor → `/viper-team --mode=refactor` (architect + coder + reviewer) |
| "Design the payment system" (architecture) | Advisor → `/viper-team --mode=architecture` (5 workers) |

Every code change is automatically cross-verified (Pi + Codex when available), and the Advisor applies 4-step thinking for non-trivial tasks. You don't need to know any of this — just describe what you want.

### Explicit commands (optional)

Power users can bypass auto-routing:

```
/viper-team 'Comment module REST API — auth, CRUD, moderation'
/viper-team --mode=bug-fix --rationale='pagination off-by-one' 'Fix page count'
/self-improve path/to/task_dir
```

## What it does

Injects a **Tech Lead-style Advisor** into every Claude Code session:

- **Global routing** — Lv 0-100 difficulty-based delegation (trivial → Pi, standard → `/viper-team`, complex → `/viper-team --mode=full`, architecture → `/viper-team --mode=architecture`)
- **`/viper-team` skill** — Spawns architect/coder/debugger/reviewer workers via Claude Code native `TeamCreate`. Scale Modes: Full / Bug-Fix / Feature-Small / Refactor / Architecture
- **`/self-improve` skill** — PRD-driven iterative improvement trio (skill + worker + ralph loop). Data-driven research or spec-based iterative refinement.
- **4-step thinking** — Analysis → Verification → Self-Correction → Plan (mandatory for Lv 21+)
- **Execution contract** — Evidence-based "declare done" gate (cross-verify, citations, root cause, recurrence prevention)
- **Status line** — Context usage, cost, active team tree, PR status, Pi/Codex attribution
- **`/harness-install` skill** — Deploy CLAUDE.md + rules/ to `~/.claude/` (symlink/copy/guide modes)

## Structure

```
.claude-plugin/plugin.json    Plugin manifest
agents/                       Agent definitions
  architect.md, coder.md        viper-team workers
  debugger.md, reviewer.md      viper-team workers
  ralph.md                      General-purpose loop agent (stop-hook based)
  self-improving-agent.md       /self-improve single-iteration worker
  self-improve-ralph.md         /self-improve loop (ralph.md thin wrapper)
references/
  CLAUDE.md                   Global Advisor instruction (deployed to ~/.claude/)
  prd-template.md             PRD template for /self-improve
  rules/                      Auto-injected rule files
    advisor.md                Advisor: routing, 4-step, anti-patterns, few-shot
    advisor-subagent.md       Subagent-first variant
    worker.md                 Worker: team communication, escalation
    tool-fallback.md          Pi/Codex absence fallback + Pi Tier routing
    common/                   Shared conventions (12: code-quality, ddd-layers, etc.)
  team-bootstrap.md           Common protocol injected into each team worker
bin/
  codex-cc                    Codex CLI wrapper (caller tracking, session resume)
hooks/
  hooks.json                  SessionStart + Stop hook registration
  ralph-stop-hook.sh          Ralph loop Stop hook
scripts/
  statusline.sh               Claude Code status line entry point
  format.sh                   Status line ANSI rendering
  plugin-update-check.sh      SessionStart plugin update check
skills/
  harness-install/            Install skill (/harness-install)
  viper-team/                 Team spawn skill (/viper-team)
  self-improve/               PRD-based iterative improvement (/self-improve)
  update-plugins/             Plugin auto-update (/update-plugins)
tests/                        Status line test suite
```

## Installation

### From marketplace (recommended)

```bash
/plugin marketplace add BoxBy/viper-plugin-cc
/plugin install viper@viper-plugin-cc
/reload-plugins
```

### From URL

```bash
claude plugin install https://github.com/BoxBy/viper-plugin-cc
```

### Manual

```bash
git clone https://github.com/BoxBy/viper-plugin-cc.git
cd viper-plugin-cc
```

Add the plugin path to `~/.claude/settings.json`:

```json
{
  "plugins": {
    "viper-plugin-cc": "/path/to/viper-plugin-cc"
  }
}
```

### Post-install setup

Once the plugin loads, run the harness install skill in Claude Code:

```bash
/harness-install                      # Interactive (mode selection via AskUserQuestion)
/harness-install --mode=symlink       # Non-interactive, recommended — auto-reflects plugin updates
/harness-install --mode=copy          # Physical copy, local edits protected
/harness-install --mode=guide         # No-op, outputs manual commands only
/harness-install --refresh-models     # Regenerate model manifest only (skip install)
```

#### Mode differences

- **Symlink (recommended)** — Symlinks `~/.claude/{CLAUDE.md, rules/*.md}` to plugin `references/*`. Plugin updates are reflected automatically.
- **Copy** — Physical copy. Requires re-running `/harness-install` on updates.
- **Guide only** — Does nothing. Outputs copy-paste commands only.

#### Backup

Existing `~/.claude/{CLAUDE.md, rules/}` are moved to `~/.claude/.backup/<YYYYMMDD-HHMMSS>/` before installation.

#### Model manifest auto-resolve

During install, `scripts/resolve-models.sh`:
1. If `ANTHROPIC_API_KEY` is set → queries `api.anthropic.com/v1/models` → latest id per family
2. Otherwise → fetches docs page + HTML parse
3. If both fail → DEFAULT constants + "manual verification required" warning
4. If codex is installed → checks `codex --help` for `--model`/`--effort` flag support

Results are written to `~/.claude/rules/model-manifest.md` (other plugins can reference `$LATEST_OPUS` etc. from this file).

#### Availability cache

The final install step generates `~/.claude/rules/availability-cache.json` — `tool-fallback.md` reads this at session start and auto-degrades routing based on Pi/Codex/OMC presence.

Start a new Claude Code session to activate.

## Optional Integrations

The plugin runs **standalone**. The following are optional:

| Tool | Purpose | Fallback when absent |
|------|---------|---------------------|
| [pi-plugin-cc](https://github.com/BoxBy/pi-plugin-cc) | Free Haiku-tier cross-verification (`pi-cc run`, `/pi:*` skills) | Haiku subagent fallback |
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | GPT-5 cross-family verification (`codex exec`, `/codex:*` skills) | Advisor self-review |
| [ralph-loop](https://claude.com/ko-kr/plugins/ralph-loop) | General-purpose agent loop (`/ralph`) — optional alternative to built-in self-improve-ralph | Built-in `/loop` fallback |

`tool-fallback.md` provides automatic degradation mappings. viper-plugin-cc works without Pi or Codex.

## Iterative Loop Execution — `/loop` vs `/ralph` vs `ralph-loop`

Three runners available for iterative loop skills like `/self-improve`:

| Aspect | **built-in `/loop`** (default) | **OMC `/ralph`** | **`ralph-loop`** (official) |
|---|---|---|---|
| Distribution | Claude Code 2.x bundled skill | `oh-my-claudecode` plugin | claude.com/plugins/ralph-loop (140k+ installs) |
| Re-exec mechanism | `ScheduleWakeup` tool | Stop hook "work is NOT done" injection | Stop hook re-feeds user prompt + file state preservation |
| Termination signal | Not calling `ScheduleWakeup` = immediate stop | OMC circuit breaker / token budget | `--completion-promise` string |
| "work is NOT done" regression | None | **Yes** | None (more rigorous, official) |

**Recommended path**:
1. Default is `/loop` — no additional install needed
2. If ralph persistence pattern is required, install `ralph-loop` (official)
3. Avoid OMC `/ralph` — stop-hook regression reproduced

## Key Concepts

### Lv-based Routing

| Difficulty | Executor | Reviewer |
|------------|----------|----------|
| Lv 1-20 (trivial) | Pi | Advisor quick check |
| Lv 21-50 (standard — code writing) | `/viper-team` (Bug-Fix / Feature-Small / Refactor) | Team reviewer + Advisor |
| Lv 51-80 (complex) | `/viper-team` (Refactor / Full) | Team reviewer + Advisor + `/codex:review` |
| Lv 81+ (architecture) | `/viper-team --mode=architecture` (5 workers) | Opus critic + `/codex:adversarial-review` |

### Scale Mode (`/viper-team`)

| Mode | Workers | Use case |
|------|---------|----------|
| **full** (default) | architect, coder, debugger, reviewer | Unclear complexity |
| **bug-fix** | debugger, reviewer | Fixing existing behavior |
| **feature-small** | coder, reviewer | Adding feature to single module |
| **refactor** | architect, coder, reviewer | Structural change, preserved functionality |
| **architecture** | architect, coder×2, debugger, reviewer | Multi-module design |

### Usage Examples

```
/viper-team 'Comment module REST API — auth, CRUD, moderation'
/viper-team --mode=bug-fix --rationale='pagination off-by-one' 'Fix page count'
/viper-team --roles=coder,coder,reviewer --rationale='two independent modules' 'Implement auth and payment'
```

### Self-Improve (`/self-improve`)

```bash
# Single iteration (test)
/self-improve path/to/task_dir

# Iterative loop (built-in ralph)
# Spawns self-improve-ralph agent for auto-loop with direction verification

# Using official Ralph plugin
/ralph "Iterate /self-improve path/to/task_dir. Until goal achieved."

# Alternative (no Ralph)
/loop /self-improve path/to/task_dir
```

## Core Conventions Summary

### Advisor 4-step thinking (mandatory for Lv 21+)

1. Analysis (Lv 0~100 self-assess, WHY-check)
2. Verification (knowledge gap, ambiguity LOW/MEDIUM/HIGH classification)
3. Self-Correction (critique + refine)
4. Plan + **Ping-pong gate**: `codex exec "Review this plan: ... Critical issues only, ≤120 words"` → apply feedback → resubmit

### "Declare done" execution contract

Tool_use log-based 4 profiles (code_change / research / file_task / text_answer). Each profile has checkboxes for read-before-write, WHY citation, test execution evidence → VERIFIED / PARTIAL / BLOCKED verdict.

## License

AGPL-3.0
