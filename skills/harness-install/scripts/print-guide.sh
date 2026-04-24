#!/usr/bin/env bash
# print-guide.sh — 수동 설치 가이드 출력. 아무 파일도 건드리지 않음.
#
# Env vars:
#   CLAUDE_PLUGIN_ROOT  — plugin root (required)
#   HARNESS_MODE        — team (default) | subagent

set -euo pipefail

: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT env missing — skill 에서 호출해야 함}"

HARNESS_MODE="${HARNESS_MODE:-team}"
case "$HARNESS_MODE" in
  team|subagent) ;;
  *) echo "[print-guide] ERROR: HARNESS_MODE must be 'team' or 'subagent', got '${HARNESS_MODE}'" >&2; exit 1 ;;
esac

cat <<EOF

── viper 수동 설치 가이드 (harness-mode=${HARNESS_MODE}) ──────────────────────────

아래 명령어를 직접 실행하세요. 기존 ~/.claude/ 파일을 덮어쓸 수 있으므로
반드시 백업 후 진행하세요.

# 1. 기존 파일 백업 (이미 ~/.claude/CLAUDE.md 등이 있을 때만)
BACKUP="\$HOME/.claude/.backup/\$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "\$BACKUP"
for f in ~/.claude/CLAUDE.md ~/.claude/RTK.md ~/.claude/rules/common ~/.claude/rules/advisor.md; do
  [ -e "\$f" ] && mv "\$f" "\$BACKUP/"
done
EOF

if [ "${HARNESS_MODE}" = "team" ]; then
cat <<EOF
for f in ~/.claude/rules/worker.md ~/.claude/agents/architect.md ~/.claude/agents/coder.md ~/.claude/agents/debugger.md ~/.claude/agents/reviewer.md; do
  [ -e "\$f" ] && mv "\$f" "\$BACKUP/"
done
EOF
fi

cat <<EOF

# 2. symlink 설치 (권장)
# NOTE: only create ~/.claude/rules — do NOT pre-create ~/.claude/rules/common
#       because then ln -s ... ~/.claude/rules/common would place the link
#       *inside* that directory (→ ~/.claude/rules/common/common).
mkdir -p ~/.claude/rules
ln -s "${CLAUDE_PLUGIN_ROOT}/references/CLAUDE.md"        ~/.claude/CLAUDE.md
ln -s "${CLAUDE_PLUGIN_ROOT}/references/RTK.md"           ~/.claude/RTK.md
ln -s "${CLAUDE_PLUGIN_ROOT}/references/rules/common"     ~/.claude/rules/common
EOF

if [ "${HARNESS_MODE}" = "team" ]; then
cat <<EOF
ln -s "${CLAUDE_PLUGIN_ROOT}/references/rules/advisor.md" ~/.claude/rules/advisor.md
ln -s "${CLAUDE_PLUGIN_ROOT}/references/rules/worker.md"  ~/.claude/rules/worker.md
mkdir -p ~/.claude/agents
ln -s "${CLAUDE_PLUGIN_ROOT}/agents/architect.md"         ~/.claude/agents/architect.md
ln -s "${CLAUDE_PLUGIN_ROOT}/agents/coder.md"             ~/.claude/agents/coder.md
ln -s "${CLAUDE_PLUGIN_ROOT}/agents/debugger.md"          ~/.claude/agents/debugger.md
ln -s "${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md"          ~/.claude/agents/reviewer.md
EOF
else
cat <<EOF
# subagent mode — if switching from team mode, back up and remove team-mode
# artifacts first (install-{copy,symlink}.sh do this automatically; the manual
# guide must mirror that behavior or stale files get loaded alongside the
# subagent advisor):
BACKUP=~/.claude/.backup/\$(date -u +%Y%m%d-%H%M%S)
mkdir -p "\$BACKUP"
[ -e ~/.claude/rules/worker.md ] && mv ~/.claude/rules/worker.md "\$BACKUP"/
for role in architect coder debugger reviewer; do
  [ -e ~/.claude/agents/\${role}.md ] && mv ~/.claude/agents/\${role}.md "\$BACKUP"/
done
[ -e ~/.claude/rules/advisor.md ] && mv ~/.claude/rules/advisor.md "\$BACKUP"/

# advisor-subagent.md installed AS advisor.md (rename on install — Claude Code
# auto-injects rules/advisor.md unconditionally, so the subagent variant must
# occupy that path).
ln -s "${CLAUDE_PLUGIN_ROOT}/references/rules/advisor-subagent.md" ~/.claude/rules/advisor.md

# worker.md and agents/*.md are NOT installed in subagent mode.
# /viper-team skill is bundled in the viper plugin (since PR #24 merged
# viper-team into viper) and will not be recommended by Advisor routing
# in subagent mode. Claude Code does not support per-skill disable,
# so no extra action needed — just ignore it.
EOF
fi

cat <<EOF

# 2-alt. 또는 copy (로컬 수정 보호 원할 때)
# mkdir -p ~/.claude/rules
# cp "${CLAUDE_PLUGIN_ROOT}/references/CLAUDE.md" ~/.claude/CLAUDE.md
# cp "${CLAUDE_PLUGIN_ROOT}/references/RTK.md"    ~/.claude/RTK.md
# cp -R "${CLAUDE_PLUGIN_ROOT}/references/rules/common" ~/.claude/rules/common
EOF

if [ "${HARNESS_MODE}" = "team" ]; then
cat <<EOF
# cp "${CLAUDE_PLUGIN_ROOT}/references/rules/advisor.md" ~/.claude/rules/advisor.md
# cp "${CLAUDE_PLUGIN_ROOT}/references/rules/worker.md"  ~/.claude/rules/worker.md
# mkdir -p ~/.claude/agents
# cp "${CLAUDE_PLUGIN_ROOT}/agents/architect.md" ~/.claude/agents/architect.md
# cp "${CLAUDE_PLUGIN_ROOT}/agents/coder.md"     ~/.claude/agents/coder.md
# cp "${CLAUDE_PLUGIN_ROOT}/agents/debugger.md"  ~/.claude/agents/debugger.md
# cp "${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md"  ~/.claude/agents/reviewer.md
EOF
else
cat <<EOF
# subagent mode (copy variant) — same cleanup prerequisites as symlink:
# BACKUP=~/.claude/.backup/\$(date -u +%Y%m%d-%H%M%S)
# mkdir -p "\$BACKUP"
# [ -e ~/.claude/rules/worker.md ] && mv ~/.claude/rules/worker.md "\$BACKUP"/
# for role in architect coder debugger reviewer; do
#   [ -e ~/.claude/agents/\${role}.md ] && mv ~/.claude/agents/\${role}.md "\$BACKUP"/
# done
# [ -e ~/.claude/rules/advisor.md ] && mv ~/.claude/rules/advisor.md "\$BACKUP"/
# cp "${CLAUDE_PLUGIN_ROOT}/references/rules/advisor-subagent.md" ~/.claude/rules/advisor.md
EOF
fi

cat <<EOF

# 3. 모델 manifest 생성
bash "${CLAUDE_PLUGIN_ROOT}/skills/harness-install/scripts/resolve-models.sh"

# 4. 가용성 캐시 (unquoted JSON heredoc — user shell evaluates the \$(...) calls)
cat > ~/.claude/rules/availability-cache.json <<JSON
{
  "pi": \$([ -x "\$(command -v pi-cc)" ] && echo true || echo false),
  "codex": \$([ -x "\$(command -v codex)" ] && echo true || echo false),
  "omc": \$(find ~/.claude/plugins/cache/omc -maxdepth 3 -name 'plugin.json' -path '*/oh-my-claudecode*/*' 2>/dev/null | head -1 | grep -q . && echo true || echo false)
}
JSON

설치 후 Claude Code 를 재시작하면 ~/.claude/CLAUDE.md 가 자동 로드됩니다.

────────────────────────────────────────────────────────────

EOF

echo "[print-guide] 가이드 출력만 (harness-mode=${HARNESS_MODE}) — 파일 시스템 변경 없음."
