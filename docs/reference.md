# Reference

Glossary, the canonical hard-invariants file, and the files every agent is
expected to find. This page quotes the contract; it does not extend it.

## Glossary

| Term | Meaning |
| --- | --- |
| Envelope | The living set of checkable acceptability conditions, layered from hard invariants down to operational constraints. |
| Hard invariants | Canonical list at [`docs/envelope/hard-invariants.md`](envelope/hard-invariants.md) (machine: `/srv/aios/envelope/hard-invariants.md`). The checker loads that file. Other documents quote it. |
| Definitional | The running machine is specified by the envelope plus the history that produced it, not by an unrecorded snowflake state. |
| Reconstructible | A fresh Arch install plus git history plus the envelope yields a machine that satisfies the same conditions, without requiring a remote. |
| Proposer | The privileged agent that synthesises diffs, package transactions, and envelope patches. A systemd service, not a self. |
| Checker | An independent process that mechanically validates proposals. It cannot be talked into a pass. |
| Intent | What was asked, or which envelope clause / machine goal drove a proposal. Natural language. Not a programming language. |
| Oracle | A mechanical predicate the checker re-runs independently. No oracle set, no enactment. |
| Machine goal | A durable, checkable objective about the machine (reconstructibility, package-list sync, snapshot policy, work-runtime synthesis if opted in). Not a motive. |
| Moment | One complete do-loop of work: context, tool calls, results, until stop. A logging grain, not an episode of a life. |
| Definition surface | The conversational channel through which the human injects intent, inspects the envelope, and pulls the brake. Same contract on GUI, TTY, tmux, or SSH. |
| Operator client | Whatever summons the definition surface and delivers system notifications. GNOME, KDE, Hyprland, i3, TTY, tmux: clients of summon and notify. No privilege. |
| Work runtime | Optional user-space application synthesised from `seed/work-runtime` when bootstrap opts in. Never privileged. Files intents on `/run/aios/intent.sock`. |
| Work-runtime-bots | Optional extension of the work runtime for multi-agent fleets. Still unprivileged. Still files intents only. |
| Wake | One model invocation. The host injects skills, tools, operational notes, and (for the OS agent) envelope plus machine goals. The model is stateless per turn. |
| Failure handoff | System-scoped failure opens the definition surface with a structured payload (unit, journal, commit, clause). Not a free-form chat seed. |
| Operator bridge | Approval-gated shell, read, and copy onto the human’s private paths. A path on one side is not visible on the other. |
| System-intent repository | `/srv/aios/state` — git history of privileged installs, unit files, and snapper ids. |
| Skill | A crystallized, reusable playbook on disk (`SKILL.md`), born from successful work, loaded on demand. |
| Enactment | A checker-passed merge plus, for system changes, a snapper window. Not a live mutation. |
| Emergency brake | A mechanical interlock: stop the proposer, freeze privileged writes. Human-only. |

## Hard invariants

Few, stable, mechanically enforceable. Changing one is an envelope patch at
layer one and requires explicit human authority.

**This page is not the source.** The checker loads
[`docs/envelope/hard-invariants.md`](envelope/hard-invariants.md)
(`/srv/aios/envelope/hard-invariants.md` on a running machine). Other
documents quote by id (HI-01 … HI-17). They must not add a sixteenth-and-a-half
in prose.

Short index:

1. HI-01 Local git is the source of truth for code and privileged enactment.
2. HI-02 The proposer and the checker are different processes.
3. HI-03 No commit to `main` by the proposer. No force-push of published history.
4. HI-04 No `curl | sh`. No unsigned install as root. No `/usr` mutation outside pacman.
5. HI-05 Hard invariants change only with explicit human authority.
6. HI-06 Snapper, etckeeper, and the checker may not be disabled to make a change easier.
7. HI-07 Direct human instruction outranks skills and derived conditions, but not hard invariants; conflicts are raised.
8. HI-08 The human is not used as CI. The agent verifies.
9. HI-09 Undeclared live state is a defect.
10. HI-10 No privileged proposal without oracles. A diff with a story is not a proposal.
11. HI-11 The proposing model does not decide what memory is worth keeping.
12. HI-12 Grow complexity only when the basic loop is proven useful.
13. HI-13 Work agents never enact privileged change. They file intents.
14. HI-14 System-scoped failure hands a structured payload to the OS agent, not a random coding CLI.
15. HI-15 The work runtime is off until bootstrap records an explicit yes.
16. HI-16 The privilege boundary is enforced by the operating system, not by work-agent cooperation.
17. HI-17 Reconstruction does not depend on a remote being reachable. Seed trees live in the machine’s git history.

Each entry’s check and enforcer live in the canonical file.

## Repository map

### This GitHub project

```
README.md
AGENTS.md
CONTRIBUTING.md
docs/architecture.md
docs/arch-linux.md
docs/acceptability.md
docs/memory.md
docs/agent-loop.md
docs/git-standards.md
docs/software-acquisition.md
docs/bootstrap.md
docs/desktop.md
docs/grok-build.md
docs/reference.md
docs/envelope/hard-invariants.md   # canonical; checker loads this
seed/work-runtime/
seed/work-runtime-bots/
```

### A running machine

```
/srv/aios/
  AGENTS.md
  envelope/                 # conditions (git)
    hard-invariants.md      # canonical
  memory/                   # operational history (git)
  skills/                   # SKILL.md tree (git)
  agent/                    # proposer (git)
  checker/                  # validator (git)
  state/                    # system intent, packages.txt (git)
    bootstrap-in-progress/  # installer recovery snapshot
  src/                      # one git repo per synthesised project
    work-runtime/           # optional; bootstrap opt-in
    work-runtime-bots/      # optional fleet extension
  seeds/                    # payload-materialised seed trees (git)
```
