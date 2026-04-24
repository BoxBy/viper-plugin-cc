#!/usr/bin/env bash
# install-symlink.sh — viper-plugin-cc references 를 ~/.claude/ 로 symlink
# 기존 파일은 ~/.claude/.backup/<YYYYMMDD-HHMMSS>/ 로 이동
#
# Env vars:
#   CLAUDE_PLUGIN_ROOT  — plugin root (required)
#   HARNESS_MODE        — team (default) | subagent
#   DST_ROOT            — override install destination (default: ~/.claude, useful for dry-run tests)

set -euo pipefail

: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT env missing — skill 에서 호출해야 함}"

HARNESS_MODE="${HARNESS_MODE:-team}"
case "$HARNESS_MODE" in
  team|subagent) ;;
  *) echo "[install-symlink] ERROR: HARNESS_MODE must be 'team' or 'subagent', got '${HARNESS_MODE}'" >&2; exit 1 ;;
esac

SRC_ROOT="${CLAUDE_PLUGIN_ROOT}/references"
DST_ROOT="${DST_ROOT:-${HOME}/.claude}"
BACKUP_ROOT="${DST_ROOT}/.backup/$(date -u +%Y%m%d-%H%M%S)"

# ── Source validation ──────────────────────────────────────────────────────────
# Always-required sources
for required in "${SRC_ROOT}/CLAUDE.md" "${SRC_ROOT}/RTK.md" "${SRC_ROOT}/rules/common" "${SRC_ROOT}/rules/advisor.md"; do
  if [ ! -e "${required}" ]; then
    echo "[install-symlink] ERROR: 필수 소스 누락: ${required}" >&2
    echo "[install-symlink] CLAUDE_PLUGIN_ROOT 또는 플러그인 설치 상태를 확인하세요." >&2
    exit 1
  fi
done

# common/*.md — verify every file advisor.md / worker.md reference exists
# individually. Checking only the directory lets a partial set (missing
# execution-contract.md, tools-reference.md, etc.) pass and break runtime lookups
# from rules/advisor.md and rules/worker.md.
for required in \
  "${SRC_ROOT}/rules/common/roles.md" \
  "${SRC_ROOT}/rules/common/tools-reference.md" \
  "${SRC_ROOT}/rules/common/execution-contract.md" \
  "${SRC_ROOT}/rules/common/code-quality.md" \
  "${SRC_ROOT}/rules/common/ddd-layers.md" \
  "${SRC_ROOT}/rules/common/ubiquitous-language.md" \
  "${SRC_ROOT}/rules/common/thinking-guidelines.md" \
  "${SRC_ROOT}/rules/common/document-management.md"; do
  if [ ! -e "${required}" ]; then
    echo "[install-symlink] ERROR: common/ 파일 누락: ${required}" >&2
    exit 1
  fi
done

# team-only sources — verify each expected role prompt file individually so a
# partial plugin install (missing architect/coder/debugger/reviewer) fails
# loudly instead of silently producing an incomplete role set.
if [ "${HARNESS_MODE}" = "team" ]; then
  for required in \
    "${SRC_ROOT}/rules/worker.md" \
    "${SRC_ROOT}/../agents" \
    "${SRC_ROOT}/../agents/architect.md" \
    "${SRC_ROOT}/../agents/coder.md" \
    "${SRC_ROOT}/../agents/debugger.md" \
    "${SRC_ROOT}/../agents/reviewer.md"; do
    if [ ! -e "${required}" ]; then
      echo "[install-symlink] ERROR: team 모드 필수 소스 누락: ${required}" >&2
      exit 1
    fi
  done
fi

# subagent-only source
if [ "${HARNESS_MODE}" = "subagent" ]; then
  if [ ! -e "${SRC_ROOT}/rules/advisor-subagent.md" ]; then
    echo "[install-symlink] ERROR: subagent 모드 필수 소스 누락: ${SRC_ROOT}/rules/advisor-subagent.md" >&2
    exit 1
  fi
fi

mkdir -p "${DST_ROOT}"

# ── Helpers ────────────────────────────────────────────────────────────────────
backup_if_exists() {
  local target="$1"
  if [ -e "${target}" ] || [ -L "${target}" ]; then
    mkdir -p "${BACKUP_ROOT}"
    mv "${target}" "${BACKUP_ROOT}/"
    echo "[install-symlink] backup: ${target} → ${BACKUP_ROOT}/"
  fi
}

link_or_copy() {
  local src="$1"
  local dst="$2"
  if ln -s "${src}" "${dst}" 2>/dev/null; then
    echo "[install-symlink] symlink: ${dst} → ${src}"
  else
    echo "[install-symlink] ⚠️  symlink 실패 (FS 미지원?) → copy: ${dst}" >&2
    if [ -d "${src}" ]; then
      cp -R "${src}" "${dst}"
    else
      cp "${src}" "${dst}"
    fi
  fi
}

# ── 1. CLAUDE.md ───────────────────────────────────────────────────────────────
backup_if_exists "${DST_ROOT}/CLAUDE.md"
link_or_copy "${SRC_ROOT}/CLAUDE.md" "${DST_ROOT}/CLAUDE.md"

# ── 2. RTK.md ─────────────────────────────────────────────────────────────────
backup_if_exists "${DST_ROOT}/RTK.md"
link_or_copy "${SRC_ROOT}/RTK.md" "${DST_ROOT}/RTK.md"

# ── 3. rules/common/ ──────────────────────────────────────────────────────────
mkdir -p "${DST_ROOT}/rules"
backup_if_exists "${DST_ROOT}/rules/common"
link_or_copy "${SRC_ROOT}/rules/common" "${DST_ROOT}/rules/common"

# ── 4. advisor.md (source differs by harness mode) ────────────────────────────
backup_if_exists "${DST_ROOT}/rules/advisor.md"
if [ "${HARNESS_MODE}" = "team" ]; then
  link_or_copy "${SRC_ROOT}/rules/advisor.md" "${DST_ROOT}/rules/advisor.md"
else
  # subagent: install advisor-subagent.md renamed as advisor.md
  link_or_copy "${SRC_ROOT}/rules/advisor-subagent.md" "${DST_ROOT}/rules/advisor.md"
  echo "[install-symlink] note: advisor-subagent.md installed as rules/advisor.md (subagent mode)"
fi

# ── 5. worker.md (team only) ──────────────────────────────────────────────────
# In subagent mode, actively remove any previously-installed worker.md so a
# team→subagent re-install doesn't leave stale auto-injected rules that break
# role isolation.
if [ "${HARNESS_MODE}" = "team" ]; then
  backup_if_exists "${DST_ROOT}/rules/worker.md"
  link_or_copy "${SRC_ROOT}/rules/worker.md" "${DST_ROOT}/rules/worker.md"
else
  if [ -e "${DST_ROOT}/rules/worker.md" ] || [ -L "${DST_ROOT}/rules/worker.md" ]; then
    backup_if_exists "${DST_ROOT}/rules/worker.md"
    echo "[install-symlink] removed: rules/worker.md (subagent mode — team artifact cleanup)"
  else
    echo "[install-symlink] skip: rules/worker.md (not used in subagent mode)"
  fi
fi

# ── 6. agents/ (team only) ────────────────────────────────────────────────────
AGENTS_SRC="${CLAUDE_PLUGIN_ROOT}/agents"
if [ "${HARNESS_MODE}" = "team" ]; then
  mkdir -p "${DST_ROOT}/agents"
  for agent_file in "${AGENTS_SRC}"/*.md; do
    [ -e "${agent_file}" ] || continue
    agent_name="$(basename "${agent_file}")"
    backup_if_exists "${DST_ROOT}/agents/${agent_name}"
    link_or_copy "${agent_file}" "${DST_ROOT}/agents/${agent_name}"
  done
else
  # Remove any previously-installed team agent md files (mirror basename logic
  # from the team branch) so a team→subagent switch doesn't leave them auto-
  # loading. Backup each into the timestamped backup dir for recovery.
  removed_any=0
  if [ -d "${DST_ROOT}/agents" ] || [ -L "${DST_ROOT}/agents" ]; then
    for agent_file in "${AGENTS_SRC}"/*.md; do
      [ -e "${agent_file}" ] || continue
      agent_name="$(basename "${agent_file}")"
      if [ -e "${DST_ROOT}/agents/${agent_name}" ] || [ -L "${DST_ROOT}/agents/${agent_name}" ]; then
        backup_if_exists "${DST_ROOT}/agents/${agent_name}"
        removed_any=1
      fi
    done
    # Try to remove an empty agents/ dir (rmdir fails silently when non-empty
    # or when the path is a symlink to something else — both acceptable).
    rmdir "${DST_ROOT}/agents" 2>/dev/null || true
  fi
  if [ "${removed_any}" = "1" ]; then
    echo "[install-symlink] removed: agents/*.md (subagent mode — team artifact cleanup)"
  else
    echo "[install-symlink] skip: agents/*.md (not used in subagent mode)"
  fi
  echo "[install-symlink] note: /viper-team skill is bundled in the viper-plugin-cc plugin (since PR #24 merged viper-team into viper-plugin-cc) and will not be recommended by Advisor routing in subagent mode. Claude Code does not support per-skill disable — just ignore it."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "[install-symlink] 완료. harness-mode=${HARNESS_MODE}"
echo "[install-symlink] 설치: ${DST_ROOT}/{CLAUDE.md, RTK.md, rules/common/, rules/advisor.md$([ "${HARNESS_MODE}" = "team" ] && echo ", rules/worker.md, agents/*.md")}"
if [ -d "${BACKUP_ROOT}" ]; then
  echo "[install-symlink] 백업: ${BACKUP_ROOT}"
fi
