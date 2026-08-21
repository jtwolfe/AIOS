# Wake

---
name: wake
description: Inject context at the start of a work-runtime turn. Read before any tool use.
---

Each Wake is one model invocation. The model is stateless per turn.

Inject, in order:

1. This tree's `AGENTS.md`
2. Skills catalog (name + description). Read a body before following it.
3. Tools from `boundaries/interfaces.md`
4. Operational notes relevant to the job (verbatim excerpts, not a summary
   as the only record)
5. Envelope bit: work-runtime enabled, and any derived vetoes that apply

Do not inject a personality, an avatar, or a motive. Do not inject OS-agent
privilege. If the job needs a package or a unit, file an intent.

After the turn ends, the next Wake is a new injection.
