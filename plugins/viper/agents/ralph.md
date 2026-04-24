---
name: ralph
description: Ralph loop behavior guide. When a ralph state file is active, this defines what Claude does each iteration — status dispatch, verification, and state updates. The stop hook handles loop continuation; this agent defines the work.
tools: Read, Grep, Glob, Write, Bash, Agent, Skill, SendMessage
---

# Ralph — Stop-Hook Loop Behavior

Ralph 는 **Stop Hook 기반 루프**다. `hooks/ralph-stop-hook.sh` 가 Claude 의 종료를 가로채고, 상태 파일(`~/.claude/ralph-state.json`)을 검사하여 계속 진행할지 결정한다. 이 파일은 루프가 활성일 때 **Claude 가 매 iteration 에서 수행할 행동**을 정의한다.

## 시작 방법

호출자(SKILL 또는 사용자)가 상태 파일을 초기화하면 루프가 시작된다:

```bash
python3 -c "
import json
with open('$HOME/.claude/ralph-state.json', 'w') as f:
    json.dump({
        'active': True,
        'iteration': 1,
        'max_iterations': 50,
        'status': 'running',
        'mode': 'A',
        'worker_agent': '{agent type}',
        'task_dir': '{path}',
        'task_description': '{desc}',
        'token_budget': 200000,
        'codex_reject_streak': 0,
        'started_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    }, f, indent=2)
"
```

## 매 Iteration 행동 가이드

stop hook 이 `{"decision":"block","reason":"..."}` 을 반환하면 Claude 는 reason 을 다음 명령으로 받는다. 매 iteration 에서:

### 1. 상태 파일 읽기

```bash
cat ~/.claude/ralph-state.json
```

iteration, status, task_dir, worker_agent, task_description 을 파악.

### 2. Status 기반 분기

| Worker status | Claude 행동 |
|---|---|
| **`running`** | 작업 디렉토리에서 다음 iteration 작업 수행. 완료 후 상태 파일 갱신. |
| **`eval_pending`** | 외부 평가 대기 중. `.done` 센티넬 파일 확인. 없으면 "대기 중" 선언 후 종료 → stop hook 이 다시 연결. |
| **`paused`** | 승인 필요. `inbox.md` 확인 → 즉시 판단 가능하면 기록 + running 복원. 유저 판단 필요 시 SendMessage 로 보고. |
| **`completed`** | Codex cross-verify 실행. 검증 통과 시 루프 종료(active=false). 실패 시 running 복원 + reject_streak++. |
| **`blocked`** / **`partial`** | 종료 보고서 작성. active=false 설정. |

### 3. 작업 수행

task_dir 의 파일들을 읽고, worker_agent 정의(agents/{name}.md)의 규칙에 따라 1회 iteration 작업을 수행.

### 4. 상태 갱신

iteration 완료 후 상태 파일 갱신:

```bash
python3 -c "
import json
with open('$HOME/.claude/ralph-state.json') as f: s = json.load(f)
s['status'] = '{new_status}'  # running | completed | blocked | partial | paused
# 다른 필드 필요시 갱신
with open('$HOME/.claude/ralph-state.json', 'w') as f: json.dump(s, f, indent=2)
"
```

## Completed 검증 (Cross-verify)

status 가 `completed` 가 되면 Codex cross-verify 를 실행:

```bash
source ~/.claude/rules/model-manifest.env 2>/dev/null || true
codex exec --skip-git-repo-check --model "$CODEX_MODEL" "$CODEX_EFFORT_FLAG" "$CODEX_EFFORT" \
  "Verify completion claim. 종료 조건: [조건]. 현재 결과: [결과]. 진짜 충족? Under 120 words. If legitimate, say 'Confirmed'."
```

- **Codex "Confirmed"** → `active=false`, 루프 종료. `codex_reject_streak = 0` 리셋.
- **Codex 거부** → `inbox.md` 에 소견 기록, `status=running` 복원, `codex_reject_streak++`. streak ≥ 3 → `status=blocked`.
- **Codex 부재** → Advisor self-critic 1-pass (cross-family 검증 degraded 경고).

## Pi 사전 검증 (권장)

매 iteration 완료 후 Pi 가 draft 요약 → Claude(Opus) 가 최종 판정:

```text
/pi:explore "상태 파일 요약: [ralph-state 내용]. 변경 요지: [1~2문장]. (1) 방향 이탈 후보 (2) 이전 실패 재현 징후 (3) status 근거. Concerns만 나열, 판정 금지."
```

**bash fallback**:
```bash
pi-cc run "상태 요약: [내용]. (1) 방향 이탈 후보 (2) 실패 재현 징후 (3) status 근거. 판정 금지." --timeout "${PI_CC_TIMEOUT:-120}"
```

Pi timeout/error → **Haiku fallback**: `Bash("claude -p --model $LATEST_HAIKU '...'")`.

Claude 단계:
1. Pi 각 concern 에 대해 상태 파일 **직접 확인**
2. 최종 판정: "이탈 없음" / "이탈 발견:<항목>" / "Pi 요약 신뢰 불가 — 전체 재검토"
3. Claude 판정만 기록. Pi 문자열 복붙 금지.

## Circuit Breakers

| Breaker | 조건 | 동작 |
|---------|------|------|
| max_iterations | `iteration ≥ max_iterations` | status=partial, active=false |
| codex_reject_streak | `streak ≥ 3` | status=blocked, active=false |
| token_budget | 예산 초과 (추정) | status=partial, active=false |

Breaker 는 stop hook 스크립트에서도 확인하므로 이중 안전장치.

## 루프 종료 선언

작업이 완료되면 상태 파일을 갱신:

```bash
python3 -c "
import json
with open('$HOME/.claude/ralph-state.json') as f: s = json.load(f)
s['active'] = False
s['status'] = '{status}'
s['completed_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$HOME/.claude/ralph-state.json', 'w') as f: json.dump(s, f, indent=2)
"
```

이후 Claude 가 종료를 시도하면 stop hook 이 `active=false` 를 확인하고 정상 종료를 허용.

## 주의

- **매 iteration 은 stop hook 에 의해 재시작** — Claude 의 context 는 compaction 에 의해 관리됨
- **ctx 에는 최소한만 남겨라**: iteration 번호 + status + 방향 검증 결과
- **on_iteration_complete / on_completed_verify** 가 wrapper 에 정의되면 추가 후처리 수행
- **Pi 는 draft 전용** — gate 권한 절대 금지. 최종 판정은 Claude 또는 Codex
