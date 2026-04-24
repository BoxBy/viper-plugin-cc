#!/usr/bin/env bash
# statusline.sh — Claude Code statusline entrypoint
#
# Reads stdin JSON Claude Code pipes to its statusline command, augments with
# local state (team config, pi/codex/haiku sentinels, active skill extracted
# from transcript.jsonl, PR number for current git branch), and delegates to
# format.sh for ANSI rendering.
#
# Live schema from capture (Claude Code 2.1.117):
#   .model.display_name, .model.id (e.g. "claude-opus-4-7[1m]")
#   .context_window.context_window_size (e.g. 1000000 for [1m] model)
#   .context_window.used_percentage (0-100)
#   .context_window.current_usage.{input,output,cache_creation,cache_read}_tokens
#   .cost.total_cost_usd
#   .transcript_path (absolute path to session JSONL)
#   .workspace.current_dir / .cwd
#   .session_id, .version
#   Fields NOT present on API-key sessions: .rate_limits.* (OAuth subscriber only)

# Statusline must NEVER disappear. No `set -e`, no `set -u`, no `pipefail`.
# Any single subpipeline returning non-zero should leave the rest of the
# rendering alone, not kill the script. All stderr redirected to /dev/null so
# partial stack traces don't leak into the terminal.
exec 2>/dev/null

# Any ERR anywhere becomes a no-op — the EXIT trap still guarantees output.
trap ':' ERR

# Last-resort fallback: if the script dies for any reason before reaching the
# printf at the end, the EXIT trap prints a minimal "Claude" so the status bar
# is never blank.
_emitted=0
trap '[ "${_emitted:-0}" = 0 ] && printf "Claude\n"; exit 0' EXIT

input=$(cat 2>/dev/null || echo '{}')
if ! echo "$input" | jq -e . >/dev/null 2>&1; then
  _emitted=1
  echo "Claude"
  exit 0
fi

# ---- 1. Model + context ---------------------------------------------------
model_display=$(jq -r '.model.display_name // .model.id // "Claude"' <<< "$input")

# Context window size — prefer context_window.context_window_size (the real
# model window, e.g. 1000000 for [1m] variants), fall back through legacy.
ctx_max=$(jq -r '
  .context_window.context_window_size //
  .context_window.total //
  .context.tokens_max // .context_tokens_max // 200000
' <<< "$input")

# Percentage — Claude Code computes .context_window.used_percentage natively.
ctx_pct_raw=$(jq -r '
  .context_window.used_percentage //
  .used_percentage //
  empty
' <<< "$input")

if [ -n "$ctx_pct_raw" ] && [ "${ctx_max:-0}" -gt 0 ] 2>/dev/null; then
  ctx_pct=${ctx_pct_raw%.*}
  # Derive used tokens from pct+max (more accurate than summing current_usage
  # which represents only the last turn's deltas, not cumulative context fill).
  ctx_used=$(( ctx_max * ctx_pct / 100 ))
else
  ctx_used=$(jq -r '
    ((.context_window.current_usage.input_tokens // 0) +
     (.context_window.current_usage.output_tokens // 0) +
     (.context_window.current_usage.cache_creation_input_tokens // 0) +
     (.context_window.current_usage.cache_read_input_tokens // 0))
  ' <<< "$input" 2>/dev/null || echo 0)
  if [ "${ctx_max:-0}" -gt 0 ] 2>/dev/null; then
    ctx_pct=$(( ctx_used * 100 / ctx_max ))
  else
    ctx_pct=0
  fi
fi

cost_usd=$(jq -r '.cost.total_cost_usd // empty' <<< "$input")

# ---- 2. rate_limits (OAuth subscriber only; absent on API-key sessions) ---
five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.percent // empty' <<< "$input")
five_hour_reset=$(jq -r '.rate_limits.five_hour.resets_in // .rate_limits.five_hour.resets_at // empty' <<< "$input")
weekly=$(jq -r '.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.percent // empty' <<< "$input")
weekly_reset=$(jq -r '.rate_limits.seven_day.resets_in // .rate_limits.seven_day.resets_at // empty' <<< "$input")

# ---- 3. Active skill from transcript (OMC pattern) ------------------------
# OMC extracts lastActivatedSkill by scanning transcript.jsonl for assistant
# tool_use blocks where name == "Skill" OR "proxy_Skill", reading .input.skill.
transcript=$(jq -r '.transcript_path // empty' <<< "$input")
active_skill=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Grep-first, jq-second: find the LAST transcript line with a Skill/proxy_Skill
  # tool_use, then run jq on that single line. Drop the skill badge once the
  # last invocation is older than STL_SKILL_STALE_AFTER seconds (default 300s)
  # so the header doesn't cling to a skill the user ran an hour ago.
  last_skill_line=$(grep -E '"name":\s*"(Skill|proxy_Skill)"' "$transcript" 2>/dev/null \
    | tail -1)
  if [ -n "$last_skill_line" ]; then
    # Timestamp lives at the top level of each transcript line as ISO-8601.
    skill_ts=$(printf '%s' "$last_skill_line" | jq -r '.timestamp // empty' 2>/dev/null)
    if [ -n "$skill_ts" ]; then
      # macOS `date -j -f` vs GNU `date -d` portable parse.
      skill_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${skill_ts%.*}" +%s 2>/dev/null \
        || date -d "$skill_ts" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      age=$(( now_epoch - skill_epoch ))
      stale_after="${STL_SKILL_STALE_AFTER:-300}"
      if [ "$skill_epoch" -gt 0 ] && [ "$age" -le "$stale_after" ]; then
        active_skill=$(printf '%s' "$last_skill_line" \
          | jq -rc '.message.content[]?
                    | select(.type == "tool_use" and (.name == "Skill" or .name == "proxy_Skill"))
                    | .input.skill // empty' 2>/dev/null \
          | tail -1)
      fi
    fi
  fi
fi

# ---- 4. Active PR for current git branch (cached 60s) ---------------------
cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<< "$input")

# Repo + branch segment — rendered on its own line below the main status row.
#
# Three pieces collected here, used by format.sh:
#   STL_REPO     — canonical repo name (same across all linked worktrees),
#                  so user sees which REPO they're in. From common-dir's
#                  parent basename.
#   STL_BRANCH   — current branch. Detached HEAD → "@<shortSHA>".
#   STL_WORKTREE — "branch" for the main worktree / "worktree" for a linked
#                  worktree. format.sh uses this to (a) color the branch
#                  name (CYAN for branch, MAGENTA for worktree) and (b)
#                  append a `[branch]` / `[worktree]` label so the user
#                  knows whether they're editing the main checkout or a
#                  linked copy.
#
# Main vs linked detection: `--absolute-git-dir` equals the common-dir
# ONLY in the main worktree; linked worktrees' git-dir lives under
# `<common>/worktrees/<name>/`.
repo_name=""
branch=""
worktree_label=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  _git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
  _common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null \
            || git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
  # Normalise common-dir to absolute if path-format flag wasn't supported.
  case "$_common" in
    /*) ;;
    *)  _common=$(cd "$cwd" && cd "$(dirname "$_common")" && pwd) ;;
  esac
  [ -n "$_common" ] && repo_name=$(basename "$(dirname "$_common")")
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
  if [ -z "$branch" ]; then
    # Detached HEAD — show short SHA in place of branch.
    branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)
    [ -n "$branch" ] && branch="@${branch}"
  fi
  if [ -n "$_git_dir" ] && [ -n "$_common" ]; then
    if [ "$_git_dir" = "$_common" ]; then
      worktree_label="branch"
    else
      worktree_label="worktree"
    fi
  fi
fi

active_pr_num=""
active_pr_state=""
active_pr_url=""
# Multi-PR list (tab-separated per line: num\tstate\turl\treview_signal)
# review_signal: "unresolved" | "resolved" | "approved" | "merged" | "none"
active_prs_raw=""
if [ -n "$cwd" ] && command -v gh >/dev/null 2>&1; then
  if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$branch" ]; then
      CACHE_DIR="${TMPDIR:-/tmp}/statusline-pr-cache"
      mkdir -p "$CACHE_DIR"
      # Cache key: path + branch (md5 for filename safety)
      key_input="$cwd|$branch"
      if command -v md5 >/dev/null 2>&1; then
        cache_key=$(printf '%s' "$key_input" | md5 -q)
      else
        cache_key=$(printf '%s' "$key_input" | md5sum | cut -d' ' -f1)
      fi
      cache_file="$CACHE_DIR/$cache_key.json"
      # Stat mtime — BSD and GNU compatible
      if [ -f "$cache_file" ]; then
        mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mtime ))
      else
        age=9999
      fi
      if [ "$age" -lt 60 ] && [ -f "$cache_file" ]; then
        active_prs_raw=$(cat "$cache_file")
      else
        # Collect ALL open PRs where current branch is either head or base,
        # then add the most recent default PR as fallback. Sort by number.
        # Review signal per-PR derived from reviewThreads + reviewDecision:
        #   unresolved = any open thread → RED (리뷰 있음)
        #   resolved   = comments present but all threads resolved → YELLOW (진행 중)
        #   approved   = reviewDecision APPROVED → GREEN (완료)
        #   merged     = .state == MERGED → GREEN
        #   none       = no reviews yet → no color
        # All my open PRs in the repo containing $cwd — simple & predictable.
        # No branch filter: a worktree checkout on branch X still surfaces my
        # PR on branch Y in the same repo, which matches user intent.
        me=$(gh api user --jq .login 2>/dev/null || echo "")
        remote_url=$(cd "$cwd" && git remote get-url origin 2>/dev/null || echo "")
        owner=""; repo=""
        if [ -n "$remote_url" ]; then
          stripped=$(printf '%s' "$remote_url" \
            | sed -E 's|^https?://[^/]+/||; s|^git@[^:]+:||; s|\.git$||')
          owner=$(printf '%s' "$stripped" | cut -d/ -f1)
          repo=$(printf '%s' "$stripped" | cut -d/ -f2)
        fi
        # Two-step: (1) `gh pr list --author` for open PR numbers, (2) per-PR
        # GraphQL for reviewThreads (gh pr view --json doesn't expose that
        # field; search API returns 0 resolved count due to permission).
        combined_json="[]"
        if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$me" ]; then
          pr_nums=$(cd "$cwd" && gh pr list \
            --state open --author "$me" \
            --json number --limit 20 2>/dev/null \
            | jq -r '.[].number // empty' | sort -n)
          per_pr_gql='query($owner:String!,$repo:String!,$num:Int!) { repository(owner:$owner,name:$repo) { pullRequest(number:$num) { number state isDraft url reviewDecision reviewThreads(first:100) { nodes { isResolved } } } } }'
          pr_array="[]"
          for n in $pr_nums; do
            one=$(gh api graphql -f query="$per_pr_gql" \
              -F owner="$owner" -F repo="$repo" -F num="$n" 2>/dev/null \
              | jq -c '.data.repository.pullRequest // empty')
            [ -z "$one" ] && continue
            pr_array=$(jq -c --argjson p "$one" '. + [$p]' <<< "$pr_array")
          done
          combined_json=$(jq -c '
            sort_by(.number)
            | map({
                number,
                state: (if .isDraft then "draft" else (.state | ascii_downcase) end),
                url,
                review_signal: (
                  if .state == "MERGED" then "merged"
                  elif .reviewDecision == "APPROVED" then "approved"
                  elif ([.reviewThreads.nodes[]? | select(.isResolved | not)] | length) > 0 then "unresolved"
                  elif ([.reviewThreads.nodes[]?] | length) > 0 then "resolved"
                  else "none"
                  end)
              })' <<< "$pr_array")
        fi
        # Convert JSON array to tab-separated lines (num\tstate\turl\tsignal)
        active_prs_raw=$(jq -r '.[] | "\(.number)\t\(.state)\t\(.url)\t\(.review_signal)"' <<< "$combined_json")
        printf '%s' "$active_prs_raw" > "$cache_file"
      fi
    fi
  fi
fi

# ---- 5. Team + pi/codex/haiku active (local sentinels) --------------------
active_team=""
team_members_raw=""
# Claude Code 2.1.117 stores teams under ~/.claude/teams/<team>/ with:
#   - config.json: canonical members list (agentId, name, agentType, model, color)
#   - inboxes/<name>.json: message history per member
#
# We prefer config.json when present (true member list + teammate-bar color),
# and fall back to inboxes/ when config is momentarily absent (first few
# seconds after TeamCreate before teammates join).
if [ -d "$HOME/.claude/teams" ]; then
  # Active team = team dir most recently modified AND still warm (mtime within
  # TEAM_STALE_AFTER seconds — default 600 / 10 min). Without the warmth check
  # a torn-down team's config.json lingers and statusline keeps rendering
  # @main + teammates for a session that no longer exists.
  TEAM_STALE_AFTER="${STL_TEAM_STALE_AFTER:-600}"
  now_epoch=$(date +%s)
  # `|| true` on the whole pipeline because pipefail + grep-no-match + all-stale
  # teams would otherwise exit 1 and kill the script under set -e.
  # stat format differs: BSD (macOS) uses `-f %m`, GNU uses `-c %Y`. We call
  # each dir through a helper to produce "mtime\tdir" portably.
  _dir_mtime() {
    local d="$1"
    local m
    m=$(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || echo "")
    [ -n "$m" ] && printf '%s\t%s\n' "$m" "$d"
  }
  active_team=$(
    find "$HOME/.claude/teams" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | while read -r d; do _dir_mtime "$d"; done \
      | sort -rn \
      | while IFS=$'\t' read -r mtime dir; do
          [ -z "$mtime" ] && continue
          age=$(( now_epoch - mtime ))
          [ "$age" -gt "$TEAM_STALE_AFTER" ] && continue
          basename "$dir"
        done \
      | grep -vE '^default$' \
      | head -1 || true
  )

  if [ -n "$active_team" ]; then
    team_dir="$HOME/.claude/teams/$active_team"
    config_file="$team_dir/config.json"
    inbox_dir="$team_dir/inboxes"

    if [ -f "$config_file" ] && jq -e '.members | type == "array"' "$config_file" >/dev/null 2>&1; then
      # Primary path: config.json canonical member list.
      # Exclude team-lead (represented by header line as main session).
      # Filter out shut-down members by checking their inbox's latest
      # self-authored message (if inbox exists).
      # Use command substitution (captures stdout directly) — avoids the
      # predictable /tmp/statusline-members.$$ race / symlink risk.
      team_members_raw=$(
        jq -r '.members[] | select(.name != "team-lead") | "\(.name)\t\(.agentType // "")\t\(.model // "")\t\(.color // "")"' \
          "$config_file" 2>/dev/null \
          | while IFS=$'\t' read -r name agent_type model color; do
              [ -z "$name" ] && continue
              inbox_file="$inbox_dir/$name.json"
              if [ -f "$inbox_file" ]; then
                last_type=$(jq -rs --arg n "$name" '
                    [.[] | .[] | select(.from == $n)] | last // {} | .text // ""
                  ' "$inbox_file" 2>/dev/null \
                  | jq -r '.type // ""' 2>/dev/null)
                [ "$last_type" = "shutdown_approved" ] && continue
              fi
              printf '%s\t%s\t%s\t%s\n' "$name" "$agent_type" "$model" "$color"
            done
      )
    elif [ -d "$inbox_dir" ]; then
      # Fallback: no config.json yet, derive members from inbox file names.
      # Color comes from self-authored messages; liveness from last type.
      # Direct command substitution (no /tmp file).
      team_members_raw=$(
        member_names=$(ls "$inbox_dir"/*.json 2>/dev/null \
          | while read -r f; do basename "$f" .json; done)
        others=$(printf '%s\n' "$member_names" | grep -vxF team-lead || true)
        others=$(printf '%s\n' "$others" | sort -u | sed '/^$/d')
        for name in $others; do
          last_type=$(cat "$inbox_dir"/*.json 2>/dev/null \
            | jq -rs --arg n "$name" '
                [.[] | .[] | select(.from == $n)] | last // {} | .text // ""
              ' 2>/dev/null \
            | jq -r '.type // ""' 2>/dev/null)
          [ "$last_type" = "shutdown_approved" ] && continue
          color=$(cat "$inbox_dir"/*.json 2>/dev/null \
            | jq -rs --arg n "$name" '
                [.[] | .[] | select(.from == $n) | .color // empty] | last // ""
              ' 2>/dev/null)
          printf '%s\t%s\t%s\t%s\n' "$name" "" "" "$color"
        done
      )
    fi

    # Keep active_team even when worker list is empty (solo team-lead). The
    # team name header is informational on its own; suppressing it leaves the
    # user blind to "is my team still alive?" right after TeamCreate but
    # before workers join.
  fi
fi

_collect_active_callers() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null \
    | while read -r f; do
        local caller pid
        caller=$(jq -r '.caller // empty' "$f" 2>/dev/null)
        pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
        [ -z "$caller" ] && continue
        if [ -n "$pid" ] && [ "$pid" != "null" ]; then
          kill -0 "$pid" 2>/dev/null || continue
        fi
        printf '%s\n' "$caller"
      done \
    | awk 'NF && !seen[$0]++'
}
active_pi=$(_collect_active_callers "$HOME/.pi-cc-tasks/.active")
active_codex=$(_collect_active_callers "$HOME/.codex-cc-tasks/.active")
active_haiku=$(_collect_active_callers "$HOME/.claude-haiku/.active")

# ---- 5b. Active subagents (this session) ----------------------------------
# Claude Code persists subagent state under
# ~/.claude/projects/<project_slug>/<session_id>/subagents/agent-<id>.{jsonl,meta.json}
# `.meta.json` carries agentType + optional description. `.jsonl` mtime ≈ last
# turn — we treat a subagent as "active" if jsonl was written within
# STL_SUBAGENT_ACTIVE_WINDOW seconds (default 60).
#
# Parent linking:
#   - subagents with agentType in {architect, coder, debugger, reviewer} are
#     Viper team workers, rendered by the team-tree path (STL_MEMBERS).
#   - For other active subagents, grep for agent_id in (a) the main transcript
#     → parent=main, (b) each worker's jsonl → parent=<worker agentType>.
#
# Output tab-separated lines: agent_id \t agentType \t description \t parent
session_id=$(jq -r '.session_id // empty' <<< "$input")
active_subagents=""
if [ -n "$session_id" ] && [ -n "${transcript:-}" ]; then
  session_dir="$(dirname "$transcript")/$session_id"
  if [ -d "$session_dir" ]; then
    now_epoch=$(date +%s)
    window="${STL_SUBAGENT_ACTIVE_WINDOW:-60}"

    # Pass 1: pre-collect candidates — lines of "id<TAB>agentType<TAB>description".
    candidates=$(
      for meta in "$session_dir"/agent-*.meta.json; do
        [ -f "$meta" ] || continue
        agent_id=$(basename "$meta" .meta.json | sed 's/^agent-//')
        jsonl="$session_dir/agent-$agent_id.jsonl"
        [ -f "$jsonl" ] || continue
        mtime=$(stat -f %m "$jsonl" 2>/dev/null || stat -c %Y "$jsonl" 2>/dev/null || echo 0)
        age=$(( now_epoch - mtime ))
        [ "$age" -gt "$window" ] && continue
        a_type=$(jq -r '.agentType // "unknown"' "$meta" 2>/dev/null)
        a_desc=$(jq -r '.description // ""' "$meta" 2>/dev/null)
        printf '%s\t%s\t%s\n' "$agent_id" "$a_type" "$a_desc"
      done
    )

    # Pass 2: identify Viper worker agent ids (they are rendered via STL_MEMBERS,
    # not STL_SUBAGENTS). Everything else is a helper subagent.
    worker_agent_ids=$(printf '%s' "$candidates" \
      | awk -F'\t' 'tolower($2) ~ /^(architect|coder|debugger|reviewer)$/ {print $1}')

    # Pass 3: attribute each helper's parent. Top-level subagents (spawned by
    # the main session) appear by id in the main transcript; nested subagents
    # (spawned by a worker) appear in that worker's own jsonl.
    active_subagents=$(
      printf '%s\n' "$candidates" | while IFS=$'\t' read -r a_id a_type a_desc; do
        [ -z "$a_id" ] && continue
        lower_type=$(printf '%s' "$a_type" | tr '[:upper:]' '[:lower:]')
        # Skip team workers (rendered via STL_MEMBERS). Using if-chain instead
        # of case/esac — bash 3.2 on macOS has parser quirks with case inside
        # $( while ... done ) subshells.
        if [ "$lower_type" = "architect" ] || [ "$lower_type" = "coder" ] \
           || [ "$lower_type" = "debugger" ] || [ "$lower_type" = "reviewer" ]; then
          continue
        fi
        parent=""
        if grep -q -- "$a_id" "$transcript" 2>/dev/null; then
          parent="main"
        else
          for w_id in $worker_agent_ids; do
            w_jsonl="$session_dir/agent-$w_id.jsonl"
            [ -f "$w_jsonl" ] || continue
            if grep -q -- "$a_id" "$w_jsonl" 2>/dev/null; then
              parent=$(jq -r '.agentType // "worker"' "$session_dir/agent-$w_id.meta.json" 2>/dev/null)
              break
            fi
          done
        fi
        [ -z "$parent" ] && parent="unknown"
        printf '%s\t%s\t%s\t%s\n' "$a_id" "$a_type" "$a_desc" "$parent"
      done
    )
  fi
fi

# ---- 6. Delegate to format.sh ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export STL_MODEL="$model_display"
export STL_REPO="$repo_name"
export STL_BRANCH="$branch"
export STL_WORKTREE="$worktree_label"
export STL_CTX_USED="$ctx_used"
export STL_CTX_MAX="$ctx_max"
export STL_CTX_PCT="$ctx_pct"
export STL_COST_USD="$cost_usd"
export STL_FIVE_HOUR="$five_hour"
export STL_FIVE_HOUR_RESET="$five_hour_reset"
export STL_WEEKLY="$weekly"
export STL_WEEKLY_RESET="$weekly_reset"
export STL_ACTIVE_SKILL="$active_skill"
export STL_PRS="$active_prs_raw"
export STL_TEAM="$active_team"
export STL_MEMBERS="$team_members_raw"
export STL_PI="$active_pi"
export STL_CODEX="$active_codex"
export STL_HAIKU="$active_haiku"
export STL_SUBAGENTS="$active_subagents"

# Ralph state — read from global state file (stop-hook based loop)
ralph_state_file="$HOME/.claude/ralph-state.json"
ralph_iter=""
ralph_max=""
if [ -f "$ralph_state_file" ]; then
  ralph_iter=$(jq -r '.iteration // empty' "$ralph_state_file" 2>/dev/null)
  ralph_max=$(jq -r '.max_iterations // empty' "$ralph_state_file" 2>/dev/null)
  [ "${ralph_iter:-0}" -le 0 ] 2>/dev/null && { ralph_iter=""; ralph_max=""; }
fi
export STL_RALPH_ITER="$ralph_iter"
export STL_RALPH_MAX="$ralph_max"

# Capture format.sh output — if empty or failed, emit fallback. Either way,
# mark _emitted=1 so the EXIT trap stays silent.
_rendered=$("$SCRIPT_DIR/format.sh" 2>/dev/null || true)
if [ -n "$_rendered" ]; then
  printf '%s\n' "$_rendered"
else
  printf '%s\n' "${STL_MODEL:-Claude}"
fi
_emitted=1
