# Architecture

The running machine is the current best concrete realization of the current
rule set, maintained by the AI. Architecture is a set of durable splits, not
a pile of daemons.

## Definitional system

AIOS is **definitional**: it is specified by an envelope of checkable
conditions plus the history that produced them. It is **reconstructible**: a
fresh Arch install plus the local git record plus the current envelope should
yield a machine that satisfies the same conditions.

That posture forbids a hidden snowflake state. Configuration lives in git.
Packages are declared. Synthesised programs are repositories. Privileged
actions leave a commit. The live system is a checkout, not an original.

**Rule.** Do not invent a parallel architecture. If a new daemon, file, or
control path is required, it must be named in the envelope and recorded in
the system-intent repository before it is relied upon.

## Two surfaces

The human never administers the machine by scattering commands across
terminals as the primary path. There are two surfaces, and they are not the
same process.

- **Conversational definition surface** — how the human injects intent,
  refines conditions, requests capability, inspects the envelope, and pulls
  the emergency brake.
- **Background privileged agent** — a long-running service with deep
  observation and enactment rights. It proposes. It does not validate itself.

The conversational surface is the human’s entire view, in the same sense that
a Grok Build preview is the user’s entire view of a sandbox. The agent does
the work; the human sets conditions and judges outcomes, and is not used as a
substitute for mechanical QA.

## Proposer and checker

Validation is separated from proposal. The proposing intelligence and the
checking mechanism share memory but are not the same process. This is the
architectural expression of “prefer mechanical, independently checkable
validation over asking the model again.”

- The **proposer** may be creative, wide-ranging, and allowed to fail. Its
  outputs are diffs, package transactions, unit files, and envelope patches.
- The **checker** is narrow and boring. It runs tests, typecheckers, policy
  scripts, pacman transaction audits, and envelope predicates. It cannot be
  talked into a pass.

Ownership of surfaces does not overlap. The proposer does not merge its own
branches. The checker does not synthesise features. Parallel work by tools
or subagents follows the same rule: shared contract first, non-overlapping
paths, then integrate.

## On-disk layout

Default layout on the Arch substrate. Each tree is its own git repository
unless noted. Nested `AGENTS.md` files apply to their subtree.

```
/srv/aios/
  AGENTS.md              # machine-wide agent contract
  envelope/              # current conditions (git)
  memory/                # interaction store (git)
  skills/                # crystallized SKILL.md files (git)
  agent/                 # privileged proposer (git)
  checker/               # independent validator (git)
  state/                 # system-intent log: installs, units, snapshots (git)
  src/                   # synthesised projects; each a git repo
  etc-mirror/            # etckeeper remote of /etc (git)
```

Working copies the human touches live under `~/src`. The privileged agent
works in `/srv/aios`. Remotes (GitHub included) are backups and
collaboration, not the source of truth. The local repositories are.
