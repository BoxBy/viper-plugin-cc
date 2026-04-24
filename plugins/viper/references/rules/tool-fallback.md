---
description: Graceful degradation mappings when pi/codex tools are partially or fully absent. Check availability before applying rules that depend on external tools.
globs: []
alwaysApply: true
---

# Tool Availability Fallback

본 harness 의 모든 rule / few-shot / `~/.claude/CLAUDE.md` 본문은 `pi` / `codex` 도구가 설치되어 있다고 전제한다. 그러나 실제 환경에선 일부 또는 전체가 없을 수 있다. **rule 이 실제 적용되기 전**, Advisor 는 `available-skills` 리스트와 PATH 를 확인하고, 부재 시 아래 대체를 적용한다.

본 fallback 규약은 **본문의 모든 `/pi:*` / `/codex:*` 참조보다 우선**한다.

---

## Pi 부재 감지
- `which pi-cc` 실패 **또는**
- `Skill` 툴의 `available-skills` 리스트에 `pi:*` 스킬이 없음

### Pi 대체 매핑

> ⚠️ **`Agent()` 시그니처 주의**: Claude Code 의 `Agent` 툴은 `description` 과 `prompt` 가 **필수**, `subagent_type` / `model` / `run_in_background` 는 옵셔널. 시그니처:
> `Agent({description: "<짧은 할일>", prompt: "<지시>", subagent_type?, model?, run_in_background?})`

| 원래 Pi 호출 | 대체 | 실행 모드 |
|-------------|------|---------|
| `/pi:cross-verify`, `/pi:review` (**blocking gate** — 결과 읽고 다음 단계) | **Haiku subagent foreground** — `Agent({description: "cross-verify diff", prompt: "...", subagent_type: "general-purpose", model: "haiku"})` | **foreground (blocking)** — gate 성격이므로 background 금지. 결과 평가 후 진행/차단 결정. |
| `/pi:ask`, `/pi:explore`, `/pi:brainstorm` (exploratory, non-gate) | **Haiku subagent** — `Agent({description: "explore X", prompt: "...", subagent_type: "general-purpose", model: "haiku", run_in_background: true})` | background 가능 (결과 수집 후 Advisor 가 종합) |
| `/pi:rescue`, `/pi:test` (실제 코드 작성/테스트) | **Sonnet executor subagent** — `Agent({description: "implement X", prompt: "...", subagent_type: "general-purpose", model: "sonnet"})` | 작업 크기 따라 둘 다 가능 (작으면 foreground, 크면 background) |
| `pi-cc run "..." --bg` (CLI 원시 호출) | **Bash `source ~/.claude/rules/model-manifest.env && claude -p --model "$LATEST_HAIKU" "..."`** (nested non-interactive session) | 원래 의도 유지 |

**이유**: Pi 의 free-compute 이점 상실 → Haiku 가 비용효율 + 독립 컨텍스트 측면에서 최근사. Sonnet 은 code-writing 계열 fallback.

### Pi Tier Conditional Routing (availability-cache.json → pi_tier)

`pi_tier` 값에 따라 Pi 가 대체할 수 있는 작업 범위가 결정된다. 세션 시작 시 `~/.claude/rules/availability-cache.json` 의 `pi_tier` 를 읽어 적용.

| pi_tier | Pi substitutes | Pi does NOT substitute |
|---------|---------------|----------------------|
| `"haiku"` (default) | Haiku 작업 (탐색, 교차 검증, 사소한 편집) | Sonnet 코드 작성, Opus 작업 |
| `"sonnet"` | Haiku + Sonnet READ/REVIEW + Sonnet 코드 작성 | Opus 작업 |
| `null` (Pi 부재) | 없음 — 위 fallback 테이블 적용 | 전체 |

**pi_tier == "sonnet" 시 추가 적용**:
- `/pi:rescue`, `/pi:test` 는 Sonnet 급 출력 생성 → routing table 에서 Lv 21-50 코드 작업에 Pi 를 Sonnet executor 로 대체 허용
- Pi 대체 매핑 테이블의 `/pi:rescue`, `/pi:test` 행에서 `subagent_type: "general-purpose", model: "sonnet"` 대신 Pi 를 그대로 사용 (이미 Sonnet 급이므로 fallback 불필요)

---

## Codex 부재 감지
- `which codex` 실패 **또는**
- `available-skills` 에 `codex:*` 스킬이 없음

### Codex 대체 매핑
| 원래 Codex 호출 | 대체 |
|----------------|------|
| `/codex:rescue` (Advisor-direct single-shot — NOT primary; primary is `/viper-team`) | **Advisor 인라인 처리** (Advisor 본인 Write/Edit) **또는** `Agent({description: "code write", prompt: "...", subagent_type: "general-purpose", model: "opus"})` fallback. For team-context cross-family, worker-level `codex exec` falls back to Advisor-supplied cross-check instead. |
| `/codex:review`, `/codex:adversarial-review` | **Advisor self-review** (집중 diff 리뷰) **+** `Agent({description: "critic review", prompt: "...", subagent_type: "general-purpose", model: "opus"})` (있으면) |
| `codex exec --skip-git-repo-check "..."` ping-pong (Lv 21+ plan review gate) | **Advisor 자체 critic 1-pass** (플랜을 Lv별 체크리스트 + anti-patterns 와 직접 대조) **+** `/pi:ask` (Pi 있으면) 로 second opinion |

**degrade 경고 필수**: Codex fallback 이 발동되면 Advisor 는 즉시 다음을 명시해야 한다: "⚠️ Codex cross-family verification 부재 — single-model 한계 감수 상태".

**이유**: cross-model(GPT-5) 검증 이점 상실. 같은 Claude family 안에서라도 self-review 는 하는 게 skip 보다 낫다.

---

## 감지 시점 (필수 절차)

1. **세션 시작 시 1회 캐시**: Advisor 는 `/harness-install` 설치 완료 후 `~/.claude/rules/availability-cache.json` 에 `pi`, `pi_tier`, `codex` 가용성 기록. 세션 시작 시 이 파일 읽어서 자동 적용. `pi_tier` 는 `"haiku"`, `"sonnet"`, `null` (Pi 부재) 중 하나이며, advisor.md § Routing 의 Pi substitution map 과 본 파일의 대체 매핑 범위를 결정.
2. **rule 이 실제 트리거될 때**: `Skill` 호출 직전 available-skills 재확인 (캐시 stale 대비).
3. **모델 ID** 는 `~/.claude/rules/model-manifest.env` (`/harness-install` 이 생성) 을 source 해서 `$LATEST_HAIKU`, `$LATEST_OPUS`, `$CODEX_MODEL` 로 참조. manifest 서술본(`model-manifest.md`) 은 사람이 읽을 수 있는 요약.

---

## 금지 사항

- Pi 부재 시 **"그냥 스킵" 금지**. 반드시 Haiku/Sonnet fallback 경유.
- Codex 부재 시 **plan review gate 생략 금지**. 최소 Advisor 자체 critic 1-pass 필수 (Lv 21+).
- Advisor 가 "Pi 있는지 확인 안 하고 그냥 호출" → 호출 실패 → fallback 전환 패턴: **가능하지만 비효율**. 세션 캐시를 선호.
- "Pi 가 없으니 신뢰도 낮추자" 로 rule 자체를 약화시키지 마라. fallback 은 동일 품질 보장 목표. 열화는 명시적 degrade 로그만.

---

## 관련

- [Routing](advisor.md) — executor 선택 원칙
- [Anti-patterns](advisor.md) — "confidence 는 문제다", Pi skip 금지 원칙
- [Execution contract](common/execution-contract.md) — cross-verify 증거 수집
