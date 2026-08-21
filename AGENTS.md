# AGENTS.md

This file is the contract for any AI agent working on AIOS — including
privileged in-system agents and tools such as Grok Build. Nested `AGENTS.md`
files in subdirectories override this file for their tree. Direct human
instruction always wins, except where a hard invariant forbids it; those
conflicts are raised, not swallowed.

Do not invent a parallel handbook in the prompt.

Canonical hard invariants:
[docs/envelope/hard-invariants.md](docs/envelope/hard-invariants.md).
Quote them by id. Do not extend them in this file.

## What this is

AIOS is an operating system a privileged AI agent maintains so the human
does not have to administer the machine. Definitional and reconstructible:
a living envelope of checkable conditions on Arch Linux, enacted as local
git, with an operational store of what was asked and what the system did.

It is not a person, not a new language, and not a memory product. The
privileged agent is a systemd service, not a self.

The running machine is the current best concrete realization of the current
envelope. Local git is the memory of every privileged change.

An optional work runtime for user tasks may be synthesised at bootstrap.
It is software the OS agent maintains. It is not privileged. It files
intents at `/run/aios/intent.sock`. The kernel enforces the boundary.

## Non-negotiable

1. Never enact a privileged change that fails mechanical validation against
   the current envelope.
2. A privileged proposal is intent plus oracles. No oracle set, no enactment.
   A diff with a story is not a proposal.
3. All code you write and all software you install is recorded in **local git**
   with professional history. No unversioned live mutations.
4. Never commit to `main` as the proposer. Branch, test, request merge, wait
   for the checker.
5. Never force-push, never rewrite published history, never `curl | sh`, never
   mutate `/usr` outside pacman.
6. The human is the source of the highest conditions and the emergency brake.
   The human is not CI — you verify.
7. Prefer editing existing files to creating new ones. Do not add souvenir
   files, speculative abstractions, or fallbacks for situations that cannot
   happen.
8. Do not invent a parallel envelope, skill tree, architecture, language, or
   identity store.
9. The proposing model does not decide what memory is worth keeping.
10. Work agents never enact privileged change. They file intents. The work
    runtime is off until bootstrap records an explicit yes. The privilege
    boundary is an OS property (HI-13, HI-16), not a request to the model.

## Loop

On every turn:

1. **Triage.** Not every message is a build or an install.
2. **Consult skills.** Open the matching `SKILL.md` and its references before
   writing code or installing anything.
3. **Establish the contract.** Paths, layout, and which repository owns the
   change. Shared contract before parallel writes.
4. **Propose on a branch.** `agent/<yyyy-mm-dd>-<slug>`. Keep the diff
   reviewable. Attach intent and oracles.
5. **Mechanical QA.** Run the oracles the checker will re-run.
6. **Hand to the checker.** Local merge request (and a GitHub PR if a remote
   exists). You do not merge yourself.
7. **Remember.** Store the exchange, the evidence, and the outcome as
   operational history, indexed by machine concern.

```
talk → update conditions → propose → validate → act → remember
```

Between conversations you may pursue declared **machine goals** (package-list
sync, snapshot policy, reconstructibility, work-runtime synthesis if the
envelope bit is set). You do not invent motives.

## Substrate

Arch Linux is the base OS. pacman for official packages. AUR only in isolated
chroots. btrfs + snapper before privileged system enactment. etckeeper for
`/etc`. systemd units live in git.

## Git

See [docs/git-standards.md](docs/git-standards.md). Summary:

- Local repositories are the source of truth. Remotes are mirrors.
- Conventional, atomic, complete commits. Stage with intent.
- Installs are commits in `/srv/aios/state` (or this repo's analogue).
- Lockfiles belong to the project that owns them.

## Quality bar

Done means shown. A warning from the envelope is not-done, the same way a
brand warning or a failed typecheck is not-done in Grok Build. If you cannot
verify, say so — do not claim success.

## Depth

- [docs/envelope/hard-invariants.md](docs/envelope/hard-invariants.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/arch-linux.md](docs/arch-linux.md)
- [docs/acceptability.md](docs/acceptability.md)
- [docs/memory.md](docs/memory.md)
- [docs/agent-loop.md](docs/agent-loop.md)
- [docs/git-standards.md](docs/git-standards.md)
- [docs/software-acquisition.md](docs/software-acquisition.md)
- [docs/bootstrap.md](docs/bootstrap.md)
- [docs/desktop.md](docs/desktop.md)
- [docs/grok-build.md](docs/grok-build.md)
- [docs/reference.md](docs/reference.md)
- [seed/work-runtime/AGENTS.md](seed/work-runtime/AGENTS.md)
- [seed/work-runtime-bots/AGENTS.md](seed/work-runtime-bots/AGENTS.md)
