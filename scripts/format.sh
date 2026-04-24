#!/usr/bin/env bash
# format.sh — render statusline as a SINGLE LINE (Claude Code statusline renders
# multi-line output as multiple visible rows, which is what the user explicitly
# does NOT want here). Everything fits on one line, separated by `│`.
#
# Segments (left-to-right, each conditional):
#   <model>                       — tier color (opus=magenta, sonnet=yellow, haiku=green)
#   <ctx_used>/<ctx_max> <pct>%   — threshold color on %: <70 green, 70-84 yellow, 85+ red
#   $<cost>                       — (optional) total session cost USD
#   5h:<pct>% wk:<pct>%           — (OAuth only) rate buckets with threshold color
#   skill:<name>                  — cyan, most recent Skill tool_use
#   PR:#<n> [state]               — yellow number + dim state; from `gh pr view`
#   [team <name>] <m1>,<m2>(Pi)…  — team roster with active-tool badges (compact)
#   ⎇ Pi Cx Hk                    — (no team) solo session active tools

# No `set -e / -u / pipefail` — renderer must never die mid-line. Individual
# branches already guard with `:-` defaults; residual errors are swallowed.
exec 2>/dev/null
trap ':' ERR

# ANSI palette
RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
GRAY=$'\e[90m'
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'
WHITE=$'\e[37m'
BRIGHT_MAGENTA=$'\e[95m'
BRIGHT_CYAN=$'\e[96m'

_ctx_color() {
  local pct="${1:-0}"
  if [ "$pct" -ge 85 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

_rate_color() {
  local pct="${1:-0}"
  if [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 75 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

_model_color() {
  local lower; lower=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *opus*)   printf '%s' "$BRIGHT_MAGENTA" ;;
    *sonnet*) printf '%s' "$YELLOW" ;;
    *haiku*)  printf '%s' "$GREEN" ;;
    *)        printf '%s' "$CYAN" ;;
  esac
}

# Model tier label shown next to teammate name. "claude-opus-4-7" → "opus",
# "claude-sonnet-4-6" → "sonnet", etc. Gray, brief — reader sees WHICH model
# is paying per teammate without hunting config.json.
_model_tier() {
  local lower; lower=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *opus*)   printf '%s' "opus" ;;
    *sonnet*) printf '%s' "sonnet" ;;
    *haiku*)  printf '%s' "haiku" ;;
    *)        printf '' ;;
  esac
}

# Claude Code assigns each teammate a color ("blue", "green", "yellow",
# "red", "magenta", "cyan", "white") and renders the teammate bar using that
# color. We read the same value verbatim so the statusline tree matches the
# teammate bar visually.
_teammate_color() {
  case "${1:-}" in
    blue)    printf '%s' "$BLUE" ;;
    green)   printf '%s' "$GREEN" ;;
    yellow)  printf '%s' "$YELLOW" ;;
    red)     printf '%s' "$RED" ;;
    magenta) printf '%s' "$MAGENTA" ;;
    cyan)    printf '%s' "$CYAN" ;;
    white)   printf '%s' "$WHITE" ;;
    *)       printf '' ;;
  esac
}

# Env from statusline.sh
STL_MODEL="${STL_MODEL:-Claude}"
STL_REPO="${STL_REPO:-}"
STL_BRANCH="${STL_BRANCH:-}"
STL_WORKTREE="${STL_WORKTREE:-}"
STL_CTX_USED="${STL_CTX_USED:-0}"
STL_CTX_MAX="${STL_CTX_MAX:-200000}"
STL_CTX_PCT="${STL_CTX_PCT:-0}"
STL_COST_USD="${STL_COST_USD:-}"
STL_FIVE_HOUR="${STL_FIVE_HOUR:-}"
STL_FIVE_HOUR_RESET="${STL_FIVE_HOUR_RESET:-}"
STL_WEEKLY="${STL_WEEKLY:-}"
STL_WEEKLY_RESET="${STL_WEEKLY_RESET:-}"
STL_ACTIVE_SKILL="${STL_ACTIVE_SKILL:-}"
STL_PRS="${STL_PRS:-}"
STL_TEAM="${STL_TEAM:-}"
STL_MEMBERS="${STL_MEMBERS:-}"
STL_PI="${STL_PI:-}"
STL_CODEX="${STL_CODEX:-}"
STL_HAIKU="${STL_HAIKU:-}"
STL_SUBAGENTS="${STL_SUBAGENTS:-}"
STL_RALPH_ITER="${STL_RALPH_ITER:-}"
STL_RALPH_MAX="${STL_RALPH_MAX:-}"

_humanize_tokens() {
  local n="$1"
  if [ "$n" -ge 1000000 ]; then
    # 1.2M format
    local m=$(( n / 1000000 ))
    local frac=$(( (n % 1000000) / 100000 ))
    if [ "$frac" -gt 0 ]; then printf '%d.%dM' "$m" "$frac"
    else printf '%dM' "$m"; fi
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' "$((n / 1000))"
  else
    printf '%d' "$n"
  fi
}

_humanize_duration() {
  local s="${1:-}"
  [ -z "$s" ] && return
  # ISO timestamp → diff
  if printf '%s' "$s" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    local target_epoch now
    target_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$s" +%s 2>/dev/null \
      || date -d "$s" +%s 2>/dev/null \
      || echo "")
    [ -z "$target_epoch" ] && return
    now=$(date +%s)
    local diff=$((target_epoch - now))
    [ "$diff" -lt 0 ] && diff=0
    s="$diff"
  elif printf '%s' "$s" | grep -qE '[a-zA-Z]'; then
    printf '%s' "$s"
    return
  fi
  # Guard: numeric only, sane range
  case "$s" in
    ''|*[!0-9]*) return ;;
  esac
  local total=${s%.*}
  # If value is larger than current wall-clock epoch, it's an absolute
  # timestamp (Claude Code sends `resets_at` as unix epoch seconds, not
  # a duration). Convert to "seconds remaining".
  local _now
  _now=$(date +%s)
  if [ "$total" -gt "$_now" ]; then
    total=$(( total - _now ))
  fi
  [ "$total" -lt 0 ] && total=0
  local d=$(( total / 86400 ))
  local h=$(( (total % 86400) / 3600 ))
  local m=$(( (total % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then
    printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# Agent type → single-char code (uppercase = opus tier, lowercase = sonnet/haiku).
# Falls through two keys: teammate NAME first (most informative — "architect",
# "coder-1"), agent_type second (generic — "general-purpose"). This matches
# how Claude Code native teams record members: `agentType` is often
# "general-purpose" while `name` carries the role.
_agent_code() {
  local name="${1:-}"
  local agent_type="${2:-}"
  local model="${3:-}"
  local candidate
  local code
  for candidate in "${name%%-*}" "${name##*:}" "${agent_type##*:}"; do
    case "$candidate" in
      team-lead|lead) code="L"; break ;;
      architect)      code="A"; break ;;
      coder)          code="C"; break ;;
      debugger)       code="D"; break ;;
      reviewer)       code="R"; break ;;
      explore)        code="e"; break ;;
      planner|plan)   code="P"; break ;;
      executor|exec)  code="X"; break ;;
      verifier|verify) code="V"; break ;;
    esac
  done
  # Fallback: first char of name
  [ -z "${code:-}" ] && code="${name:0:1}"
  [ -z "$code" ] && code="?"
  if printf '%s' "$model" | grep -qi 'opus'; then
    printf '%s' "$(printf '%s' "$code" | tr '[:lower:]' '[:upper:]')"
  elif [ -n "$model" ]; then
    printf '%s' "$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')"
  else
    printf '%s' "$code"
  fi
}

# ==== Build single-line output ============================================
SEP="${GRAY}│${RESET}"
out=""
_add() {
  # Append segment with separator (skip leading separator on empty out)
  local seg="$1"
  [ -z "$seg" ] && return
  if [ -z "$out" ]; then
    out="$seg"
  else
    out="${out} ${SEP} ${seg}"
  fi
}

# 1. Header: bold model name, tier color. Team count appended if active.
out="${BOLD}$(_model_color "$STL_MODEL")${STL_MODEL}${RESET}"

# 1.5. Repo / branch — dim gray repo, branch in CYAN (main worktree) or
# MAGENTA (linked worktree), plus a `[branch]` / `[worktree]` label so the
# user knows whether they're editing the main checkout or a linked copy.
# Rendered on its OWN line below the main status row (stored in
# $repo_branch_line, assembled near the end). Detached HEAD: `@<shortSHA>`.
repo_branch_line=""
if [ -n "$STL_REPO" ] || [ -n "$STL_BRANCH" ]; then
  seg=""
  [ -n "$STL_REPO" ] && seg="${GRAY}${DIM}${STL_REPO}${RESET}"
  if [ -n "$STL_BRANCH" ]; then
    [ -n "$seg" ] && seg="${seg}${GRAY}/${RESET}"
    case "$STL_WORKTREE" in
      worktree) branch_color="$MAGENTA" ;;   # linked worktree — distinct
      *)        branch_color="$CYAN" ;;       # main-worktree branch (default)
    esac
    seg="${seg}${branch_color}${STL_BRANCH}${RESET}"
  fi
  if [ -n "$STL_WORKTREE" ]; then
    seg="${seg} ${GRAY}${DIM}[${STL_WORKTREE}]${RESET}"
  fi
  repo_branch_line="$seg"
fi

# 2. Context: "ctx:N%" (labeled — bare "N%" was ambiguous)
ctx_color=$(_ctx_color "$STL_CTX_PCT")
out="${out} ${GRAY}ctx:${RESET}${ctx_color}${STL_CTX_PCT}%${RESET}"

# 2b. Ralph loop: "ralph:iter/max" — YELLOW numbers, shown when active
if [ -n "$STL_RALPH_ITER" ] && [ -n "$STL_RALPH_MAX" ]; then
  out="${out} ${SEP} ${GRAY}ralph:${YELLOW}${STL_RALPH_ITER}${GRAY}/${STL_RALPH_MAX}${RESET}"
fi

# 3. Cost — intentionally omitted per user preference (rate_limits percentages
# carry the "how much quota used" signal; raw $ cost adds visual noise without
# actionable info for this workflow).

# 4. Rate limits (OAuth only) — labels + resets_in are gray (context, not
# signal), percent keeps the rate_color (green/yellow/red by utilization).
if [ -n "$STL_FIVE_HOUR" ] || [ -n "$STL_WEEKLY" ]; then
  rate_seg=""
  if [ -n "$STL_FIVE_HOUR" ]; then
    rs=$(_humanize_duration "$STL_FIVE_HOUR_RESET")
    rc=$(_rate_color "${STL_FIVE_HOUR%.*}")
    rate_seg="${GRAY}5h:${RESET}${rc}${STL_FIVE_HOUR%.*}%${RESET}"
    [ -n "$rs" ] && rate_seg="${rate_seg}${GRAY}(${rs})${RESET}"
  fi
  if [ -n "$STL_WEEKLY" ]; then
    rs=$(_humanize_duration "$STL_WEEKLY_RESET")
    rc=$(_rate_color "${STL_WEEKLY%.*}")
    [ -n "$rate_seg" ] && rate_seg="${rate_seg} "
    rate_seg="${rate_seg}${GRAY}wk:${RESET}${rc}${STL_WEEKLY%.*}%${RESET}"
    [ -n "$rs" ] && rate_seg="${rate_seg}${GRAY}(${rs})${RESET}"
  fi
  _add "$rate_seg"
fi

# 5. Active skill
if [ -n "$STL_ACTIVE_SKILL" ]; then
  # Strip namespace prefix (oh-my-claudecode:plan → plan)
  skill_short="${STL_ACTIVE_SKILL##*:}"
  _add "${CYAN}skill:${skill_short}${RESET}"
fi

# 6. PRs — list of "#N" numbers with OSC 8 hyperlinks. Color per review_signal:
#   🔴 RED    = unresolved (리뷰 있음, 미해결 스레드 존재)
#   🟡 YELLOW = resolved (코멘트 있지만 전부 해결됨, 아직 APPROVED 안 됨 → 진행 중)
#   🟢 GREEN  = approved OR merged (완료)
#   default  = GRAY (리뷰 없음)
if [ -n "$STL_PRS" ]; then
  pr_entries=""
  while IFS=$'\t' read -r pr_num pr_state pr_url pr_signal; do
    [ -z "$pr_num" ] && continue
    case "$pr_signal" in
      unresolved) num_color="$RED" ;;
      resolved)   num_color="$YELLOW" ;;
      approved|merged) num_color="$GREEN" ;;
      *)          num_color="$GRAY" ;;
    esac
    if [ -n "$pr_url" ] && [ "$pr_url" != "null" ]; then
      # OSC 8 hyperlink wrapping the "#N" token
      num_rendered=$(printf '\e]8;;%s\e\\%s#%s%s\e]8;;\e\\' \
        "$pr_url" "$num_color" "$pr_num" "$RESET")
    else
      num_rendered="${num_color}#${pr_num}${RESET}"
    fi
    if [ -z "$pr_entries" ]; then pr_entries="$num_rendered"
    else pr_entries="${pr_entries}${GRAY},${RESET} ${num_rendered}"; fi
  done <<< "$STL_PRS"
  [ -n "$pr_entries" ] && _add "${GRAY}PR:${RESET}${pr_entries}"
fi

# 7. Team tree (multi-line) when team is active.
#
# Canonical Claude Code team shape (from ~/.claude/teams/<name>/config.json,
# verified 2026-04-24 on Claude Code 2.1.119):
#   { name, leadAgentId, members: [{ agentId, name, agentType, model, color, ... }] }
#
# Rendering contract:
#   • Active team → always emit a `[team <name>]` header line, even when only
#     the lead exists (solo team shouldn't vanish from the UI right after
#     TeamCreate but before any workers join).
#   • team-lead is intentionally NOT rendered in the worker tree — the header
#     row (model · ctx%) already represents "me". Adding @main would duplicate.
#   • statusline.sh pre-filters team-lead out of STL_MEMBERS, so we just walk
#     the remaining rows and render them as @<name>.
team_tree_lines=""
if [ -n "$STL_TEAM" ]; then
  team_tree_lines+=$'\n'"${GRAY}[team ${CYAN}${STL_TEAM}${RESET}${GRAY}]${RESET}"

  member_lines=()
  while IFS= read -r mline; do
    [ -n "$mline" ] && member_lines+=("$mline")
  done <<< "$STL_MEMBERS"
  member_count=${#member_lines[@]}

  if [ "$member_count" -eq 0 ]; then
    team_tree_lines+=" ${GRAY}${DIM}(solo — no workers yet)${RESET}"
  fi

  if [ "$member_count" -gt 0 ]; then
    idx=0
    for mline in "${member_lines[@]}"; do
      idx=$((idx+1))
      name=$(printf '%s' "$mline" | cut -f1)
      agent_type=$(printf '%s' "$mline" | cut -f2)
      model=$(printf '%s' "$mline" | cut -f3)
      color_field=$(printf '%s' "$mline" | cut -f4)

      # Primary: teammate bar color (matches Claude Code native UI).
      # Fallback: model tier color when no color was assigned (e.g. team-lead).
      tcolor=$(_teammate_color "$color_field")
      [ -z "$tcolor" ] && tcolor=$(_model_color "$model")

      # team-lead is the main session
      if [ "$name" = "team-lead" ] || [ "$agent_type" = "team-lead" ]; then
        display="@main"
      else
        display="@${name}"
      fi

      suffix=""
      # Match sentinel caller against teammate name, agent_type, and — for
      # the team-lead — also `advisor`/`main` (the hook defaults unknown
      # sessions to "advisor", and we display team-lead as @main).
      _match_set() {
        local set="$1"
        printf '%s' "$set" | grep -qxF "$name" 2>/dev/null && return 0
        [ -n "$agent_type" ] && printf '%s' "$set" | grep -qxF "$agent_type" 2>/dev/null && return 0
        if [ "$name" = "team-lead" ] || [ "$agent_type" = "team-lead" ]; then
          printf '%s' "$set" | grep -qxF "advisor" 2>/dev/null && return 0
          printf '%s' "$set" | grep -qxF "main" 2>/dev/null
        else
          return 1
        fi
      }
      # Badge color = this teammate's Claude Code bar color. Name stays gray;
      # the color moves to the tool badge so you can instantly identify which
      # teammate (by bar color) is running which tool.
      pi_on=0; cx_on=0; hk_on=0
      _match_set "$STL_PI"    && { pi_on=1; suffix="${suffix}${tcolor}(Pi)${RESET}"; }
      _match_set "$STL_CODEX" && { cx_on=1; suffix="${suffix}${tcolor}(Codex)${RESET}"; }
      _match_set "$STL_HAIKU" && { hk_on=1; suffix="${suffix}${tcolor}(Haiku)${RESET}"; }

      is_last_worker=0
      if [ "$idx" -lt "$member_count" ]; then prefix="├─"; else prefix="└─"; is_last_worker=1; fi
      # Teammate names are always dim gray — the visual signal belongs to the
      # active-tool badge (Pi=magenta, Codex=yellow, Haiku=cyan). Making names
      # colorful too is visual noise; gray names + colored badges lets the eye
      # jump to the workers actually doing something.
      label_color="$GRAY"
      # Unused in this branch — kept for future reintroduction.
      : "$tcolor"
      # Model tier label — shows whether this teammate is opus/sonnet/haiku.
      # Lead row (synthetic team-lead) has empty model → skip.
      tier=$(_model_tier "$model")
      tier_label=""
      [ -n "$tier" ] && tier_label=" ${GRAY}[${tier}]${RESET}"
      team_tree_lines+=$'\n'"${GRAY}${prefix}${RESET} ${label_color}${display}${RESET}${tier_label}${suffix}"

      # Nested subagents — helpers spawned by this worker (parent == worker name).
      # Match primarily on the worker's unique name (new name-first policy), but
      # also accept agentType as a legacy fallback: older metadata writers set
      # parent=agentType when meta.name was empty, so dropping that path would
      # hide those helpers from the tree (statusline.sh still emits them).
      if [ -n "$STL_SUBAGENTS" ]; then
        while IFS=$'\t' read -r _sa_id _sa_type _sa_desc _sa_parent; do
          [ -z "$_sa_id" ] && continue
          [ "$_sa_parent" = "$name" ] || [ "$_sa_parent" = "$agent_type" ] || continue
          # Vertical guide for non-last worker, blank for last.
          if [ "$is_last_worker" = "1" ]; then sa_guide="   "; else sa_guide="${GRAY}│${RESET}  "; fi
          sa_desc_trunc="${_sa_desc:0:50}"
          [ "${#_sa_desc}" -gt 50 ] && sa_desc_trunc="${sa_desc_trunc}…"
          sa_display="${GRAY}◦ ${_sa_type}${RESET}"
          [ -n "$sa_desc_trunc" ] && sa_display="${sa_display}${GRAY}: ${sa_desc_trunc}${RESET}"
          team_tree_lines+=$'\n'"${sa_guide}${sa_display}"
        done <<< "$STL_SUBAGENTS"
      fi
    done
  fi
fi

# 8. Solo tools (no team): show active pi/codex/haiku
if [ -z "$STL_TEAM" ]; then
  tool_flags=""
  [ -n "$STL_PI" ]    && tool_flags="${tool_flags}${MAGENTA}Pi${RESET} "
  [ -n "$STL_CODEX" ] && tool_flags="${tool_flags}${YELLOW}Codex${RESET} "
  [ -n "$STL_HAIKU" ] && tool_flags="${tool_flags}${CYAN}Haiku${RESET} "
  if [ -n "$tool_flags" ]; then
    _add "${GRAY}⎇${RESET} ${tool_flags% }"
  fi
fi

# 9. Top-level subagents (parent=main or unknown) — rendered BELOW team tree
# with ◦ marker. In solo mode, ALL active subagents render here (no worker to
# attribute them to).
if [ -n "$STL_SUBAGENTS" ]; then
  subagent_lines=""
  while IFS=$'\t' read -r _sa_id _sa_type _sa_desc _sa_parent; do
    [ -z "$_sa_id" ] && continue
    # In team mode, skip subagents already nested under a worker (parent matches
    # a worker agentType). In solo mode, include everyone.
    if [ -n "$STL_TEAM" ]; then
      case "$(printf '%s' "$_sa_parent" | tr '[:upper:]' '[:lower:]')" in
        main|unknown|"") ;;  # render at top level
        *) continue ;;        # rendered nested under worker
      esac
    fi
    sa_desc_trunc="${_sa_desc:0:60}"
    [ "${#_sa_desc}" -gt 60 ] && sa_desc_trunc="${sa_desc_trunc}…"
    sa_display="${GRAY}◦ ${_sa_type}${RESET}"
    [ -n "$sa_desc_trunc" ] && sa_display="${sa_display}${GRAY}: ${sa_desc_trunc}${RESET}"
    subagent_lines+=$'\n'"${sa_display}"
  done <<< "$STL_SUBAGENTS"
  team_tree_lines+="$subagent_lines"
fi

# Plugin-update top line: SessionStart hook writes a compact one-liner
# (`updates: NAME X→Y, … — /plugin update NAME`) to
# ~/.claude/.cache/plugin-updates.txt when any installed plugin is behind the
# marketplace. Empty/missing file → no top line. TTL 6h so a stale entry left
# after `/plugin update` doesn't keep flashing. Dim gray so it's legible but
# never steals attention from the main line. Rendered on the FIRST line
# (above the status row) because it's actionable user notice, not status.
plugin_update_line=""
plugin_update_cache="${HOME}/.claude/.cache/plugin-updates.txt"
if [ -s "$plugin_update_cache" ]; then
  # file size > 0 AND mtime within 6h
  cache_age_s=$(( $(date +%s) - $(stat -f %m "$plugin_update_cache" 2>/dev/null || stat -c %Y "$plugin_update_cache" 2>/dev/null || echo 0) ))
  if [ "$cache_age_s" -ge 0 ] && [ "$cache_age_s" -lt 21600 ]; then
    plugin_update_raw=$(tr -d '\n' < "$plugin_update_cache" 2>/dev/null)
    if [ -n "$plugin_update_raw" ]; then
      plugin_update_line="${GRAY}${DIM}${plugin_update_raw}${RESET}"$'\n'
    fi
  fi
fi

# Line order (top → bottom):
#   1. plugin_update_line (if updates available)    — actionable top notice
#   2. out (main status)                            — model / ctx / PR / rate / skill
#   3. repo_branch_line (if in a git repo)          — own line; branch names can be long
#   4. team_tree_lines (if team active)             — multi-line tree
[ -n "$repo_branch_line" ] && repo_branch_line=$'\n'"$repo_branch_line"
printf '%s%s%s%s\n' "$plugin_update_line" "$out" "$repo_branch_line" "$team_tree_lines"
