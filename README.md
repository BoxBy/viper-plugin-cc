# viper-plugin-cc

전역 Advisor 하네스. `CLAUDE.md` + `rules/*.md` + `/harness-install` skill 로 구성되어, Tech-Lead 식 역할 분담·Lv 0~100 기반 routing·4-step thinking·execution contract 를 모든 Claude Code 세션에 주입한다.

## 왜 이 플러그인?

Claude Code 플러그인 시스템은 `skills/`, `agents/`, `hooks/` 는 자동 주입하지만 **`CLAUDE.md` 와 `rules/` 는 주입하지 않는다**. 이 플러그인이 그 gap 을 메운다:

1. `references/CLAUDE.md` — 세션 시작 시 자동 로드될 Advisor instruction
2. `references/rules/*.md` — `~/.claude/rules/` 에 있으면 자동 주입되는 rule 파일들
3. `/harness-install` skill — 위 파일들을 `~/.claude/` 에 symlink/copy/guide 3-모드 중 선택 설치

설치 후 어느 프로젝트에서 Claude Code 를 켜도 동일한 routing 과 thinking 규약이 적용된다.

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

```bash
/harness-install                      # 대화형 (AskUserQuestion 으로 모드 선택)
/harness-install --mode=symlink       # 비대화, 권장 — 플러그인 업데이트 자동 반영
/harness-install --mode=copy          # 물리 복사, 로컬 수정 보호됨
/harness-install --mode=guide         # 아무것도 안 하고 수동 명령만 출력
/harness-install --refresh-models     # 모델 manifest 만 재생성 (install 건너뜀)
```

### 모드 차이

- **Symlink (권장)** — `~/.claude/{CLAUDE.md, RTK.md, rules/*.md}` 를 플러그인 `references/*` 로 심볼릭 링크. 플러그인 업데이트시 자동 반영. 유저가 로컬에서 rule 수정하면 원본 touch (주의).
- **Copy** — 물리 복사. 업데이트 시 `/harness-install` 재실행 필요. 로컬 수정 보호됨.
- **Guide only** — 아무것도 안 한다. 복붙 명령어만 출력.

### 백업

기존 `~/.claude/{CLAUDE.md, RTK.md, rules/}` 가 있으면 `~/.claude/.backup/<YYYYMMDD-HHMMSS>/` 로 이동 후 설치.

### 모델 manifest 자동 resolve

install 시 `scripts/resolve-models.sh` 가:
1. `ANTHROPIC_API_KEY` 있으면 `api.anthropic.com/v1/models` 조회 → family 별 최신 id
2. 없으면 docs 페이지 fetch + HTML parse
3. 둘 다 실패 시 DEFAULT 상수 + "수동 확인 필요" 경고
4. codex 설치돼 있으면 `codex --help` 로 `--model`/`--effort` 플래그 지원 확인

결과는 `~/.claude/rules/model-manifest.md` 에 기록 (다른 plugin 들도 이 파일 `$LATEST_OPUS` 등 env 변수 참조).

### 가용성 캐시

install 마지막 단계에서 `~/.claude/rules/availability-cache.json` 생성 — `tool-fallback.md` 가 세션 시작 시 읽고 Pi/Codex/OMC 부재에 따라 routing 을 자동 degrade 한다.

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
- 모든 Bash 툴콜의 output 을 PreToolUse hook 에서 자동 token-diet — 60–90% 절감 (소스: [rtk-ai/rtk](https://github.com/rtk-ai/rtk))
- `rtk gain` 으로 누적 절감량 확인
- viper-plugin-cc 의 subagent-token-diet 규약이 RTK hook 주입을 전제로 설계됨 → RTK 없으면 bash output 이 plain 으로 흘러서 컨텍스트 폭발

## 의존 플러그인 / 도구 — 선택 사항

RTK 외의 타 플러그인은 전부 optional. 부재 시 degrade:

- **Pi 부재** → 무료 compute 없이 Haiku 4.5 fallback
- **Codex 부재** → cross-family verification 없이 Advisor self-review
- **OMC 부재** → tier-0 orchestration 없이 built-in `/loop`, `Agent`, `TeamCreate` 로 대체
- **`ralph-loop` 부재** → built-in `/loop` 으로 대체. ralph 가 꼭 필요하면 claude.com/plugins/ralph-loop (Anthropic 공식) 설치 권장 — OMC `/ralph` 는 지양.

`tool-fallback.md` 가 자동 degrade 매핑을 제공. viper-plugin-cc 는 Pi / Codex / OMC / ralph-loop 없이도 전역 routing/4-step thinking 이 동작 — **단, RTK 만은 필수.**

## 반복 루프 실행 메커니즘 — `/loop` vs `/ralph` vs `ralph-loop`

`/self-improve` 같은 반복 루프 skill 을 돌릴 때 사용할 실행자는 3 가지:

| 측면 | **built-in `/loop`** (기본값) | **OMC `/ralph`** | **`ralph-loop`** (Anthropic 공식) |
|---|---|---|---|
| 배포 | Claude Code 2.x 번들 skill | `oh-my-claudecode` 플러그인 | claude.com/plugins/ralph-loop (14만+ 설치) |
| 재실행 메커니즘 | `ScheduleWakeup` 툴 (모델이 스스로 예약) | Stop hook "work is NOT done" 주입 | Stop hook 이 유저 prompt 재-feed + 파일 상태 보존 |
| 종료 신호 | 모델이 `ScheduleWakeup` 안 부르면 즉시 종료 | OMC circuit breaker / token budget | `--completion-promise` 문자열 (예: `DONE`) |
| "work is NOT done" 회귀 | 없음 | **있음** (실측 `/insights` §2) | 없음 (공식이라 더 엄밀) |

**추천 경로**:
1. 기본은 `/loop` — 별도 설치 불필요
2. ralph persistence 패턴이 꼭 필요하면 `ralph-loop` (공식) 로 설치
3. OMC `/ralph` 는 지양 — stop-hook 회귀 재현됨

## 핵심 규약 요약

### Advisor 4-step thinking (Lv 21+ 필수)

1. Analysis (Lv 0~100 self-assess, WHY-check)
2. Verification (knowledge gap, ambiguity LOW/MEDIUM/HIGH 분류)
3. Self-Correction (critique + refine)
4. Plan + **Ping-pong gate**: `codex exec "Review this plan: ... Critical issues only, ≤120 words"` → 반영 후 재제출

### Lv 기반 routing (advisor.md)

| Lv | Executor | Reviewer |
|---|---|---|
| 1-20 trivial | Pi | Advisor quick |
| 21-50 read/review | Pi | Advisor |
| 21-50 code write | `/codex:rescue` | Advisor + `/pi:cross-verify` |
| 51-80 complex | `/codex:rescue` or Opus | Advisor + `/pi:cross-verify` + `/codex:review` |
| 81+ architecture | Advisor plans → mix | Opus critic + `/codex:adversarial-review` |

### "Declare done" execution contract

tool_use 로그 기반 4 프로파일 (code_change / research / file_task / text_answer). 각 프로파일은 read-before-write, WHY 인용, 테스트 실행 증거 등 체크박스로 VERIFIED / PARTIAL / BLOCKED 판정.

## 관련 파일

- `references/CLAUDE.md` — 설치될 전역 instruction
- `references/rules/*.md` — 설치될 rule 모음
- `skills/harness-install/SKILL.md` — 설치 skill 절차
- `skills/harness-install/scripts/resolve-models.sh` — 모델 dynamic resolve
- `~/.claude/rules/model-manifest.md` — install 결과 (설치 시 생성)
- `~/.claude/rules/availability-cache.json` — tool 가용성 (설치 시 생성)

## 라이선스

MIT (wrtn-tech).
