---
description: DDD layered architecture rules for projects following domain/commons/infra/repositories/graphs layer separation. Project-specific paths and enforcer hooks under the "Project-specific application" section.
---

# DDD Layer Rules (generic)

These rules apply to **any project** following DDD (Domain-Driven Design) layered architecture. For project-specific root paths and enforcer hooks, see the `## Project-specific application` section.

Source: generalized from `writer-agent-harness` project `.claude/rules/ddd-layers.md`.

---

## 1. Layer dependencies (standard)

```text
domain      → core domain logic, entities, value objects
port        → interfaces, abstract classes, protocols (ACL)
commons     → cross-cutting utilities (logging, time, event bus, URL helpers, etc.)
infra       → external dependency implementations (DB, API, files, message brokers, etc.)
repository  → repository pattern implementations (infra counterpart to port/repository interfaces)
component   → use cases, application services, graph/workflow (uppermost layer)
di          → dependency injection composition root
config      → configuration values (hot / cold config)
```

**Dependency direction (strictly enforced)** — arrow reads "importer → imported" (upper layers depend on lower layers):

```text
di → component → repository → infra → commons → port → domain
```

| Layer | Allowed imports | Forbidden imports |
|-------|-----------------|-------------------|
| `domain` | stdlib, external packages only. `port` only inside `TYPE_CHECKING` block | infra, repository, component, di, config |
| `port` | domain, stdlib, external packages | infra, repository, component |
| `commons` | port, domain, stdlib, external packages | component (no direct dependency) |
| `infra` | commons, port, domain, stdlib, external packages | component |
| `repository` | infra, commons, port, domain, stdlib, external packages | component |
| `component` | repository, infra, commons, port, domain, stdlib, external packages | `di` (only entry points may import `di` — see note below) |
| `di` | all allowed | — |
| `config` | stdlib, external packages only | domain, port, infra, repository, component |

`di` may only be imported from **entry points (e.g., `cli.py`, `gui.py`, `scripts/`)**.

---

## 2. `TYPE_CHECKING` pattern (required)

When `domain` needs to reference a `port` type, always use the `TYPE_CHECKING` guard:

```python
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from port.user_port import UserPort  # ✅ type-hint only, no runtime import

# ❌ Forbidden: domain→infra direct import, domain→port runtime import, port→component import
```

For TypeScript/Java/other languages, use the language's "type-only import" mechanism (`import type { ... }` in TS, declaration-only annotations in Java).

---

## 3. Plural/alias layer names

Projects often use plural forms. The enforcer hook must be able to map the following aliases to their canonical layer:

| Alias (plural/conventional) | Canonical layer |
|-----------------------------|-----------------|
| `models/`                   | `domain`        |
| `components/`               | `component`     |
| `repositories/`             | `repository`    |
| `ports/`                    | `port`          |
| `services/`                 | `component` (when explicitly designated by policy) |
| `entities/`                 | `domain`        |

---

## 4. DI decorators — entry point only

DI decorator patterns such as `@inject` / `Provide[Container.xxx]` from `dependency_injector` (Python) must be used **only at entry points**.

- **Forbidden**: using `@inject` or `Provide` in `graph.py`, `runner.py`, `states.py`, domain/, infra/, commons/, etc.
- **Required**: inject dependencies via `__init__` parameters. Assemble in the Container at the composition root.

```python
# ✅ Correct pattern — entry point (cli.py) only
@inject
async def handle_run_e2e(
    args: argparse.Namespace,
    e2e_graph=Provide[Container.e2e_graph],
) -> None: ...

# ❌ Forbidden — @inject used in graph.py, service.py, etc.
@inject
class MyGraph(BaseGraph):
    def __init__(self, router=Provide[Container.model_router]): ...
```

---

## 5. Project-specific application

**Canonical paths are defined by each project**. Examples:

- writer-agent-harness: `pipeline/{domain,ports,commons,infra,repositories,graphs}/`
- Sample web app: `src/{domain,application,infrastructure}/` (hexagonal variant)
- Microservices: `services/<svc>/{internal,pkg,cmd}/` (Go project layout)

**Enforcer hook implementation guide** (PostToolUse, blocking):
- Place `check_imports.py` / `check_imports.ts` in `.claude/hooks/` and register under `PostToolUse.Edit|Write` in `settings.json`
- Forbidden import found → exit code 1 (blocking) + output violation location
- Implement the allowed-import matrix by mapping this rule's table to the project's canonical paths

**The file scope to which this rule applies** is specified in each project's root CLAUDE.md or AGENTS.md. Example: `paths: ["pipeline/**/*.py"]` (writer-agent-harness), `paths: ["src/**/*.ts"]` (TS project).

---

## Hook summary (project responsibility)

| Hook | Trigger | Checks | Blocks |
|------|---------|--------|--------|
| `check_imports.*` | Edit\|Write | DDD layer dependencies, DI container → entry point only | ✅ |
| `check_inject_location.*` | Edit\|Write | `@inject` / `Provide` entry point only | ✅ |

This rule does not mandate hook implementation per project. Even without hooks, Advisor must flag violations against this rule's matrix during code review (Rule-driven review).
