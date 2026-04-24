# viper-plugin-cc

Claude Code 용 Viper 오케스트레이트 하네스 — Claude Code 네이티브 프리미티브(`TeamCreate` / `SendMessage` / `Agent`) 기반 멀티에이전트 코딩 팀.

[BoxBy/Viper](https://github.com/BoxBy/Viper/tree/develop)의 orchestrate harness를 Claude Code 플러그인 시스템에 이식.

## 왜 이 플러그인?

Claude Code 플러그인 시스템은 `skills/`, `agents/`, `hooks/` 는 자동 주입하지만 **`CLAUDE.md` 와 `rules/` 는 주입하지 않는다**. 이 플러그인이 그 gap 을 메운다:

1. `references/CLAUDE.md` — 세션 시작 시 자동 로드될 Advisor instruction
2. `references/rules/*.md` — `~/.claude/rules/` 에 있으면 자동 주입되는 rule 파일들
3. `/harness-install` skill — 위 파일들을 `~/.claude/` 에 symlink/copy/guide 3-모드 중 선택 설치

설치 후 어느 프로젝트에서 Claude Code 를 켜도 동일한 routing 과 thinking 규약이 적용된다.

## 하는 일

모든 Claude Code 세션에 **Tech Lead 스타일 Advisor**를 주입:

- **전역 라우팅** — Lv 0-100 난이도 기반 위임 (trivial → Pi, standard → `/viper-team`, complex → `/viper-team --mode=full`, architecture → `/viper-team --mode=architecture`)
- **`/viper-team` 스킬** — Claude Code 네이티브 `TeamCreate`로 architect/coder/debugger/reviewer 워커 스폰. Scale Mode: Full / Bug-Fix / Feature-Small / Refactor / Architecture
- **`/self-improve` 스킬** — PRD 기반 반복 개선 3총사 (skill + worker + ralph 루프). 데이터 기반 연구 또는 스펙 기반 반복 개선.
- **4-step 사고** — 분석 → 검증 → 자기수정 → 계획 (Lv 21+ 필수)
- **실행 계약** — 증거 기반 "완료 선언" 게이트 (cross-verify, 인용, 근원 원인, 재발 방지)
- **상태 표시줄** — 컨텍스트 사용량, 비용, 활성 팀 트리, PR 상태, Pi/Codex 속성
- **`/harness-install` 스킬** — CLAUDE.md + rules/를 `~/.claude/`에 배포 (symlink/copy/guide 모드)

## 구조

```
.claude-plugin/plugin.json    플러그인 매니페스트
agents/                       에이전트 정의
  architect.md, coder.md        viper-team 워커
  debugger.md, reviewer.md      viper-team 워커
  ralph.md                      범용 루프 에이전트 (stop-hook 기반)
  self-improving-agent.md       /self-improve 1회 반복 워커
  self-improve-ralph.md         /self-improve 루프 (ralph.md thin wrapper)
references/
  CLAUDE.md                   전역 Advisor 인스트럭션 (~/.claude/에 배포)
  RTK.md                      RTK (Rust Token Killer) 사용 가이드
  prd-template.md             /self-improve용 PRD 템플릿
  rules/                      자동 주입 규칙 파일
    advisor.md                Advisor 전용: routing, 4-step, anti-patterns, few-shot
    advisor-subagent.md       Subagent-first variant
    worker.md                 Worker 전용: 팀 통신, 에스컬레이션
    tool-fallback.md          Pi/Codex 부재 시 전환 + Pi Tier 라우팅
    common/                   공통 규약 (12개: code-quality, ddd-layers 등)
  team-bootstrap.md           각 팀 워커에 주입되는 공통 프로토콜
bin/
  codex-cc                    Codex CLI wrapper (caller tracking, session resume)
hooks/
  hooks.json                  SessionStart + Stop hook 등록
  ralph-stop-hook.sh          Ralph 루프 Stop hook
scripts/
  statusline.sh               Claude Code 상태 표시줄 진입점
  format.sh                   상태 표시줄 ANSI 렌더링
  plugin-update-check.sh      SessionStart 플러그인 업데이트 체크
skills/
  harness-install/            설치 스킬 (/harness-install)
  viper-team/                 팀 스폰 스킬 (/viper-team)
  self-improve/               PRD 기반 반복 개선 (/self-improve)
  update-plugins/             플러그인 자동 업데이트 (/update-plugins)
tests/                        상태 표시줄 테스트 스위트
```

## 구성

| 구성 | 위치 | 역할 |
|---|---|---|
| `references/CLAUDE.md` | — | 글로벌 instruction (Role, Gate, Simplicity First, Surgical Changes, Goal-Driven) |
| `references/RTK.md` | — | rtk(Rust Token Killer) hook 사용 가이드 |
| `references/rules/advisor.md` | — | Advisor 전용: routing table, 4-step thinking, anti-patterns, few-shot, subagent token diet, tool fallback |
| `references/rules/advisor-subagent.md` | — | Subagent-first variant (harness-install --harness-mode=subagent 시 선택) |
| `references/rules/worker.md` | — | Worker 전용: 팀 통신 프로토콜, 에스컬레이션, worker anti-patterns |
| `references/rules/tool-fallback.md` | — | Pi/Codex 부재 시 degrade 매핑 + Pi Tier (pi_tier) 조건부 라우팅 |
| `references/rules/common/` | — | 공통 규약 (code-quality, ddd-layers, execution-contract, thinking-guidelines, ubiquitous-language, complexity-matrix, episodic-feedback, roles, tools-reference, agent-evolution, vibe-and-rigor) |
| `skills/harness-install/SKILL.md` | — | 설치 skill — symlink/copy/guide 선택 + 모델 manifest 생성 |
| `skills/viper-team/`, `skills/self-improve/`, `skills/update-plugins/` | — | 팀 스폰, PRD 기반 반복 개선, 플러그인 자동 업데이트 |
| `hooks/hooks.json` | — | SessionStart (업데이트 체크) + Stop (Ralph 루프) hook |
| `scripts/` | — | statusline, format, plugin-update-check |
| `bin/codex-cc` | — | Codex CLI wrapper |
| `tests/test_statusline.sh` | — | 상태 표시줄 테스트 스위트 |

## 설치

### Git 저장소에서 설치

```bash
claude plugin install https://github.com/BoxBy/viper-plugin-cc
```

### 수동 설치

```bash
git clone https://github.com/BoxBy/viper-plugin-cc.git
cd viper-plugin-cc
```

`~/.claude/settings.json`에 플러그인 경로 추가:

```json
{
  "plugins": {
    "viper-plugin-cc": "/path/to/viper-plugin-cc"
  }
}
```

### 설치 후 설정

플러그인이 로드되면 Claude Code에서 harness install 스킬 실행:

```bash
/harness-install                      # 대화형 (AskUserQuestion 으로 모드 선택)
/harness-install --mode=symlink       # 비대화, 권장 — 플러그인 업데이트 자동 반영
/harness-install --mode=copy          # 물리 복사, 로컬 수정 보호됨
/harness-install --mode=guide         # 아무것도 안 하고 수동 명령만 출력
/harness-install --refresh-models     # 모델 manifest 만 재생성 (install 건너뜀)
```

#### 모드 차이

- **Symlink (권장)** — `~/.claude/{CLAUDE.md, RTK.md, rules/*.md}` 를 플러그인 `references/*` 로 심볼릭 링크. 플러그인 업데이트시 자동 반영.
- **Copy** — 물리 복사. 업데이트 시 `/harness-install` 재실행 필요.
- **Guide only** — 아무것도 안 한다. 복붙 명령어만 출력.

#### 백업

기존 `~/.claude/{CLAUDE.md, RTK.md, rules/}` 가 있으면 `~/.claude/.backup/<YYYYMMDD-HHMMSS>/` 로 이동 후 설치.

#### 모델 manifest 자동 resolve

install 시 `scripts/resolve-models.sh` 가:
1. `ANTHROPIC_API_KEY` 있으면 `api.anthropic.com/v1/models` 조회 → family 별 최신 id
2. 없으면 docs 페이지 fetch + HTML parse
3. 둘 다 실패 시 DEFAULT 상수 + "수동 확인 필요" 경고
4. codex 설치돼 있으면 `codex --help` 로 `--model`/`--effort` 플래그 지원 확인

결과는 `~/.claude/rules/model-manifest.md` 에 기록 (다른 plugin 들도 이 파일 `$LATEST_OPUS` 등 env 변수 참조).

#### 가용성 캐시

install 마지막 단계에서 `~/.claude/rules/availability-cache.json` 생성 — `tool-fallback.md` 가 세션 시작 시 읽고 Pi/Codex/OMC 부재에 따라 routing 을 자동 degrade 한다.

새 Claude Code 세션을 시작하면 활성화됩니다.

## 사전 조건 — RTK 필수

**RTK (Rust Token Killer)** 는 설치 전제 조건. 선택 사항 아님.

```bash
brew install rtk   # macOS/Linux, 권장
# 또는
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
# 또는
cargo install --git https://github.com/rtk-ai/rtk

rtk init -g        # Claude Code hook 설치 (PreToolUse)
```

설치 후 `rtk --version` 으로 확인. viper-plugin-cc 가 의존하는 것:
- 모든 Bash 툴콜의 output 을 PreToolUse hook 에서 자동 token-diet — 60–90% 절감
- `rtk gain` 으로 누적 절감량 확인
- viper-plugin-cc 의 subagent-token-diet 규약이 RTK hook 주입을 전제로 설계됨 → RTK 없으면 bash output 이 plain 으로 흘러서 컨텍스트 폭발

## 선택적 연동

플러그인은 **독립 실행** 가능. 아래는 선택 사항:

| 도구 | 용도 | 부재 시 동작 |
|------|------|-------------|
| [pi-plugin-cc](https://github.com/BoxBy/pi-plugin-cc) | 무료 Haiku 티어 교차 검증 (`pi-cc run`, `/pi:*` 스킬) | Haiku subagent fallback |
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | GPT-5 교차 패밀리 검증 (`codex exec`, `/codex:*` 스킬) | Advisor self-review |
| [ralph-loop](https://claude.com/ko-kr/plugins/ralph-loop) | 범용 에이전트 루프 (`/ralph`) — 내장 self-improve-ralph의 선택적 대안 | built-in `/loop` 대체 |

`tool-fallback.md`가 자동 degrade 매핑을 제공. viper-plugin-cc는 Pi / Codex 없이도 전역 routing/4-step thinking 이 동작 — **단, RTK 만은 필수.**

## 반복 루프 실행 메커니즘 — `/loop` vs `/ralph` vs `ralph-loop`

`/self-improve` 같은 반복 루프 skill 을 돌릴 때 사용할 실행자는 3 가지:

| 측면 | **built-in `/loop`** (기본값) | **OMC `/ralph`** | **`ralph-loop`** (Anthropic 공식) |
|---|---|---|---|
| 배포 | Claude Code 2.x 번들 skill | `oh-my-claudecode` 플러그인 | claude.com/plugins/ralph-loop (14만+ 설치) |
| 재실행 메커니즘 | `ScheduleWakeup` 툴 | Stop hook "work is NOT done" 주입 | Stop hook 이 유저 prompt 재-feed + 파일 상태 보존 |
| 종료 신호 | `ScheduleWakeup` 안 부르면 즉시 종료 | OMC circuit breaker / token budget | `--completion-promise` 문자열 |
| "work is NOT done" 회귀 | 없음 | **있음** | 없음 (공식이라 더 엄밀) |

**추천 경로**:
1. 기본은 `/loop` — 별도 설치 불필요
2. ralph persistence 패턴이 꼭 필요하면 `ralph-loop` (공식) 로 설치
3. OMC `/ralph` 는 지양 — stop-hook 회귀 재현됨

## 핵심 개념

### Lv 기반 라우팅

| 난이도 | 실행자 | 리뷰어 |
|--------|--------|--------|
| Lv 1-20 (trivial) | Pi | Advisor 빠른 확인 |
| Lv 21-50 (standard — 코드 작성) | `/viper-team` (Bug-Fix / Feature-Small / Refactor) | 팀 리뷰어 + Advisor |
| Lv 51-80 (complex) | `/viper-team` (Refactor / Full) | 팀 리뷰어 + Advisor + `/codex:review` |
| Lv 81+ (architecture) | `/viper-team --mode=architecture` (5명) | Opus critic + `/codex:adversarial-review` |

### Scale Mode (`/viper-team`)

| 모드 | 워커 | 사용 시나리오 |
|------|------|--------------|
| **full** (기본) | architect, coder, debugger, reviewer | 복잡도 불명확 |
| **bug-fix** | debugger, reviewer | 기존 동작 수정 |
| **feature-small** | coder, reviewer | 단일 모듈에 기능 추가 |
| **refactor** | architect, coder, reviewer | 구조 변경, 기능 유지 |
| **architecture** | architect, coder×2, debugger, reviewer | 다중 모듈 설계 |

### 사용 예시

```
/viper-team '댓글 모듈 REST API 구현 — auth, CRUD, moderation'
/viper-team --mode=bug-fix --rationale='페이지네이션 off-by-one' '페이지 카운트 수정'
/viper-team --roles=coder,coder,reviewer --rationale='두 개의 독립 모듈' '인증 및 결제 구현'
```

### Self-Improve (`/self-improve`)

```bash
# 1회 반복 (테스트)
/self-improve path/to/task_dir

# 반복 루프 (내장 ralph)
# self-improve-ralph 에이전트를 스폰하여 방향 검증 포함 자동 루프

# 공식 Ralph 플러그인 사용 시
/ralph "/self-improve path/to/task_dir 를 반복. 목표 달성까지."

# 대체 (Ralph 없음)
/loop /self-improve path/to/task_dir
```

## 핵심 규약 요약

### Advisor 4-step thinking (Lv 21+ 필수)

1. Analysis (Lv 0~100 self-assess, WHY-check)
2. Verification (knowledge gap, ambiguity LOW/MEDIUM/HIGH 분류)
3. Self-Correction (critique + refine)
4. Plan + **Ping-pong gate**: `codex exec "Review this plan: ... Critical issues only, ≤120 words"` → 반영 후 재제출

### "Declare done" execution contract

tool_use 로그 기반 4 프로파일 (code_change / research / file_task / text_answer). 각 프로파일은 read-before-write, WHY 인용, 테스트 실행 증거 등 체크박스로 VERIFIED / PARTIAL / BLOCKED 판정.

## 라이선스

AGPL-3.0
