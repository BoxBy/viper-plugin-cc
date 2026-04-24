#!/usr/bin/env bash
# apply-statusline.sh — idempotent ~/.claude/settings.json edit
# Points statusLine.command to statusline plugin's entrypoint.
# Backs up prior setting to ~/.claude/settings.json.backup-<ts>

set -euo pipefail

SETTINGS="${HOME}/.claude/settings.json"
BACKUP="${SETTINGS}.backup-$(date -u +%Y%m%d-%H%M%S)"

# Resolve statusline entrypoint. statusline 은 viper plugin 내부 (scripts/
# statusline.sh) 에 번들됨. Claude Code plugin cache 레이아웃:
#   ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/scripts/statusline.sh
# 우선순위: env override → 자기 plugin 내부 → marketplace cache (viper plugin
# 또는 legacy statusline 플러그인) → dev repo checkout.
_find_statusline_script() {
  local candidates=()
  # 1. Env override (테스트 / 커스텀 레이아웃)
  [ -n "${STATUSLINE_SCRIPT:-}" ] && candidates+=("$STATUSLINE_SCRIPT")
  # 2. 자기 plugin 내부 — $CLAUDE_PLUGIN_ROOT 가 viper 를 가리키면 scripts/ 가 형제
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && candidates+=("${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh")
  # 3. Marketplace install: viper plugin cache
  local glob1 glob2
  for glob1 in "$HOME/.claude/plugins/cache"/*/viper/*/scripts/statusline.sh; do
    [ -f "$glob1" ] && candidates+=("$glob1")
  done
  # 4. Legacy — statusline 가 독립 plugin 이었을 때의 경로 (backwards compat)
  for glob2 in "$HOME/.claude/plugins/cache"/*/statusline/*/scripts/statusline.sh; do
    [ -f "$glob2" ] && candidates+=("$glob2")
  done
  # 5. Dev: cwd-rooted repo checkout
  candidates+=("$PWD/plugins/viper/scripts/statusline.sh")

  for c in "${candidates[@]}"; do
    if [ -f "$c" ] && [ -x "$c" ]; then
      # Normalise to absolute path so settings.json stores a stable location
      (cd "$(dirname "$c")" && printf '%s\n' "$PWD/$(basename "$c")")
      return 0
    fi
  done
  return 1
}

if [ ! -f "$SETTINGS" ]; then
  echo "[apply-statusline] ERROR: $SETTINGS not found" >&2
  exit 1
fi

TARGET_SCRIPT="$(_find_statusline_script || echo '')"
if [ -z "$TARGET_SCRIPT" ]; then
  echo "[apply-statusline] ERROR: cannot locate statusline plugin's statusline.sh" >&2
  echo "[apply-statusline] Install statusline plugin first (marketplace: writer-agent-quality-check)." >&2
  exit 1
fi

# Current statusLine.type + .command — no-op only if BOTH match (otherwise a
# wrong type with matching command would be left untouched, which is wrong).
current_type=$(jq -r '.statusLine.type // empty' "$SETTINGS" 2>/dev/null)
current_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
if [ "$current_type" = "command" ] && [ "$current_cmd" = "$TARGET_SCRIPT" ]; then
  echo "[apply-statusline] already pointing at $TARGET_SCRIPT (type=command) — no-op"
  exit 0
fi

cp "$SETTINGS" "$BACKUP"
echo "[apply-statusline] backup: $BACKUP"

# Merge (not overwrite) — preserve any pre-existing statusLine fields
# like `padding`, `refreshInterval`, `visible`, etc. that the user or
# other tools may have set.
tmp="$(mktemp)"
jq --arg cmd "$TARGET_SCRIPT" \
   '(.statusLine = (.statusLine // {})) | .statusLine.type = "command" | .statusLine.command = $cmd' \
   "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "[apply-statusline] updated: .statusLine.command = $TARGET_SCRIPT"
echo "[apply-statusline] prior value: ${current_cmd:-<unset>}"
echo "[apply-statusline] Start a new Claude Code session to pick up the change."
