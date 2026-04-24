# PRD.md 작성 가이드

PRD는 **subagent가 이 PRD만 읽고 바로 실행 가능한 수준**이어야 한다. 다음을 반드시 포함:

1. **목표**: 측정 가능한 수치 (ρ, d, p-value threshold)
2. **종료 조건**: 성공 기준 + 검증 프로토콜 + max iterations + plateau 허용
3. **데이터 소스**: 경로 + 행 수 + 포맷(JSON/JSONL) + 각 소스가 제공하는 필드 목록
4. **JOIN 로직**: 여러 소스를 합칠 때 JOIN 키 + 코드 예시. 단일 소스에 모든 필드 있다고 가정하지 말 것
5. **필터 조건**: 비성인, 2차창작 제외 등 + 어느 필드에서 확인하는지
6. **진행 순서**: 단계별 구체적 행동 (소규모 일관성 → 대규모 경향성)
7. **평가 명령어**: 복사해서 바로 실행 가능. API KEY 설정 포함
8. **수정 대상/금지**: 무엇을 바꿀 수 있고 무엇을 바꾸면 안 되는지
9. **작업 디렉토리 구조**: 폴더 안 모든 파일의 역할 + 시작 시 읽는 순서
10. **제약**: 고정 jsonl 재사용 금지, overfitting 금지, 임시 파일 위치 등

## 템플릿

```markdown
# {작업 이름}

## 목표
측정 가능한 수치 목표.

## 데이터
- 경로, 설명, 비교 대상 정의

## 수정 대상
- 파일 경로 + 수정 가능 범위 (수정 금지 항목 명시)

## 평가 방법
- 실행 명령어 (복사해서 바로 실행 가능)
- 점수 추출 방법
- **eval 은 프로젝트가 정의한 eval 함수/커맨드로 실행**. 예: `python run_benchmark.py --model $LATEST_OPUS_LITELLM`, `pytest -k eval_*`, `yarn eval`, 또는 `my_eval_module.evaluate_batch(...)`. 입력 스키마(Pydantic / dataclass / dict) 도 본 절에 명시.

## 종료 조건
- 성공: metric ≥ threshold
- 검증 프로토콜 (5단계 필수):
  1. reverse-extract: 비교 그룹에서 추출, 차이 분석
  2. 일관성: 같은 데이터 3회 반복 → 재현성
  3. 견고성: 매번 다른 데이터 랜덤 추출 × 3회 → 견고성
  4. 대규모: N=80 고정 (초과 시 questions.md 승인 요청)
  5. 통계: regression + Cohen's d + 버킷 단조성
- 최대 iterations / plateau 허용 횟수

## Pi 활용 (Pi = draft / Advisor = verify, 전부 Worker 검토 필수)
- Phase 1: Pi가 사전분석 draft (축별 regression, pass_count, 버킷 분석) → Worker(Opus) 판정
- Phase 2: Pi가 변형 병렬 draft 생성 → Worker가 1~2개 선택
- Phase 3: Pi가 pre-check + cross-verify draft → Worker가 gate 결정 (Pi 단독 PASS/FAIL 금지)
- Phase 3: Pi가 eval 결과 통계 draft → Worker가 spot-check verify
- Phase 4: Pi가 regression **후보 draft** → Worker가 `[REGRESSION]` 기록 및 "3회 연속 → 수정 금지" 승격 판단
- `plateau_count` ≥ 2: Pi가 Promptbreeder mutation 5종 병렬 draft → Worker가 선택
- **eval은 반드시 Opus** — Pi는 eval 실행 불가

상세 규약: `${CLAUDE_PLUGIN_ROOT}/agents/self-improving-agent.md` Phase 2~4 / `${CLAUDE_PLUGIN_ROOT}/agents/self-improve-ralph.md` section 2. Pi에게 gate 권한 주는 템플릿 금지.

## 제약
- 모델, overfitting 기준, 기타 규칙

## 참고 자료
- reference/에 넣을 파일 경로
```
