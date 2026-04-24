---
name: update-plugins
description: 마켓플레이스 대비 뒤처진 플러그인을 자동 업데이트. 캐시 파일 기반으로 outdated 목록을 읽고 `/plugin update` 를 순차 실행 + viper-plugin-cc 업데이트 시 `/harness-install --mode=symlink` 로 symlink 재링크 + 완료 후 statusline 캐시 재빌드. LLM 이 검증 단계를 담당하므로 완전 자동화는 아님.
user-invocable: true
argument-hint: "[--dry-run]"
---

# /update-plugins

`~/.claude/.cache/plugin-updates.txt` 에 기록된 outdated 플러그인을 하나씩 업데이트한다. OMC 의 `interactiveUpdate()` 상응 — 유저 1회 호출로 "감지 → 업데이트 → 재링크 → 재검증" 을 완주.

## 실행 흐름 (Claude 가 이 순서대로)

### 0. 인자 파싱

- `--dry-run` → 실제 `/plugin update` 호출하지 않고 계획만 출력 후 종료.

### 1. 캐시 파일 읽기

```bash
cat ~/.claude/.cache/plugin-updates.txt 2>/dev/null
```

- 파일 없거나 empty → **업데이트 대상 없음** 보고 후 종료. hook 이 아직 안 돈 상태면 먼저 `bash ~/.claude/hooks/plugin-update-check.sh` 수동 트리거 후 재확인.

### 2. outdated 목록 파싱

캐시 형식: `updates: NAME X→Y, NAME X→Y — /plugin update NAME`

전체 outdated 목록은 마켓플레이스 clone 에서 직접 재계산 (one-liner 는 첫 번째 NAME 만 포함하므로):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-update-check.sh" >/dev/null 2>&1
# 캐시에는 compact 만 있음 — 전체 목록은 hook 을 다시 돌려 stdout JSON 으로 받음
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-update-check.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' | grep -oE '• [^@]+@[^:]+' | sed 's/• //'
```

결과: `plugin@marketplace` 형태의 줄들.

### 3. 각 플러그인 순차 업데이트

outdated 목록 순서대로 (알파벳 정렬):

```
/plugin update <name>@<marketplace>
```

> ⚠️ Claude Code 의 `/plugin update` 는 slash command 라 Bash 에서 `claude -p` 로 재귀 호출하면 prompt cache 가 불안정해진다. **본 skill 이 직접 `/plugin update` 를 invoke** (Claude 가 slash command 를 대화적으로 실행).

각 업데이트 후 성공 메시지 (`✓ Updated <name> to X.Y.Z`) 를 확인하고 다음으로 진행. 실패 시 즉시 중단 후 에러 보고.

### 4. viper-plugin-cc 업데이트 감지 → 모든 diff 재링크

outdated 목록에 `viper-plugin-cc@...` 가 있었다면 업데이트 완료 후 viper-plugin-cc 가 `~/.claude/` 로 배포한 **모든 아티팩트** 를 새 버전 경로로 다시 포인팅한다. viper-plugin-cc 의 diff 는 3 가지 카테고리로 나뉘고 각각 처리 방식이 다르다.

#### (A) Symlink-based — `--mode=symlink` 로 재링크

| 대상 | 구 버전 이슈 |
|---|---|
| `~/.claude/CLAUDE.md` | 여전히 `cache/*/viper-plugin-cc/<old-ver>/references/CLAUDE.md` 를 가리킴 |
| `~/.claude/RTK.md` | 동일 |
| `~/.claude/rules/common/*.md` | 동일 |
| `~/.claude/rules/advisor.md` (+ `worker.md`, team 모드) | 동일 |
| `~/.claude/agents/{architect,coder,debugger,reviewer}.md` (team 모드) | 동일 |

`/plugin update` 는 새 버전을 `cache/*/viper-plugin-cc/<new-ver>/` 에 깔 뿐, 심볼릭은 그대로. `/harness-install --mode=symlink` 가 전부 재링크한다.

#### (B) Absolute-path with version — `--apply-statusline` 으로 재포인팅

| 대상 | 구 버전 이슈 |
|---|---|
| `~/.claude/settings.json` 의 `statusLine.command` | 절대경로 안에 `<old-ver>` 가 박혀있음 (`cache/*/viper-plugin-cc/0.2.0/scripts/statusline.sh`) |

`apply-statusline.sh` 의 `_find_statusline_script()` 가 최신 버전 plugin cache 를 찾아서 포인터 갱신.

#### (C) `${CLAUDE_PLUGIN_ROOT}` 기반 — **자동 업데이트**, 별도 조치 불필요

| 대상 | 자동 업데이트 메커니즘 |
|---|---|
| Plugin hooks (`plugins/viper-plugin-cc/hooks/hooks.json`) | Claude Code 가 session start 시 `cache/*/viper-plugin-cc/<new-ver>/hooks/hooks.json` 을 자동 로드. `command` 가 `${CLAUDE_PLUGIN_ROOT}/scripts/*` 로 쓰여 있어 항상 최신 버전 script 실행 (e.g. `plugin-update-check.sh`). |
| Plugin skills (`plugins/viper-plugin-cc/skills/*/SKILL.md`) | Claude Code 가 skill index 를 plugin cache 에서 세션마다 재빌드. 새 skill 자동 노출. |
| Bundled scripts (`plugins/viper-plugin-cc/scripts/*`) | hooks + skills 가 `${CLAUDE_PLUGIN_ROOT}` 로 호출하므로 자동. |

#### 최종 커맨드

```
/harness-install --mode=symlink --apply-statusline
```

두 플래그로 (A) + (B) 커버, (C) 는 `/plugin update` 만으로 자동.

> **Legacy cleanup**: 초기 설치본 중 `~/.claude/settings.json` 의 `hooks.SessionStart` 에 `/Users/boxby/.claude/hooks/plugin-update-check.sh` 같은 **절대경로 entry** 가 남아있으면 plugin hooks.json 과 **중복 실행** 된다 (viper-plugin-cc 0.3.0+ 은 plugin hooks.json 으로만 hook 주입). `settings.json` 을 확인해 `plugin-update-check` 참조가 있으면 해당 entry 제거 + `~/.claude/hooks/plugin-update-check.sh` 파일 삭제. 자동화 migration 스크립트는 아직 없음 — 수동 확인 권장.

### 4.1. install mode 추적

- `--mode=symlink` 대신 copy 로 설치한 유저는 `--mode=copy --apply-statusline` 로 실행. 이전 선택은 `~/.claude/.cache/plugin-updates.txt` 와 같은 디렉토리의 `install-mode.txt` 에 저장돼 있으면 그걸 사용, 없으면 AskUserQuestion 으로 물어봄.
- harness-mode (team vs subagent) 는 그대로 유지 — `~/.claude/rules/advisor.md` 의 symlink target 이 `advisor.md` 인지 `advisor-subagent.md` 인지로 자동 감지.

### 5. 캐시 재빌드

업데이트 완료 후 hook 재실행 → 캐시 비워짐 → 다음 statusline 렌더에서 top line 사라짐:

```bash
bash ~/.claude/hooks/plugin-update-check.sh >/dev/null 2>&1
```

### 6. 완료 보고 (MANDATORY)

```markdown
## ✓ /update-plugins 완료

- **업데이트된 플러그인**:
  - `self-improve`: 0.2.0 → 0.3.0
  - `viper-plugin-cc`: 0.2.0 → 0.3.0 (harness-install --mode=symlink 재실행)
- **재링크 대상**: ~/.claude/CLAUDE.md, rules/*, agents/* (viper-plugin-cc 업데이트 시만)
- **다음 단계**: 새 Claude Code 세션 시작하면 새 버전 CLAUDE.md + rules 자동 로드됨.
```

실패 시:

```markdown
## ✗ /update-plugins 중단

- **실패 단계**: (/plugin update <name> 또는 /harness-install)
- **에러**: (마지막 stderr / exit code)
- **완료된 플러그인**: (이미 업데이트된 것 목록 — rollback 시 참고)
- **권장 조치**: 수동 `/plugin update <name>` 재시도 후 `/harness-install --mode=symlink`
```

## Rules

- **LLM 검증 필수**: 단순 스크립트가 아니다. 각 `/plugin update` 결과의 stderr / stdout 을 LLM 이 읽고 문제 있으면 중단. 예: 플러그인 install.sh 가 Rust 빌드 실패 → rck 의 경우 `plugins/rck/scripts/install.sh` 재실행 필요 여부 판단.
- **re-link 이후 rule 충돌 검증**: viper-plugin-cc 재설치 후 advisor.md / worker.md 링크가 올바른 target 을 가리키는지 확인. `readlink ~/.claude/rules/advisor.md` 결과가 새 버전 plugin cache 경로인지 검증.
- **backup 확인**: `/harness-install` 이 `~/.claude/.backup/<ts>/` 에 기존 파일 백업하므로, 업데이트 후 기존 파일이 살아있는지 `ls ~/.claude/.backup/` 확인 후 보고.
- **Dry-run 모드**: `--dry-run` 이면 outdated 목록과 계획된 `/plugin update` 순서 + `/harness-install` 조건만 출력. 실행 없음.
- **완전 자동화 아님**: harness-mode 선택, rule 충돌 resolve, 빌드 실패 복구 등은 LLM 판단이 필요. 완전 무인 루프는 OMC 의 silentAutoUpdate 패턴이 가까우나 우리는 의도적으로 지원 안 함 (하네스 변경은 사용자 승인 필요).

## 관련

- `${CLAUDE_PLUGIN_ROOT}/scripts/plugin-update-check.sh` — hook (업데이트 감지 + 캐시 기록)
- `${CLAUDE_PLUGIN_ROOT}/skills/harness-install/SKILL.md` — symlink 재링크 담당
- OMC 의 `interactiveUpdate()` (`src/features/auto-update.ts`) — 상응 로직 참고. 우리는 claude.com/plugins 마켓플레이스 기반이라 npm/GitHub releases 대신 `/plugin update` slash command 사용.
