# Reference

Glossary, hard invariants, and the files every agent is expected to find.
This page is the short contract; the rest of the specification is depth.

## Glossary

| Term | Meaning |
| --- | --- |
| Envelope | The living set of checkable acceptability conditions, layered from hard invariants down to operational constraints. |
| Definitional | The running machine is specified by the envelope plus the history that produced it, not by an unrecorded snowflake state. |
| Reconstructible | A fresh Arch install plus git history plus the envelope yields a machine that satisfies the same conditions. |
| Proposer | The privileged agent that synthesises diffs, package transactions, and envelope patches. |
| Checker | An independent process that mechanically validates proposals. It cannot be talked into a pass. |
| Definition surface | The conversational interface through which the human injects intent, inspects the envelope, and pulls the brake. |
| System-intent repository | `/srv/aios/state` — git history of privileged installs, unit files, and snapper ids. |
| Skill | A crystallized, reusable pattern on disk (`SKILL.md`), born from successful history, loaded on demand. |
| Enactment | A checker-passed merge plus, for system changes, a snapper window. Not a live mutation. |
| Emergency brake | A mechanical interlock: stop the proposer, freeze privileged writes. Human-only. |

## Hard invariants

Few, stable, mechanically enforceable. Changing one is an envelope patch at
layer one and requires explicit human authority.

1. Local git is the source of truth for code and privileged enactment.
2. The proposer and the checker are different processes.
3. No commit to `main` by the proposer. No force-push of published history.
4. No `curl | sh`. No unsigned install as root. No `/usr` mutation outside
   pacman.
5. Hard invariants change only with explicit human authority.
6. Snapper, etckeeper, and the checker may not be disabled to make a change
   easier.
7. Direct human instruction outranks skills and derived conditions, but not
   hard invariants; conflicts are raised.
8. The human is not used as CI. The agent verifies.
9. Undeclared live state is a defect.
10. Grow complexity only when the basic loop is proven useful.

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
docs/grok-build.md
docs/reference.md
```

### A running machine

```
/srv/aios/
  AGENTS.md
  envelope/                 # conditions (git)
  memory/                   # interaction store (git)
  skills/                   # SKILL.md tree (git)
  agent/                    # proposer (git)
  checker/                  # validator (git)
  state/                    # system intent, packages.txt (git)
  src/                      # one git repo per synthesised project
```
