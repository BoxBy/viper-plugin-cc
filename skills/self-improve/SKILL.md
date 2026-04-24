---
name: self-improve
description: PRD 기반 반복 개선. 작업 디렉토리의 PRD.md가 모든 것을 정의.
user-invocable: true
argument-hint: "{task_dir} [--ralph] [--dry-run] [rollback {timestamp}]"
---

# Self-Improve

작업 디렉토리의 PRD.md를 읽고 self-improving-agent를 spawn하여 반복 개선.

> 메인 에이전트용 spawn 가이드·함정은 프로젝트 루트 `CLAUDE.md` (자동 주입됨).

## 사용법

```bash
/self-improve {task_dir}        # {task_dir}/PRD.md 필수
```

## 독립 설치 — 다른 플러그인 불필요

이 플러그인은 **단독 설치만으로 동작**한다. Pi / Codex / OMC 는 전부 옵셔널:

- **Pi 부재**: `self-improving-agent.md` 가 자동으로 Haiku Bash fallback 사용 (`source ~/.claude/rules/model-manifest.env && claude -p --model "$LATEST_HAIKU"`). agent 규약 § "역할 분담" 참고.
  - ⚠️ **cross-plugin 주석**: `model-manifest.env` 는 **본 플러그인의 `/harness-install`** 이 생성한다. `/harness-install` 미실행 시 해당 파일이 없으므로 `source ... 2>/dev/null || true` 로 silently skip → `$LATEST_HAIKU` 미설정 상태로 `claude -p` 호출 시 Claude Code 기본 모델로 fallback. `/harness-install` 실행을 권장.
- **Codex 부재**: `self-improve-ralph.md` 의 `completed` status 검증 게이트가 "Advisor 자체 critic" 으로 degrade. section 4 및 본 skill 의 "OMC 미설치 시 대체" 블록 참고.
- **Stop Hook 부재**: Claude Code built-in `/loop` 또는 수동 재호출로 대체 (아래 모드 2/3 참고). 본 플러그인의 `hooks/ralph-stop-hook.sh` 가 stop hook 이벤트를 처리하므로, plugin hooks 가 정상 등록되면 별도 설치 불필요.
- **`/harness-install` 미실행**: tool-fallback.md 규약은 없지만, 3총사 문서 내부에 fallback 지시가 self-contained 로 박혀있다. 기능상 문제 없음.

최소 설치: `/plugin install self-improve@<marketplace>` 만으로 PRD 기반 연구 루프 작동 (`<marketplace>` 는 사용자가 `~/.claude/settings.json` 의 `extraKnownMarketplaces` 에 등록한 이름).

## 사전 조건

- `{task_dir}/PRD.md` 존재 필수
- PRD에 목표, 데이터, 수정 대상, 종료 조건이 명시되어 있어야 함

## 동작

1. `{task_dir}/PRD.md` 존재 확인
2. 디렉토리 구조 초기화 (없는 파일/폴더 생성)
3. `self-improving-agent` spawn:
   ```text
   {task_dir}/ 에서 self-improving iteration을 실행하라.
   PRD.md를 읽고 시작.
   ```

## 디렉토리 구조

자동 생성됨. 상세 정의는 `${CLAUDE_PLUGIN_ROOT}/agents/self-improving-agent.md` § "작업 디렉토리 구조" 참조. `PRD.md` 만 유저가 작성하면 나머지는 첫 spawn에서 초기화.

## 실행 모드

### 1. 단독 실행 (1회 iteration, 테스트용)

```bash
/self-improve {task_dir}
```

`self-improving-agent`가 1회 iteration(Phase 0→4) 실행 후 종료. 종료 상태(`status` 가 `completed`/`partial`/`blocked`) 도달 시에만 Phase 5(종료 보고)가 추가 실행됨.

> ⚠️ **제약**: 단독 실행에는 Ralph가 없으므로 `status="eval_pending"` 또는 `status="paused"` 를 재개할 주체가 없다. Phase 3 단계 4가 background eval을 띄우면 워커는 즉시 종료되고 `.done` 파일은 누구도 감지하지 않는다. 테스트용으로 1 iteration만 돌리려면 (a) `runs_per_candidate`/N을 축소해서 동기 완결 가능한 범위로 맞추거나, (b) 실패 허용하고 재시도 실행. 실제 루프는 Ralph 경유(모드 2/3)가 표준.

### Ralph 실행 모드 (Stop-Hook 기반)

Ralph 는 **Stop Hook 기반**으로 동작한다 (상세 규약: `${CLAUDE_PLUGIN_ROOT}/agents/ralph.md` + `hooks/ralph-stop-hook.sh`):
- Claude 가 작업을 완료하고 종료를 시도하면, stop hook 이 이를 가로채고 상태 파일(`~/.claude/ralph-state.json`)을 검사
- 루프가 활성(active=true)이면 종료를 차단하고 reason 을 다음 명령으로 주입
- iteration 카운트, max_iterations, circuit breaker 는 stop hook 에서 자동 관리
- Claude 는 매 iteration 에서 `ralph.md` + `self-improve-ralph.md` 의 행동 가이드에 따라 작업

### 2. Ralph 루프 실행 (권장)

```bash
/self-improve {task_dir} --ralph
```

또는 수동으로 상태 파일을 초기화한 후 작업 시작:

```bash
# 상태 파일 초기화 (stop hook 이 감지)
python3 -c "
import json, datetime
with open('$HOME/.claude/ralph-state.json', 'w') as f:
    json.dump({
        'active': True, 'iteration': 1, 'max_iterations': 50,
        'status': 'running', 'worker_agent': 'self-improving-agent',
        'task_dir': '{task_dir}', 'task_description': '...',
        'token_budget': 200000, 'codex_reject_streak': 0,
        'started_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    }, f, indent=2)
"
```

이후 Claude 가 self-improving-agent 규칙에 따라 작업하면, stop hook 이 자동으로 루프를 유지.

**stop hook 미지원 환경에서의 대체**:
- Claude Code built-in `/loop` 사용: `/loop /self-improve {task_dir}`
- 또는 매 iteration `/self-improve {task_dir}` 를 수동 반복 (status=running 이면 재호출)
- 또는 OMC `/ralph` 플러그인 사용 (별도 설치)

### 3. 병렬 실행 (여러 PRD 동시)

각 task_dir 별로 별도 Claude Code 세션에서 ralph 루프를 실행:
- 세션 1: `/self-improve {task_dir_1} --ralph`
- 세션 2: `/self-improve {task_dir_2} --ralph`

또는 단일 Advisor 에서 각 task_dir 별 Agent 를 `run_in_background: true` 로 병렬 spawn 후 각각 ralph 상태 파일 사용.

## Research 모드 (데이터 기반 가설/검증)

기존 `research-loop` 에이전트의 기능을 흡수. 데이터 기반 연구 질문(상관 분석, 축 발견, 평가 기준 최적화, 근본 원인 분석 등)에는 PRD.md를 아래 형식으로 작성하면 `self-improving-agent`가 가설→검증→수정 루프를 수행한다. 반복 동작(가설 생성/검증/롤백/방향 전환)은 워커 Phase 1~4 규약과 동일 — `${CLAUDE_PLUGIN_ROOT}/agents/self-improving-agent.md` 참조.

### PRD.md 템플릿 (research)

```markdown
# 목표
{자연어 연구 질문 또는 달성 목표}

# 데이터
- {파일 경로} (JSONL/JSON/CSV)

# 제약조건
- 사용 금지 변수: ...
- 결과 변수(종속변수): ...

# 종료 조건
- {지표} ≥ {임계값}  (예: R² ≥ 0.85, 일치율 ≥ 80%, ρ ≥ 0.7)

# 검증 방법
- 코드(Python/통계)로만 검증 — "아마 그럴 것이다"는 가설 아님
- 모든 발견에 p-value 또는 효과 크기 첨부
- n<30이면 소표본 경고
- 같은 가설 재시도 금지 (이전 실패 기록 확인)
```

### research_state.json 추가 필드

```json
{
  "objective": "...",
  "exit_criteria": {"metric": "r2", "threshold": 0.85},
  "best_result": {"r2": 0.488, "iter": 7},
  "plateau_count": 0,
  "history": [
    {
      "iter": 1,
      "hypothesis": "...",
      "result": {"r2": 0.45, "p_value": 0.001, "delta_r2": 0.12},
      "verdict": "partial",
      "reason": "R²=0.45 < 목표 0.85, 기존 대비 +0.12 개선"
    }
  ]
}
```

### 사용 예

```bash
/ralph "/self-improve {task_dir} 를 반복. {종료조건} 달성까지."
# OMC 없으면: /loop /self-improve {task_dir}   (built-in 스킬)
```

## Pi 활용 (PRD 공통)

워커 내부 규약(Phase/Pi 역할/메모리/학습 규칙)의 **single source of truth** 는 `${CLAUDE_PLUGIN_ROOT}/agents/self-improving-agent.md` 이다. 중복 기술 금지 (drift 방지). PRD.md 에 아래 한 줄만 포함하면 된다:

```markdown
## Pi 활용
agent.md 의 "역할 분담" 및 Phase 1~4 Pi 서브절차를 따른다 (링크: `${CLAUDE_PLUGIN_ROOT}/agents/self-improving-agent.md`). 추가 규정 필요 시 본 섹션에 append.
```

agent.md 내 Phase 별 Pi 책임 요약은 그 파일의 해당 섹션을 직접 참조 (Phase 1: 사전분석, Phase 2: 병렬 변형 / reverse-extract / self-challenge / Promptbreeder, Phase 3: pre-check + 통계 draft, Phase 4: regression 후보 draft, 공통 eval-은-반드시-Opus).

## 성공 패턴 참조 (PRD 공통)

다른 task_dir의 검증된 skill을 재사용할 수 있다:
```markdown
## 참조 가능한 성공 패턴
- `{task_dir}/memory/skills/` 및 sibling task_dir 의 `memory/skills/` 에서 관련 skill 탐색
- Phase 1에서 Glob 으로 발견 → contract_NNN.md 에 출처 명시 후 재사용
```
