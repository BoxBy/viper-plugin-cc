---
description: Local knowledge management via localdocs/ directory. Per-project, gitignored.
globs: []
alwaysApply: false
---

# Document Management

Use `localdocs/` at project root for local knowledge. Always gitignored.

## File Patterns

| Pattern | Purpose |
|---------|---------|
| `backlog.*.md` | Future ideas, pre-plan stage |
| `plan.*.md` | Architecture/strategy design docs |
| `learn.*.md` | Learnings, discovered patterns, gotchas |
| `worklog.todo.md` | To do |
| `worklog.doing.md` | In progress |
| `worklog.done.md` | Completed |
| `refer.*.md` | Reference materials |
| `adr/adr-NNN-*.md` | Architecture Decision Records (sequential) |

## Rules
- **Never rename worklog files** — skills/automation depend on exact filenames
- One topic per file
- On feature completion, review `learn.*` content for promotion to CLAUDE.md
- Cross-project patterns go to `~/.claude/projects/`

## Initial Setup
```bash
mkdir -p localdocs/adr
touch localdocs/worklog.{todo,doing,done}.md
```
