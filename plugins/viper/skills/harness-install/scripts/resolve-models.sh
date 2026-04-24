#!/usr/bin/env bash
# resolve-models.sh — 설치 시점 최신 모델 id resolve 후 ~/.claude/rules/model-manifest.md 출력
# 호출: bash resolve-models.sh
# 의존: curl, jq (있으면 선호), python3 (jq 없을 때 fallback)
# 출력: ~/.claude/rules/model-manifest.md + stdout 에 요약

set -euo pipefail

MANIFEST_DIR="${HOME}/.claude/rules"
MANIFEST="${MANIFEST_DIR}/model-manifest.md"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${MANIFEST_DIR}"

# ─── 0. Portable version-sort detector (GNU coreutils vs macOS BSD) ──
SORT_VERSION_SUPPORTED="false"
if printf '1.2\n1.10\n' | sort -V >/dev/null 2>&1 \
   && [ "$(printf '1.2\n1.10\n' | sort -V | tail -1)" = "1.10" ]; then
  SORT_VERSION_SUPPORTED="true"
fi

# ─── 1. Default values (3차 fallback) ─────────────────────────────
DEFAULT_OPUS="claude-opus-4-7"
DEFAULT_SONNET="claude-sonnet-4-6"
DEFAULT_HAIKU="claude-haiku-4-5-20251001"
DEFAULT_CODEX_MODEL="gpt-5-codex"
DEFAULT_CODEX_EFFORT="xhigh"

LATEST_OPUS=""
LATEST_SONNET=""
LATEST_HAIKU=""
SOURCE="default_fallback"

# ─── 2. 1차: API 조회 ─────────────────────────────────────────────
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "[resolve-models] ANTHROPIC_API_KEY 감지 → API 조회" >&2
  if MODELS_JSON=$(curl -sS --fail --max-time 15 \
      -H "anthropic-version: 2023-06-01" \
      -H "X-Api-Key: ${ANTHROPIC_API_KEY}" \
      https://api.anthropic.com/v1/models 2>/dev/null); then

    if command -v jq >/dev/null 2>&1 && [ "${SORT_VERSION_SUPPORTED}" = "true" ]; then
      LATEST_OPUS=$(echo "${MODELS_JSON}" | jq -r '.data[].id' 2>/dev/null | grep -E '^claude-opus' | sort -V | tail -1 || true)
      LATEST_SONNET=$(echo "${MODELS_JSON}" | jq -r '.data[].id' 2>/dev/null | grep -E '^claude-sonnet' | sort -V | tail -1 || true)
      LATEST_HAIKU=$(echo "${MODELS_JSON}" | jq -r '.data[].id' 2>/dev/null | grep -E '^claude-haiku' | sort -V | tail -1 || true)
    elif command -v python3 >/dev/null 2>&1; then
      # jq 없으면 python3 fallback — version-aware sort (날짜 suffix 있는 id 우선)
      PY_SORT='import sys,json,re
d=json.load(sys.stdin)
ids=[m["id"] for m in d.get("data",[]) if m["id"].startswith(sys.argv[1])]
def key(i):
  m=re.search(r"claude-\w+-(\d+)-(\d+)(?:-(\d+))?", i)
  return tuple(int(x) if x else 0 for x in (m.groups() if m else (0,0,0)))
print(sorted(ids, key=key)[-1] if ids else "")'
      LATEST_OPUS=$(echo "${MODELS_JSON}" | python3 -c "${PY_SORT}" claude-opus || true)
      LATEST_SONNET=$(echo "${MODELS_JSON}" | python3 -c "${PY_SORT}" claude-sonnet || true)
      LATEST_HAIKU=$(echo "${MODELS_JSON}" | python3 -c "${PY_SORT}" claude-haiku || true)
    else
      # jq 도 python3 도 없음 — API 응답 파싱 스킵, 2차 fallback 로 진행
      echo "[resolve-models] ⚠️  jq·python3 둘 다 부재 — API 응답 파싱 불가. 2차 fallback 시도." >&2
    fi

    if [ -n "${LATEST_OPUS}" ] && [ -n "${LATEST_SONNET}" ] && [ -n "${LATEST_HAIKU}" ]; then
      SOURCE="anthropic_api"
      echo "[resolve-models] API resolve 성공" >&2
    else
      echo "[resolve-models] API 응답 파싱 실패 (일부 family 누락) → 2차 fallback 시도" >&2
    fi
  else
    echo "[resolve-models] API 호출 실패 (network/auth) → 2차 fallback 시도" >&2
  fi
fi

# ─── 3. 2차: 공식 문서 파싱 ───────────────────────────────────────
if [ "${SOURCE}" = "default_fallback" ]; then
  echo "[resolve-models] platform.claude.com docs 파싱 시도" >&2
  DOCS_URL="https://platform.claude.com/docs/en/about-claude/models/overview"
  if DOCS_HTML=$(curl -sS --fail --max-time 20 "${DOCS_URL}" 2>/dev/null); then
    # 최신 모델 id 추출 — 문서에서 "claude-{opus|sonnet|haiku}-*-*" 패턴 뽑기
    # 매우 관대한 regex (HTML 태그 안에 섞여있을 수 있어서)
    EXTRACTED=$(echo "${DOCS_HTML}" | grep -oE 'claude-(opus|sonnet|haiku)-[0-9]+-[0-9]+(-[0-9]+)?' | sort -u || true)
    if [ -n "${EXTRACTED}" ]; then
      # DOC_* 임시 변수 사용 → 1차 API 에서 부분 성공한 값 덮어쓰기 방지
      DOC_OPUS=""; DOC_SONNET=""; DOC_HAIKU=""
      if [ "${SORT_VERSION_SUPPORTED}" = "true" ]; then
        DOC_OPUS=$(echo "${EXTRACTED}" | grep '^claude-opus' | sort -V | tail -1 || true)
        DOC_SONNET=$(echo "${EXTRACTED}" | grep '^claude-sonnet' | sort -V | tail -1 || true)
        DOC_HAIKU=$(echo "${EXTRACTED}" | grep '^claude-haiku' | sort -V | tail -1 || true)
      elif command -v python3 >/dev/null 2>&1; then
        PY_VSORT='import sys
ids=[l.strip() for l in sys.stdin if l.strip()]
def key(i):
  parts=[int(p) for p in __import__("re").findall(r"\d+", i)]
  return tuple(parts) if parts else (0,)
print(sorted(ids, key=key)[-1] if ids else "")'
        DOC_OPUS=$(echo "${EXTRACTED}" | grep '^claude-opus' | python3 -c "${PY_VSORT}" || true)
        DOC_SONNET=$(echo "${EXTRACTED}" | grep '^claude-sonnet' | python3 -c "${PY_VSORT}" || true)
        DOC_HAIKU=$(echo "${EXTRACTED}" | grep '^claude-haiku' | python3 -c "${PY_VSORT}" || true)
      else
        # 둘 다 없음 — grep 으로 얻은 첫 항목 (정확성 낮음, default fallback 유도)
        DOC_OPUS=$(echo "${EXTRACTED}" | grep '^claude-opus' | tail -1 || true)
        DOC_SONNET=$(echo "${EXTRACTED}" | grep '^claude-sonnet' | tail -1 || true)
        DOC_HAIKU=$(echo "${EXTRACTED}" | grep '^claude-haiku' | tail -1 || true)
      fi
      # 누락된 family 만 보충 (1차 성공값 보존)
      [ -z "${LATEST_OPUS}" ] && [ -n "${DOC_OPUS}" ] && LATEST_OPUS="${DOC_OPUS}"
      [ -z "${LATEST_SONNET}" ] && [ -n "${DOC_SONNET}" ] && LATEST_SONNET="${DOC_SONNET}"
      [ -z "${LATEST_HAIKU}" ] && [ -n "${DOC_HAIKU}" ] && LATEST_HAIKU="${DOC_HAIKU}"
      if [ -n "${LATEST_OPUS}" ] && [ -n "${LATEST_SONNET}" ] && [ -n "${LATEST_HAIKU}" ]; then
        SOURCE="platform_docs"
        echo "[resolve-models] 문서 resolve 성공" >&2
      fi
    fi
  else
    echo "[resolve-models] 문서 fetch 실패" >&2
  fi
fi

# ─── 4. 3차: Default + stderr 경고 ──────────────────────────────
if [ -z "${LATEST_OPUS}" ]; then LATEST_OPUS="${DEFAULT_OPUS}"; fi
if [ -z "${LATEST_SONNET}" ]; then LATEST_SONNET="${DEFAULT_SONNET}"; fi
if [ -z "${LATEST_HAIKU}" ]; then LATEST_HAIKU="${DEFAULT_HAIKU}"; fi

if [ "${SOURCE}" = "default_fallback" ]; then
  echo "[resolve-models] ⚠️  API/문서 모두 실패 — default 상수 사용. '/harness-install --refresh-models' 로 재시도 권장." >&2
fi

# LiteLLM 형식
LATEST_OPUS_LITELLM="anthropic/${LATEST_OPUS}"

# ─── 5. Codex 모델 resolve ────────────────────────────────────────
CODEX_MODEL="${DEFAULT_CODEX_MODEL}"
CODEX_EFFORT="${DEFAULT_CODEX_EFFORT}"
CODEX_EFFORT_FLAG="--effort"  # default, CLI 지원 확인 후 변경 가능
CODEX_AVAILABLE="false"

if command -v codex >/dev/null 2>&1; then
  CODEX_AVAILABLE="true"
  HELP_OUT=$(codex --help 2>&1 || true)
  if echo "${HELP_OUT}" | grep -q -- '--effort'; then
    CODEX_EFFORT_FLAG="--effort"
  elif echo "${HELP_OUT}" | grep -q -- '--reasoning-effort'; then
    CODEX_EFFORT_FLAG="--reasoning-effort"
  else
    echo "[resolve-models] ⚠️  codex CLI 에 --effort/--reasoning-effort 플래그 없음. CLI 업데이트 검토. 기본값 --effort 사용." >&2
  fi
fi

# ─── 6. Manifest 출력 ────────────────────────────────────────────
cat > "${MANIFEST}" <<EOF
---
generated_at: ${TIMESTAMP}
source: ${SOURCE}
description: Installation-time resolved model IDs. rules/* 파일과 self-improve 3총사가 model-manifest.env 를 source 해서 \$LATEST_* env var 로 참조.
---

# Resolved Model IDs

| env var | ID |
|---------|-----|
| \`\$LATEST_OPUS\` | \`${LATEST_OPUS}\` |
| \`\$LATEST_SONNET\` | \`${LATEST_SONNET}\` |
| \`\$LATEST_HAIKU\` | \`${LATEST_HAIKU}\` |
| \`\$LATEST_OPUS_LITELLM\` | \`${LATEST_OPUS_LITELLM}\` |
| \`\$CODEX_MODEL\` | \`${CODEX_MODEL}\` |
| \`\$CODEX_EFFORT\` | \`${CODEX_EFFORT}\` |

Codex 가용: ${CODEX_AVAILABLE}

## Refresh

\`/harness-install --refresh-models\` 로 재생성. 또는 직접:

\`\`\`bash
bash \${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/resolve-models.sh
\`\`\`

## 사용 규약 (환경 변수 기반)

rules/\*.md 및 plugins/self-improve/agents/\*.md 의 **bash 코드 블록**은 \`\$LATEST_OPUS\`, \`\$LATEST_HAIKU\`, \`\$CODEX_MODEL\`, \`\$CODEX_EFFORT\` 등을 환경변수로 참조한다.

실제 실행 전 반드시 source:

\`\`\`bash
source ~/.claude/rules/model-manifest.env
claude -p --model "\$LATEST_OPUS" "..."
codex exec --model "\$CODEX_MODEL" "\$CODEX_EFFORT_FLAG" "\$CODEX_EFFORT" "..."
# 참고: \$CODEX_EFFORT_FLAG 는 codex CLI 의 --effort 또는 --reasoning-effort 중 설치된 버전에 맞춰 resolve 됨.
\`\`\`

(\`~/.claude/rules/model-manifest.env\` 은 본 스크립트가 생성한 sourceable bash env 파일.)

## 현재 resolve 된 값

- \`\$LATEST_OPUS\` = ${LATEST_OPUS}
- \`\$LATEST_SONNET\` = ${LATEST_SONNET}
- \`\$LATEST_HAIKU\` = ${LATEST_HAIKU}
- \`\$LATEST_OPUS_LITELLM\` = ${LATEST_OPUS_LITELLM}
- \`\$CODEX_MODEL\` = ${CODEX_MODEL}
- \`\$CODEX_EFFORT\` = ${CODEX_EFFORT}

(재설치: \`/harness-install --refresh-models\`)
EOF

# ─── 6b. Manifest .env emit (bash sourceable) ────────────────────
MANIFEST_ENV="${MANIFEST_DIR}/model-manifest.env"
cat > "${MANIFEST_ENV}" <<EOF
# Auto-generated by resolve-models.sh at ${TIMESTAMP}
# Source with: source ~/.claude/rules/model-manifest.env
export LATEST_OPUS="${LATEST_OPUS}"
export LATEST_SONNET="${LATEST_SONNET}"
export LATEST_HAIKU="${LATEST_HAIKU}"
export LATEST_OPUS_LITELLM="${LATEST_OPUS_LITELLM}"
export CODEX_MODEL="${CODEX_MODEL}"
export CODEX_EFFORT="${CODEX_EFFORT}"
export CODEX_EFFORT_FLAG="${CODEX_EFFORT_FLAG}"
export CODEX_AVAILABLE="${CODEX_AVAILABLE}"
export MODEL_MANIFEST_SOURCE="${SOURCE}"
EOF

# ─── 7. stdout 요약 ────────────────────────────────────────────
echo "[resolve-models] manifest: ${MANIFEST}"
echo "[resolve-models] manifest.env: ${MANIFEST_ENV}"
echo "[resolve-models] source: ${SOURCE}"
echo "[resolve-models] opus=${LATEST_OPUS} sonnet=${LATEST_SONNET} haiku=${LATEST_HAIKU} codex=${CODEX_MODEL} effort=${CODEX_EFFORT} codex_available=${CODEX_AVAILABLE}"
