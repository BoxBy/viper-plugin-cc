---
description: Language-agnostic code quality rules — simplicity first, surgical changes, no speculative abstractions, no useless orphan code. Applied during any code Review/Edit/Write.
---

# Code Quality Rules (generic)

These rules are language- and project-agnostic. Applied automatically by any role touching code (Advisor, worker, subagent) during Review / Edit / Write — role is immaterial, the checks are the same.

---

## 1. Minimize `type: ignore` / `# noqa`

**Fix the root cause — do not suppress errors**. The only exception is structural reasons such as missing external stubs.

- Bare `# type: ignore` ❌ → `# type: ignore[specific-code]` required
- Bare `# noqa` ❌ → `# noqa: E402` (explicit code) required
- TS/JS `// @ts-ignore` → prefer `// @ts-expect-error <reason>`
- Go `//nolint` → `//nolint:linter_name // reason` (explicit)

**Key rule**: No broad suppression. Type errors and lint warnings must be scoped to the minimum range and accompanied by a reason comment.

---

## 2. Restrict import try-except (optional dependency pattern)

Do not wrap **core dependencies** in `try-except ImportError`. Missing core dependencies must fail immediately.

```python
# ❌ Forbidden — core dependency
try:
    import langchain
except ImportError:
    langchain = None

# ✅ Allowed — optional dependency (fallback is viable)
try:
    import uvloop
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass  # falls back to standard asyncio
```

---

## 3. No thin wrappers

Delete wrapper functions that only delegate to a lower-level call without adding logic. Replace with direct calls.

```python
# ❌ Forbidden
def get_user(user_id: str) -> User:
    return user_repository.find_by_id(user_id)  # thin wrapper

# ✅ Call directly at the use site
user = user_repository.find_by_id(user_id)
```

Exception: wrappers intentionally designed as an **ACL (Anti-Corruption Layer)** or **port/adapter** are "thin by architecture purpose" — keep them. When in doubt, decide by whether the name is meaningful in Ubiquitous Language terms.

---

## 4. Prefer domain methods

If a domain object exposes a method, use it. Do not re-implement domain logic as a standalone function.

```python
# ✅ Domain method
story.to_markdown()
user.can_view(document)

# ❌ Bypassing via standalone function
story_to_markdown(story)
can_user_view_document(user, document)
```

Rationale: encapsulation, testability, and alignment with Ubiquitous Language.

---

## 5. Access data through the Repository pattern

In component/graph/service layers, **direct file/DB/external API I/O is forbidden**. Use the existing Repository if one exists. If none exists, create one in port/infra first and inject it.

```python
# ❌ Forbidden
with open('users.json') as f:
    data = json.load(f)

# ✅ Via Repository
users = user_repository.list_active()
```

---

## 6. No comments by default

Follow the "Default to writing no comments" rule from CLAUDE.md.

- **No WHAT comments**: anything like `# increment counter`
- **WHY only when non-obvious**: hidden constraints, invariants, workarounds, surprising behavior
- **No task/fix references in code**: "# added for bug #123", "# used by FooController" belong in the PR description, not in the code — they rot over time

---

## 7. No backward-compat hacks

Underscore renames (`_var`), `// removed` tombstone comments, re-export shims — all are dead code. Delete them completely. If confirmed unused, clean up.

---

## Hook summary (project responsibility)

| Hook | Trigger | Checks | Blocks |
|------|---------|--------|--------|
| `check_type_ignore.*` | Edit\|Write | `# type: ignore` / `# noqa` without specific code | ⚠️ Warning (tolerable) |
| `check_import_try_except.*` | Edit\|Write | Core dependency wrapped in try-except ImportError | ✅ Blocking |

These rules apply during Advisor review regardless of whether hooks are implemented.
