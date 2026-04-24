#!/usr/bin/env bash
# Test suite for plugins/viper-plugin-cc/scripts/statusline.sh + format.sh
#
# Uses a private $HOME sandbox so real ~/.claude is never touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../scripts/statusline.sh"

FAIL=0
PASS=0

_assert_contains() {
  local label="$1" needle="$2" actual="$3"
  if printf '%s' "$actual" | grep -q -- "$needle"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "✗ $label"
    echo "  expected to contain: $needle"
    echo "  actual: $actual"
  fi
}

_assert_not_contains() {
  local label="$1" needle="$2" actual="$3"
  if ! printf '%s' "$actual" | grep -q -- "$needle"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "✗ $label"
    echo "  expected NOT to contain: $needle"
    echo "  actual: $actual"
  fi
}

# Sandbox HOME so ~/.claude/teams, ~/.pi-cc-tasks etc. don't affect real env.
HOME_SANDBOX=$(mktemp -d)
export HOME="$HOME_SANDBOX"
trap "rm -rf '$HOME_SANDBOX'" EXIT INT TERM

echo "== statusline.sh tests =="

# Test 1: empty input → default Claude line
out=$(echo '{}' | bash "$STATUSLINE")
_assert_contains "empty input renders Claude model" "Claude" "$out"

# Test 2: legacy schema (context.tokens_used) — renders ctx:N% only (no used/max)
# Note: legacy schema doesn't have .used_percentage, so pct is computed from
# current_usage, which is 0 for this fixture. Adjust fixture to include pct.
out=$(echo '{"model":{"display_name":"Opus 4.7"},"context_window":{"context_window_size":200000,"used_percentage":23}}' | bash "$STATUSLINE")
_assert_contains "legacy-ish schema ctx_pct" "ctx:" "$out"
_assert_contains "legacy-ish schema pct value" "23%" "$out"

# Test 3: modern schema (context_window + used_percentage)
out=$(echo '{"model":{"display_name":"Opus 4.7"},"context_window":{"input_tokens":100000,"total":200000,"used_percentage":50}}' | bash "$STATUSLINE")
_assert_contains "modern schema renders" "50%" "$out"

# Test 4: rate_limits rendered
out=$(echo '{"model":{"display_name":"Opus 4.7"},"rate_limits":{"five_hour":{"percent":26,"resets_in":4200},"seven_day":{"percent":84,"resets_in":158400}}}' | bash "$STATUSLINE")
_assert_contains "5h bucket rendered" "5h:26%" "$out"
_assert_contains "weekly bucket rendered" "wk:84%" "$out"

# Test 5: team tree with active pi/codex attribution
mkdir -p "$HOME/.claude/teams/viper-test" "$HOME/.pi-cc-tasks/.active" "$HOME/.codex-cc-tasks/.active"
cat > "$HOME/.claude/teams/viper-test/config.json" <<EOF
{"members":[
  {"name":"architect","agentType":"architect","model":"claude-opus-4-7"},
  {"name":"coder","agentType":"coder","model":"claude-sonnet-4-6"},
  {"name":"reviewer","agentType":"reviewer","model":"claude-sonnet-4-6"}
]}
EOF
# Alive pid: use our shell's pid
echo "{\"caller\":\"coder\",\"pid\":$$,\"started\":\"t\"}" > "$HOME/.pi-cc-tasks/.active/coder.$$.json"
echo "{\"caller\":\"reviewer\",\"pid\":$$,\"started\":\"t\"}" > "$HOME/.codex-cc-tasks/.active/reviewer.$$.json"

out=$(echo '{"model":{"display_name":"Opus 4.7"}}' | bash "$STATUSLINE")
_assert_contains "team tree architect" "architect" "$out"
_assert_contains "team tree coder" "coder" "$out"
_assert_contains "coder has Pi badge" "(Pi)" "$out"
_assert_contains "reviewer has Codex badge" "(Codex)" "$out"

# Test 6: stale pid filtered out (dead PID 999999)
rm -f "$HOME/.pi-cc-tasks/.active"/*
echo '{"caller":"coder","pid":999999,"started":"t"}' > "$HOME/.pi-cc-tasks/.active/coder.999999.json"
out=$(echo '{"model":{"display_name":"Opus 4.7"}}' | bash "$STATUSLINE")
_assert_not_contains "stale PID not shown" "(Pi)" "$out"

# Test 7: duplicate-role team (coder-1/coder-2) — agentType match highlights both
rm -rf "$HOME/.claude/teams" "$HOME/.pi-cc-tasks/.active" "$HOME/.codex-cc-tasks/.active"
mkdir -p "$HOME/.claude/teams/viper-dup" "$HOME/.pi-cc-tasks/.active"
cat > "$HOME/.claude/teams/viper-dup/config.json" <<EOF
{"members":[
  {"name":"coder-1","agentType":"coder","model":"claude-sonnet-4-6"},
  {"name":"coder-2","agentType":"coder","model":"claude-sonnet-4-6"},
  {"name":"reviewer","agentType":"reviewer","model":"claude-sonnet-4-6"}
]}
EOF
echo "{\"caller\":\"coder\",\"pid\":$$,\"started\":\"t\"}" > "$HOME/.pi-cc-tasks/.active/coder.$$.json"
out=$(echo '{}' | bash "$STATUSLINE")
pi_hits=$(printf '%s' "$out" | grep -c "(Pi)" || true)
if [ "$pi_hits" = "2" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  echo "✗ duplicate-role attribution: expected 2 (Pi) badges, got $pi_hits"
  echo "$out"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL/$((PASS+FAIL)) test(s) failed"
  exit 1
fi
echo "PASS: all $PASS tests"
