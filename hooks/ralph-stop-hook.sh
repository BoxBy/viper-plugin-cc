#!/usr/bin/env bash
# ralph-stop-hook.sh — Stop hook for Ralph loop pattern.
#
# Fires after every Claude response. Checks ~/.claude/ralph-state.json:
#   - Not active or no state file → allow normal exit
#   - Active + iteration < max → block exit, inject continuation reason
#   - Active + iteration >= max or terminal status → allow exit, cleanup state
#
# Windows compatible: avoids non-POSIX commands, uses bash builtins.

exec 2>/dev/null
trap ':' ERR

STATE_FILE="$HOME/.claude/ralph-state.json"

# No state file → not in a Ralph loop
[ -f "$STATE_FILE" ] || exit 0

# Read state — use python as cross-platform JSON parser (available on all
# Claude Code installations since Claude Code itself requires Node.js/python).
read_state() {
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        s = json.load(f)
    print(json.dumps({
        'active': s.get('active', False),
        'iteration': s.get('iteration', 0),
        'max_iterations': s.get('max_iterations', 50),
        'status': s.get('status', 'unknown'),
        'task_dir': s.get('task_dir', ''),
        'worker_agent': s.get('worker_agent', ''),
        'task_description': s.get('task_description', ''),
        'mode': s.get('mode', 'A'),
        'codex_reject_streak': s.get('codex_reject_streak', 0),
    }))
except: sys.exit(1)
" "$STATE_FILE" 2>/dev/null
}

STATE_JSON=$(read_state)
[ -z "$STATE_JSON" ] && exit 0

# Parse fields
active=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('active',False))" 2>/dev/null)
[ "$active" != "True" ] && exit 0

iteration=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('iteration',0))" 2>/dev/null)
max_iter=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('max_iterations',50))" 2>/dev/null)
status=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null)
task_dir=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task_dir',''))" 2>/dev/null)
task_desc=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin).get('task_description',''); print(d[:200])" 2>/dev/null)
streak=$(printf '%s' "$STATE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('codex_reject_streak',0))" 2>/dev/null)

# Terminal statuses → allow exit
case "$status" in
  completed|blocked|partial)
    # Cleanup: mark inactive
    python3 -c "
import json
with open('$STATE_FILE') as f: s = json.load(f)
s['active'] = False
with open('$STATE_FILE', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null
    exit 0
    ;;
esac

# Circuit breaker: codex reject streak ≥ 3
if [ "$streak" -ge 3 ] 2>/dev/null; then
  python3 -c "
import json
with open('$STATE_FILE') as f: s = json.load(f)
s['active'] = False
s['status'] = 'blocked'
with open('$STATE_FILE', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null
  exit 0
fi

# Max iterations reached
next_iter=$((iteration + 1))
if [ "$next_iter" -gt "$max_iter" ] 2>/dev/null; then
  python3 -c "
import json
with open('$STATE_FILE') as f: s = json.load(f)
s['active'] = False
s['status'] = 'partial'
with open('$STATE_FILE', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null
  exit 0
fi

# Increment iteration and block exit to continue loop
python3 -c "
import json
with open('$STATE_FILE') as f: s = json.load(f)
s['iteration'] = $next_iter
with open('$STATE_FILE', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null

# Build continuation reason
reason="Ralph loop iteration ${next_iter}/${max_iter}. Status: ${status}."
[ -n "$task_desc" ] && reason="${reason} Task: ${task_desc}."
reason="${reason} Read the ralph state file and continue with the next iteration. If status is completed/blocked/partial, declare done immediately."

printf '%s\n' "{\"decision\":\"block\",\"reason\":\"${reason}\"}"
