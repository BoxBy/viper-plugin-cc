#!/usr/bin/env bash
# apply-hook-migration.sh — remove duplicate rtk-rewrite PreToolUse entry
# from ~/.claude/settings.json. pi plugin's pi-caller-inject.sh now calls
# rtk-rewrite.sh internally, so a separate hook entry would cause a race
# per Claude Code docs ("All matching hooks run in parallel").
#
# Idempotent. Backup before edit.

set -euo pipefail

SETTINGS="${HOME}/.claude/settings.json"
BACKUP="${SETTINGS}.backup-$(date -u +%Y%m%d-%H%M%S)"

if [ ! -f "$SETTINGS" ]; then
  echo "[apply-hook-migration] ERROR: $SETTINGS not found" >&2
  exit 1
fi

# Detect rtk-rewrite entry under hooks.PreToolUse[matcher=="Bash"].hooks[].command.
# Scope: the race we're fixing is the Bash-matcher duplicate only. Other-matcher
# rtk entries (if any exist — unusual) are NOT touched.
rtk_count=$(jq '
  [.hooks.PreToolUse[]?
   | select((.matcher // "") == "Bash")
   | .hooks[]?
   | select(((.command // "") | test("rtk-rewrite\\.sh")))
  ] | length
' "$SETTINGS" 2>/dev/null || echo 0)

if [ "${rtk_count:-0}" = "0" ]; then
  echo "[apply-hook-migration] no rtk-rewrite.sh PreToolUse entry found — nothing to do"
  exit 0
fi

cp "$SETTINGS" "$BACKUP"
echo "[apply-hook-migration] backup: $BACKUP"

tmp="$(mktemp)"

# Strategy: walk hooks.PreToolUse. ONLY for groups where matcher=="Bash",
# drop any inner hook entry whose command references rtk-rewrite.sh.
# Groups with other matchers are untouched. Remove Bash groups whose .hooks
# array becomes empty. Remove hooks.PreToolUse if it becomes empty.
jq '
  .hooks.PreToolUse = (
    (.hooks.PreToolUse // [])
    | map(
        if (.matcher // "") == "Bash" then
          .hooks = ((.hooks // []) | map(select(((.command // "") | test("rtk-rewrite\\.sh")) | not)))
        else
          .
        end
      )
    | map(select((.hooks // []) | length > 0))
  )
  | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
  | if (.hooks | length) == 0 then del(.hooks) else . end
' "$SETTINGS" > "$tmp"

mv "$tmp" "$SETTINGS"

echo "[apply-hook-migration] removed ${rtk_count} rtk-rewrite.sh PreToolUse entry/entries"
echo "[apply-hook-migration] pi plugin's pi-caller-inject.sh will now call rtk-rewrite.sh internally"
echo "[apply-hook-migration] Start a new Claude Code session to pick up the change."
