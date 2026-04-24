# viper-plugin-cc

[English](README.md)

Claude Code 용 Viper 오케스트레이트 하네스 — Claude Code 네이티브 프리미티브(`TeamCreate` / `SendMessage` / `Agent`) 기반 멀티에이전트 코딩 팀.

[BoxBy/Viper](https://github.com/BoxBy/Viper/tree/develop)의 orchestrate harness를 Claude Code 플러그인 시스템에 이식.

## 하는 일

모든 Claude Code 세션에 **Tech Lead 스타일 Advisor**를 주입:

- **전역 라우팅** — Lv 0-100 난이도 기반 위임 (trivial → Pi, standard → `/viper-team`, complex → `/viper-team --mode=full`, architecture → `/viper-team --mode=architecture`)
- **`/viper-team` 스킬** — Claude Code 네이티브 `TeamCreate`로 architect/coder/debugger/reviewer 워커 스폰. Scale Mode: Full / Bug-Fix / Feature-Small / Refactor / Architecture
- **`/self-improve` 스킬** — PRD 기반 반복 개선 3총사 (skill + worker + ralph 루프). 데이터 기반 연구 또는 스펙 기반 반복 개선.
- **4-step 사고** — 분석 → 검증 → 자기수정 → 계획 (Lv 21+ 필수)
- **실행 계약** — 증거 기반 "완료 선언" 게이트 (cross-verify, 인용, 근원 원인, 재발 방지)
- **상태 표시줄** — 컨텍스트 사용량, 비용, 활성 팀 트리, PR 상태, Pi/Codex 속성
- **`/harness-install` 스킬** — CLAUDE.md + rules/를 `~/.claude/`에 배포 (symlink/copy/guide 모드)

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

```
/harness-install
```

`CLAUDE.md` + `rules/*.md`를 `~/.claude/`에 배포하고 모델 manifest를 생성합니다. symlink(권장), copy, guide-only 모드 중 선택.

새 Claude Code 세션을 시작하면 활성화됩니다.

## 선택적 연동

플러그인은 **독립 실행** 가능. 아래는 선택 사항:

| 도구 | 용도 | 설치 |
|------|------|------|
| [pi-plugin-cc](https://github.com/BoxBy/pi-plugin-cc) | 무료 Haiku 티어 교차 검증 (`pi-cc run`, `/pi:*` 스킬) | 별도 플러그인 |
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | GPT-5 교차 패밀리 검증 (`codex exec`, `/codex:*` 스킬) | 별도 플러그인 |
| [ralph-loop](https://claude.com/ko-kr/plugins/ralph-loop) | 범용 에이전트 루프 (`/ralph`) — 내장 self-improve-ralph의 선택적 대안 | 공식 플러그인 |

Pi 또는 Codex가 없으면 `tool-fallback.md`가 Claude 네이티브 서브에이전트(Haiku/Sonnet)로 자동 전환.

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

## 라이선스

AGPL-3.0
