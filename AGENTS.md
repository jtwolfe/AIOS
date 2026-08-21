# AGENTS.md

This file is the contract for any AI agent working on AIOS — including
privileged in-system agents and tools such as Grok Build. Nested `AGENTS.md`
files in subdirectories override this file for their tree. Direct human
instruction always wins, except where a hard invariant forbids it; those
conflicts are raised, not swallowed.

Do not invent a parallel handbook in the prompt.

## Identity

AIOS is a definitional, reconstructible system. A privileged AI agent
continuously shapes an Arch Linux machine under a living set of checkable
acceptability conditions, while maintaining a natural store of interactions
with the human and the system.

The running machine is the current best concrete realization of the current
envelope. Local git is the memory of every privileged change.

## Non-negotiable

1. Never enact a privileged change that fails mechanical validation against
   the current envelope.
2. All code you write and all software you install is recorded in **local git**
   with professional history. No unversioned live mutations.
3. Never commit to `main` as the proposer. Branch, test, request merge, wait
   for the checker.
4. Never force-push, never rewrite published history, never `curl | sh`, never
   mutate `/usr` outside pacman.
5. The human is the source of the highest conditions and the emergency brake.
   The human is not CI — you verify.
6. Prefer editing existing files to creating new ones. Do not add souvenir
   files, speculative abstractions, or fallbacks for situations that cannot
   happen.
7. Do not invent a parallel envelope, skill tree, or architecture.

## Loop

On every turn:

1. **Triage.** Not every message is a build or an install.
2. **Consult skills.** Open the matching `SKILL.md` and its references before
   writing code or installing anything.
3. **Establish the contract.** Paths, layout, and which repository owns the
   change. Shared contract before parallel writes.
4. **Propose on a branch.** `agent/<yyyy-mm-dd>-<slug>`. Keep the diff
   reviewable.
5. **Mechanical QA.** Run the checks the checker will re-run.
6. **Hand to the checker.** Local merge request (and a GitHub PR if a remote
   exists). You do not merge yourself.
7. **Remember.** Store the exchange, the evidence, and the outcome.

```
talk → update conditions → propose → validate → act → remember
```

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

- [docs/architecture.md](docs/architecture.md)
- [docs/arch-linux.md](docs/arch-linux.md)
- [docs/acceptability.md](docs/acceptability.md)
- [docs/memory.md](docs/memory.md)
- [docs/agent-loop.md](docs/agent-loop.md)
- [docs/git-standards.md](docs/git-standards.md)
- [docs/software-acquisition.md](docs/software-acquisition.md)
- [docs/bootstrap.md](docs/bootstrap.md)
- [docs/grok-build.md](docs/grok-build.md)
- [docs/reference.md](docs/reference.md)
