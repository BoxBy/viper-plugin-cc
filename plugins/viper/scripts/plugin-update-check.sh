#!/usr/bin/env bash
# plugin-update-check.sh — SessionStart hook: compare each installed plugin's
# version (from the per-plugin cache dir name) against the marketplace's
# declared latest in `.claude-plugin/marketplace.json`. Emit a short
# additionalContext summary when any plugin is behind so the user sees it on
# every session start without running a command.
#
# Dual output:
#   1. SessionStart Claude transcript: `additionalContext` JSON on stdout.
#   2. Statusline 2nd line: cache file written to
#      ~/.claude/.cache/plugin-updates.txt with a compact one-line summary
#      (e.g. "📦 updates: viper 0.2.0→0.3.0, self-improve 0.2.0→0.3.0").
#      statusline.sh reads it and renders below the main status line.
#      Empty file (or missing) → no 2nd line. TTL 6h (mtime-based) to avoid
#      showing stale notifications after the user ran /plugin update.
#
# Output contract (Claude Code hook protocol):
#   - Always exit 0. A silent hook is fine; failing the hook just prints
#     [hook failure] noise in the transcript.
#   - Emit JSON on stdout when there's something to say:
#       { "hookSpecificOutput": {
#           "hookEventName": "SessionStart",
#           "additionalContext": "📦 Plugin updates available: ..."
#       } }
#     Anything else goes to /dev/null.
#
# Design:
#   - Fetches marketplace clones (git fetch --quiet, no reset) so we have the
#     latest `marketplace.json` without mutating the user's checkout — the
#     actual cache copy only moves when the user runs `/plugin update`.
#   - Per-plugin "installed version" = highest semver subdirectory in
#     ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.
#   - Skips gracefully on any error (missing jq, missing git, rate-limited
#     upstream, etc.) — statusline-style fail-open.

exec 2>/dev/null

_want_jq() { command -v jq >/dev/null 2>&1; }
_want_git() { command -v git >/dev/null 2>&1; }

if ! _want_jq; then exit 0; fi

out=""
marketplaces_root="${HOME}/.claude/plugins/marketplaces"
cache_root="${HOME}/.claude/plugins/cache"

[ -d "$marketplaces_root" ] || exit 0

for mkt_dir in "$marketplaces_root"/*/; do
  [ -d "$mkt_dir" ] || continue
  mkt_name=$(basename "$mkt_dir")
  mkt_json="$mkt_dir/.claude-plugin/marketplace.json"
  [ -f "$mkt_json" ] || continue

  # Refresh remote state WITHOUT touching the working tree. git fetch alone
  # updates FETCH_HEAD / remote refs; we read `marketplace.json` from
  # origin/HEAD via `git show` so a diverged local clone never stalls us.
  if _want_git; then
    (cd "$mkt_dir" && timeout 5 git fetch --quiet 2>/dev/null) &
  fi
done
wait 2>/dev/null

for mkt_dir in "$marketplaces_root"/*/; do
  [ -d "$mkt_dir" ] || continue
  mkt_name=$(basename "$mkt_dir")
  mkt_json="$mkt_dir/.claude-plugin/marketplace.json"
  [ -f "$mkt_json" ] || continue

  # Prefer origin/HEAD copy when git is usable; fall back to working tree.
  remote_json=""
  if _want_git; then
    remote_json=$(cd "$mkt_dir" && git show origin/HEAD:.claude-plugin/marketplace.json 2>/dev/null)
  fi
  if [ -z "$remote_json" ]; then
    remote_json=$(cat "$mkt_json")
  fi

  # Each plugin row: name<TAB>version. Skip entries without an explicit
  # semver-ish version — some marketplaces declare plugins without a
  # `version` field and jq emits `null` which is not comparable.
  while IFS=$'\t' read -r plugin_name latest_version; do
    [ -z "$plugin_name" ] && continue
    [ -z "$latest_version" ] && continue
    [ "$latest_version" = "null" ] && continue
    installed_dir="$cache_root/$mkt_name/$plugin_name"
    [ -d "$installed_dir" ] || continue
    installed_version=$(ls "$installed_dir" 2>/dev/null | sort -V | tail -1)
    [ -z "$installed_version" ] && continue
    [ "$installed_version" = "$latest_version" ] && continue

    # Semver compare: only flag when latest > installed (sort -V picks the
    # greater of the two). Skip downgrades (remote rolled back / local dev
    # build ahead of marketplace) which otherwise generate noise.
    greater=$(printf '%s\n%s\n' "$installed_version" "$latest_version" \
      | sort -V | tail -1)
    if [ "$greater" = "$latest_version" ] && [ "$greater" != "$installed_version" ]; then
      out+=$'\n  • '"$plugin_name"'@'"$mkt_name"': '"$installed_version"' → '"$latest_version"
    fi
  done < <(printf '%s' "$remote_json" | jq -r '.plugins[]? | "\(.name)\t\(.version // "")"' 2>/dev/null)
done

# Statusline cache file: compact one-liner for rendering below the main
# status line. Missing/empty/stale → no 2nd line. statusline.sh reads it.
cache_dir="${HOME}/.claude/.cache"
cache_file="${cache_dir}/plugin-updates.txt"
mkdir -p "$cache_dir" 2>/dev/null

if [ -n "$out" ]; then
  # Transcript: full multi-line summary for Claude to surface in conversation.
  summary='📦 Plugin updates available:'"$out"$'\nRun `/plugin update <plugin>@<marketplace>` to upgrade. For viper, re-run `/harness-install --mode=symlink` after update to re-point ~/.claude/ symlinks at the new version.'
  jq -n --arg ctx "$summary" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

  # Statusline cache: compact comma-joined form. "  • NAME@MKT: X → Y" rows
  # → "NAME X→Y" joined by ", ". Drops the marketplace suffix because this
  # repo owns exactly one marketplace (writer-agent-quality-check) and the
  # verbose form just adds noise to a line the user glances at.
  # Uses sed + paste (POSIX, works on both BSD/macOS and GNU awk).
  compact=$(printf '%s\n' "$out" \
    | sed -n 's|^  • \([^@]*\)@[^:]*: \([^ ]*\) → \([^ ]*\).*|\1 \2→\3|p' \
    | paste -sd ',' - \
    | sed 's/,/, /g')
  # Single user-facing action hint. /viper:update-plugins handles the entire
  # upgrade flow (per-plugin /plugin update + harness-install re-link for viper
  # + cache rebuild) so we never tell users to run /plugin update directly
  # from the statusline.
  printf 'updates: %s — /viper:update-plugins' "$compact" > "$cache_file"
else
  # No updates: clear cache so statusline stops showing stale notice.
  : > "$cache_file"
fi

exit 0
