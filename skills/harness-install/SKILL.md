---
name: harness-install
description: viper-plugin-cc 플러그인을 ~/.claude/ 에 설치. CLAUDE.md + RTK.md + rules/ + agents/*.md + skills/*/ 일괄 배포. symlink/copy/guide 3-모드 + 모델 manifest + statusline 포인터 + rtk ↔ pi-caller-inject hook 마이그레이션. 기존 파일은 ~/.claude/.backup/<ts>/ 로 백업.
user-invocable: true
argument-hint: "[--refresh-models] [--apply-statusline] [--apply-hook-migration] [--mode=symlink|copy|guide] [--harness-mode=team|subagent]"
---

# /harness-install

viper-plugin-cc 플러그인이 가진 CLAUDE.md + RTK.md + rules/*.md + agents/*.md + skills/*/ 를 사용자 `~/.claude/` 에 설치한다. Claude Code 플러그인 시스템은 rules/ 와 CLAUDE.md 를 자동 주입하지 않고, agents/skills 는 global-scope 로 활용하려면 `~/.claude/` 위치가 필요하므로 수동 설치 스킬이 있다.

## 사전 조건 — RTK 필수

이 스킬은 **RTK (Rust Token Killer, [rtk-ai/rtk](https://github.com/rtk-ai/rtk))** 가 설치된 환경을 전제로 한다. viper-plugin-cc 가 참조하는 subagent-token-diet 규약이 RTK 의 PreToolUse hook 주입을 가정하므로, RTK 없으면 Bash 툴콜 output 이 plain 으로 흘러 컨텍스트 폭발을 일으킨다.

설치 절차 (첫 실행 전 1 회):
```bash
brew install rtk              # macOS/Linux 권장
# 또는: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
# 또는: cargo install --git https://github.com/rtk-ai/rtk
rtk init -g                   # Claude Code hook 등록
rtk --version                 # 확인
```

`rtk` 바이너리가 PATH 에 없으면 `/harness-install` 은 **설치를 중단하고** 위 명령을 안내한다 (실행 흐름 단계 0 직후의 전제 조건 체크).

## 설치 모드 (install mode)

- **A. symlink (권장)** — `~/.claude/{CLAUDE.md, RTK.md, rules/*.md}` 를 `${CLAUDE_PLUGIN_ROOT}/references/*` 로 **심볼릭 링크**. 플러그인 업데이트 시 자동 반영. 사용자가 로컬에서 수정하면 원본 touch 됨(주의).
- **B. copy** — 물리 복사. 업데이트 시 `/harness-install` 재실행 필요. 로컬 수정 보호됨.
- **C. guide only** — 아무것도 안 한다. 복붙 명령어만 출력. 유저가 수동 수행.

## 하네스 모드 (harness mode)

`--harness-mode` 는 어떤 roles/agents 세트를 설치할지 제어한다. 기본값: `team`.

- **team (default)** — 팀 기반 오케스트레이션. 설치 대상:
  - `rules/common/*` → `~/.claude/rules/common/`
  - `rules/advisor.md` → `~/.claude/rules/advisor.md`
  - `rules/worker.md` → `~/.claude/rules/worker.md`
  - `agents/{architect,coder,debugger,reviewer}.md` → `~/.claude/agents/`
  - `/viper-team` 스킬은 플러그인에 이미 있으므로 추가 설치 불필요.

- **subagent** — 단일 Advisor + Pi/Codex subagent 패턴 (팀 없이 동작). 설치 대상:
  - `rules/common/*` → `~/.claude/rules/common/`
  - `rules/advisor-subagent.md` → `~/.claude/rules/advisor.md` (이름 변환 설치)
  - `rules/worker.md` **미설치** (팀 워커 불필요)
  - `agents/*.md` **미설치** (팀 워커 불필요)
  - 설치 후 주의: `/viper-team` 스킬은 `viper-plugin-cc` 플러그인에 번들로 남아있지만 subagent 모드의 Advisor 라우팅에서는 추천되지 않는다. Claude Code 는 skill-단위 disable 을 지원하지 않으므로 (PR #24 로 `viper-team` 독립 플러그인은 `viper-plugin-cc` 에 흡수됨) 무시하고 쓰거나, `viper-plugin-cc` 플러그인 자체를 disable 하면 rules/ 와 다른 skill 까지 함께 빠진다는 점에 유의.

## 사용법

```text
/harness-install                                        # 대화형 (AskUserQuestion 으로 모드 선택)
/harness-install --mode=symlink                         # 비대화, symlink 바로 실행 (harness-mode=team 기본)
/harness-install --mode=symlink --harness-mode=team     # team 모드 명시
/harness-install --mode=copy   --harness-mode=subagent  # subagent 모드, 물리 복사
/harness-install --refresh-models                       # 모델 manifest 만 재생성 (install 건너뜀)
/harness-install --apply-statusline                     # settings.json 의 statusLine.command 를 statusline 플러그인으로 포인팅
/harness-install --apply-hook-migration                 # settings.json 에서 rtk-rewrite PreToolUse 엔트리 제거
```

플래그는 조합 가능. `--apply-*` 플래그만 주면 mode 선택 없이 해당 작업만 실행.

## 실행 흐름 (Claude 가 이 절차를 따른다)

### 0.0. RTK prerequisite 체크 (MANDATORY — 다른 단계 전에 첫 실행)

```bash
if ! command -v rtk >/dev/null 2>&1; then
  cat <<'EOF'
[harness-install] ❌ RTK (Rust Token Killer) 가 설치돼 있지 않습니다.
viper-plugin-cc 는 RTK 를 필수 의존으로 합니다 (subagent-token-diet 규약이 RTK hook 주입을 가정).

설치:
  brew install rtk
  # 또는
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  # 또는
  cargo install --git https://github.com/rtk-ai/rtk

설치 후:
  rtk init -g
  rtk --version

그 다음 /harness-install 재실행.
EOF
  exit 3
fi
```

`rtk init -g` 는 이미 돌아있는지 추가 검증:
```bash
if ! grep -q 'rtk-rewrite' ~/.claude/settings.json 2>/dev/null \
   && ! grep -rq 'rtk-rewrite' ~/.claude/plugins/cache/*/pi/*/hooks/ 2>/dev/null; then
  echo "[harness-install] ⚠️  RTK hook 이 Claude Code 에 등록돼 있지 않습니다."
  echo "[harness-install] 'rtk init -g' 를 실행하거나 pi 플러그인 (pi-caller-inject 경유) 을 설치하세요."
  # 경고만 — RTK 바이너리는 있으므로 설치 자체는 진행
fi
```

### 0. 인자 파싱

`$ARGUMENTS` 에서 플래그 파싱:
- `--refresh-models` → 단계 3 만 실행 후 종료
- `--apply-statusline` → `scripts/apply-statusline.sh` 만 실행 후 종료
- `--apply-hook-migration` → `scripts/apply-hook-migration.sh` 만 실행 후 종료
- `--mode=<X>` → AskUserQuestion 생략, 단계 2 로 점프
- `--harness-mode=<Y>` → `HARNESS_MODE` env 로 저장 (team|subagent). 기본값: team. 미지원 값 → 에러 후 종료.
- 여러 `--apply-*` 조합 가능 (순차 실행)
- 아무 플래그도 없으면 대화형 flow (단계 1 부터)

`--harness-mode` 파싱 및 검증 (SKILL.md 에서 스크립트 호출 전 수행):
```bash
HARNESS_MODE="team"  # default
if echo "$ARGUMENTS" | grep -q -- '--harness-mode='; then
  # Match only the whole-word allowed values. Without the `(space|end)` anchor
  # invalid inputs like `--harness-mode=subagent123` truncate to a valid
  # prefix and silently pass the case check below.
  HARNESS_MODE="$(echo "$ARGUMENTS" \
    | grep -Eo -- '--harness-mode=(team|subagent)([[:space:]]|$)' \
    | head -1 \
    | sed -E 's/^--harness-mode=//; s/[[:space:]]+$//')"
  # Fallback: if nothing matched the whole-word pattern, capture the raw token
  # so the case statement surfaces the user's actual (bad) value in the error.
  if [ -z "$HARNESS_MODE" ]; then
    HARNESS_MODE="$(echo "$ARGUMENTS" | grep -o -- '--harness-mode=[^[:space:]]*' | head -1 | cut -d= -f2)"
  fi
fi
case "$HARNESS_MODE" in
  team|subagent) ;;
  *) echo "ERROR: --harness-mode must be 'team' or 'subagent', got '${HARNESS_MODE}'"; exit 1 ;;
esac
export HARNESS_MODE
```

### 1. 기존 파일 상태 점검

```bash
for f in ~/.claude/CLAUDE.md ~/.claude/RTK.md; do [ -e "$f" ] && echo "EXISTS: $f" || echo "ABSENT: $f"; done
[ -d ~/.claude/rules ] && ls ~/.claude/rules/ | head -20 || echo "rules/ ABSENT"
```

기존 파일·rules 있으면 → 단계 2 에서 사용자에게 backup 확인.

### 2. 모드 선택 (AskUserQuestion — `--mode` / `--harness-mode` 없을 때)

두 질문을 한 번의 `AskUserQuestion` 에 묶어 보낸다 — 불필요한 왕복 차단.

```text
AskUserQuestion({
  questions: [
    {
      question: "CLAUDE.md + rules/ 를 ~/.claude/ 에 어떻게 설치할까?",
      header: "Install mode",
      options: [
        { label: "Symlink (권장)", description: "심볼릭 링크. 플러그인 업데이트 자동 반영. 기존 파일은 ~/.claude/.backup/<ts>/ 로 이동." },
        { label: "Copy", description: "물리 복사. 로컬 수정 보호. 업데이트 시 재실행 필요." },
        { label: "Guide only", description: "설치 스크립트만 출력. 아무것도 건드리지 않음. 유저가 수동 실행." }
      ],
      multiSelect: false
    },
    {
      question: "어떤 하네스 유형을 설치할까?",
      header: "Harness mode",
      options: [
        { label: "Team (권장)", description: "/viper-team 팀 기반 오케스트레이션. architect/coder/debugger/reviewer 4-worker + 스케일 모드." },
        { label: "Subagent (legacy)", description: "단일 Advisor + Pi/Codex 서브에이전트 호출. 팀 없이 동작. 기존 서브에이전트 하네스 사용자용." }
      ],
      multiSelect: false
    }
  ]
})
```

이미 `--harness-mode=...` 가 인자로 왔으면 Harness mode 질문 생략. 이미 `--mode=...` 왔으면 Install mode 질문 생략. 둘 다 왔으면 AskUserQuestion 자체 건너뛰고 단계 3 으로.

기존 파일이 존재하는 경우, 별도로 backup 확인:
```text
AskUserQuestion({
  questions: [{
    question: "기존 ~/.claude/{CLAUDE.md, RTK.md, rules/} 를 백업하고 덮어쓸까?",
    header: "Backup",
    options: [
      { label: "백업 후 덮어쓰기 (권장)", description: "~/.claude/.backup/<YYYYMMDD-HHMMSS>/ 로 이동 후 설치" },
      { label: "중단", description: "아무것도 하지 않고 종료" }
    ],
    multiSelect: false
  }]
})
```

### 3. 모델 resolve 및 manifest 생성

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/resolve-models.sh
```

이 스크립트는:
1. `ANTHROPIC_API_KEY` env 있으면 `https://api.anthropic.com/v1/models` 조회 → 각 family 최신 id 추출
2. 없으면 `curl https://platform.claude.com/docs/en/about-claude/models/overview` fetch → HTML parsing
3. 둘 다 실패 시 `DEFAULT_*` 상수 사용하되 stderr 에 "수동 확인 필요" 경고
4. codex 설치돼 있으면 `codex --help` 로 `--model`, `--effort` 플래그 지원 확인
5. 결과를 `~/.claude/rules/model-manifest.md` 에 쓰기 (frontmatter 포함)

출력: manifest 경로 + resolved 모델 id 리스트를 사용자에게 보고.

### 4. 설치 실행 (선택된 모드 기준)

`HARNESS_MODE` 는 단계 0 에서 파싱·검증된 값을 그대로 export 해서 스크립트에 전달한다.

```bash
# A. symlink
HARNESS_MODE="${HARNESS_MODE}" bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/install-symlink.sh

# B. copy
HARNESS_MODE="${HARNESS_MODE}" bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/install-copy.sh

# C. guide only
HARNESS_MODE="${HARNESS_MODE}" bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/print-guide.sh
```

각 스크립트는 성공/실패 exit code + stdout 로 사용자에게 진행 상황 보고.

### 4.5. 선택적 statusline + hook 마이그레이션

`--apply-statusline` 또는 `--apply-hook-migration` 플래그 있으면 해당 스크립트 실행. 플래그 없이 interactive flow 라면 AskUserQuestion 으로 의사 확인:

```bash
# 4.5.A statusline 전환
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/apply-statusline.sh

# 4.5.B rtk → pi-caller-inject 마이그레이션
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/apply-hook-migration.sh
```

두 스크립트 모두 idempotent. 기존 설정은 `~/.claude/settings.json.backup-<ts>` 로 백업.

`apply-statusline`: `settings.json.statusLine.command` 를 statusline 플러그인의 `scripts/statusline.sh` 경로로 지정. OMC HUD 이전 사용자는 이전 `omc-hud.mjs` 경로가 백업 대체됨.

`apply-hook-migration`: `settings.json.hooks.PreToolUse` 에서 `rtk-rewrite.sh` 로 이어지는 엔트리를 제거. pi 플러그인의 hooks.json 이 PreToolUse/Bash matcher 로 `pi-caller-inject.sh` 를 등록하고, 그 스크립트가 rtk-rewrite 를 내부 subprocess 로 호출하므로 별도 엔트리가 남아있으면 Claude Code hooks 병렬 실행 규칙에 따라 race 가 발생한다 ([docs](https://code.claude.com/docs/en/hooks)).

### 5. 설치 후 가용성 캐시

Pi/Codex/OMC 가용성을 체크해서 `~/.claude/rules/availability-cache.json` 에 저장 (tool-fallback.md 가 세션 시작 시 읽음):

```bash
# omc 체크는 캐시 디렉터리 존재만으로는 불충분 (빈 디렉터리 false-positive).
# oh-my-claudecode 하위 실제 플러그인 manifest (plugin.json) 존재를 확인.
_omc_installed() {
  find ~/.claude/plugins/cache/omc -maxdepth 3 -name 'plugin.json' -path '*/oh-my-claudecode*/*' 2>/dev/null | head -1 | grep -q .
}

cat > ~/.claude/rules/availability-cache.json << EOF
{
  "pi": $([ -x "$(command -v pi-cc)" ] && echo 'true' || echo 'false'),
  "codex": $([ -x "$(command -v codex)" ] && echo 'true' || echo 'false'),
  "omc": $(_omc_installed && echo 'true' || echo 'false'),
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

### 6. 최종 보고 (MANDATORY — 생략 금지)

**스크립트만 실행하고 끝내지 말 것.** 사용자 마지막 메시지로 아래 형식의 요약을 반드시 출력. **보고 내용은 실제 install mode (symlink/copy/guide) + harness mode (team/subagent) 조합에 따라 실제로 생성/변경된 파일만 나열**하라 — 가짜 항목 (예: copy 모드에서 "심볼릭 링크 생성", subagent 모드에서 "agents/* 설치") 을 보고하면 다음 단계에서 사용자가 잘못된 경로를 참조한다.

```markdown
## ✓ /harness-install 완료

- **Install mode**: <선택된 값: symlink | copy | guide>
- **Harness mode**: <선택된 값: team | subagent>
- **설치된 파일** (mode 조합별로 실제 생성된 것만 나열):
  - symlink + team: `~/.claude/CLAUDE.md`, `~/.claude/rules/common/*` (심볼릭), `~/.claude/rules/advisor.md` (심볼릭), `~/.claude/rules/worker.md` (심볼릭), `~/.claude/agents/{architect,coder,debugger,reviewer}.md` (심볼릭)
  - symlink + subagent: `~/.claude/CLAUDE.md`, `~/.claude/rules/common/*` (심볼릭), `~/.claude/rules/advisor.md` ← `advisor-subagent.md` (심볼릭). worker.md / agents/*.md 는 설치하지 않음.
  - copy + team: 위 symlink+team 과 동일 파일 집합, 단 copy (심볼릭 아님)
  - copy + subagent: 위 symlink+subagent 과 동일 파일 집합, 단 copy (심볼릭 아님)
  - guide: 파일 생성 없음. 수동 설치 명령만 stdout 에 출력됨.
- **Model manifest**: `~/.claude/rules/model-manifest.md` (opus=<id>, sonnet=<id>, haiku=<id>, codex=<id|unavailable>) — guide 모드는 명령만 출력, 실제 생성은 사용자 직접 실행.
- **Degraded tools** (없으면 생략): Pi / Codex / OMC 중 부재한 것
- **다음 단계**: 새 Claude Code 세션 시작하면 CLAUDE.md + rules 자동 로드됨.
  - subagent 모드: `/viper-team` 스킬은 `viper-plugin-cc` 번들에 남아있지만 Advisor 라우팅이 추천하지 않음. Claude Code 는 skill 단위 disable 을 지원하지 않으므로 별도 조치 불필요 (무시 가능).
  - guide 모드: stdout 에 출력된 명령을 사용자가 직접 실행해야 설치 완료.
```

실패 시:

```markdown
## ✗ /harness-install 실패

- **단계**: (어느 단계에서 실패했는지 — 모드 선택 / 백업 / resolve-models / install-symlink 등)
- **에러**: (stderr 마지막 라인 또는 exit code)
- **영향**: 이미 백업된 파일은 ~/.claude/.backup/<ts>/ 에 남아있음 — 재시도 가능
- **권장 조치**: (e.g., ANTHROPIC_API_KEY 설정 후 --refresh-models 재실행 / 권한 확인 등)
```

설치 스크립트 내부 stdout (예: `[install-symlink] 완료`) 은 참고용 로그. 사용자에게는 위 요약이 "무엇이 바뀌었는지" 한눈에 들어오는 **최종 확인 표시** 역할.

## Refresh models only (`--refresh-models`)

install 건너뛰고 단계 3 만 실행. 기존 model-manifest.md 덮어쓰기.

## 에러 처리

- `~/.claude/` 자체가 없으면 생성 (`mkdir -p`)
- 심볼릭 링크 지원 안 되는 FS(FAT32 등) → copy 모드로 자동 전환 + 사용자 고지
- API 조회 실패 → 에러 메시지 + docs fallback
- 모든 fallback 실패 → AskUserQuestion 으로 사용자에게 직접 모델 id 입력 요청

## 관련

- `${CLAUDE_PLUGIN_ROOT}/references/rules/tool-fallback.md` — Pi/Codex/OMC 부재 시 동작
- `${CLAUDE_PLUGIN_ROOT}/references/CLAUDE.md` — 설치될 전역 instruction
- `~/.claude/rules/model-manifest.md` — resolve 결과 (설치 시 생성)
- `~/.claude/.backup/<ts>/` — 기존 파일 백업 위치
