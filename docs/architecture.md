# Architecture

The running machine is the current best concrete realization of the current
rule set, maintained by the AI so the human does not have to administer it.
Architecture is a set of durable splits, not a pile of daemons and not a
personality.

## Definitional system

AIOS is **definitional**: it is specified by an envelope of checkable
conditions plus the history that produced them. It is **reconstructible**: a
fresh Arch install plus the local git record plus the current envelope should
yield a machine that satisfies the same conditions.

That posture forbids a hidden snowflake state. Configuration lives in git.
Packages are declared. Synthesised programs are repositories. Privileged
actions leave a commit. The live system is a checkout, not an original. Seed
trees used for synthesis live in that git history too — reconstruction must
not depend on GitHub being reachable (HI-17).

**Rule.** Do not invent a parallel architecture. If a new daemon, file, or
control path is required, it must be named in the envelope and recorded in
the system-intent repository before it is relied upon.

## Two terms

Lock these. Other wording in older notes is an alias, not a second concept.

- **Definition surface** — the conversational channel. Natural language.
  Same contract on a GUI window, a TTY, a tmux pane, or SSH.
- **Operator client** — whatever summons the definition surface and delivers
  system notifications. GNOME, KDE, Hyprland, i3, a pure TTY, tmux: all
  valid clients of the same two contracts (summon, notify).

Hard invariants live in one file the checker loads:
[`docs/envelope/hard-invariants.md`](envelope/hard-invariants.md). On a
running machine: `/srv/aios/envelope/hard-invariants.md`. Other documents
quote it by id. They do not extend it.

## Two surfaces

The human never administers the machine by scattering commands across
terminals as the primary path. There are two surfaces, and they are not the
same process.

- **Definition surface** — how the human injects intent, refines conditions,
  requests capability, inspects the envelope, and pulls the emergency brake.
  Natural language. No new language runtime. v1 transport is the TUI
  (named views in [docs/desktop.md](desktop.md)). A later GUI uses the
  same view ids. TTY, tmux, or SSH host that TUI — same contract.
- **Background privileged agent** — an always-on worker with deep
  observation and enactment rights. It proposes. It does not validate itself.
  It is a systemd service, not a presence.

The definition surface is the human’s entire view, in the same sense that
a Grok Build preview is the user’s entire view of a sandbox. The agent does
the work; the human sets conditions and judges outcomes, and is not used as a
substitute for mechanical QA.

## Operator client and work

Those two surfaces are the OS. An operator client of them is present from
bootstrap: a way to summon OS intents and to receive system failure already
briefed. See [docs/desktop.md](desktop.md). The client is whatever the
envelope installed. AIOS does not require a particular DE or WM. Until a
graphical client exists, the definition surface is a TTY.

People also do user work on the machine. That is optional. Bootstrap asks
whether to synthesise a work runtime. If yes, it lives under
`/srv/aios/src/work-runtime` as an ordinary synthesised application: skills,
connectors, workers, an approval-gated bridge to private human paths. It is
not privileged. It files intents at `/run/aios/intent.sock` when it needs
packages, units, or policy. If the envelope bit is set, completing that
synthesis is a machine goal — bootstrap is not finished until the seed is a
local git repository under `/srv/aios/src`.

Do not grow a personality, a roster of selves, or a second cloud computer so
the OS can “have teammates.” Work agents are user-space software on a managed
box. Multi-agent fleets, when needed, are an optional extension
([`seed/work-runtime-bots`](../seed/work-runtime-bots/README.md)), still
under the same privilege boundary.

## Privilege boundary

“Work agents file intents only” is not a request to the model. The operating
system enforces it (HI-13, HI-16).

- Only the privileged agent uid can write the envelope, `/srv/aios/state`,
  unit files, and the package list. Only that uid may run pacman as root or
  talk to the checker merge path.
- Work-runtime processes run in `aios-work.slice`: `NoNewPrivileges`,
  `ProtectSystem=strict`, a capability bounding set that cannot escalate, and
  a filesystem that cannot see privileged trees.
- To request a privileged change, a work agent writes a structured intent to
  `/run/aios/intent.sock`. The OS agent is the only consumer. It turns
  accepted intents into ordinary proposals (branch, oracles, checker). A work
  agent that calls `pacman` or `systemctl` is denied by the kernel, not
  scolded after the fact.

If a work process can enact, the machine is misconfigured — that is a
checker failure, not a prompt failure.

## Proposer and checker

Validation is separated from proposal. The proposing intelligence and the
checking mechanism share the operational store but are not the same process.
This is the architectural expression of “prefer mechanical, independently
checkable validation over asking the model again.”

- The **proposer** may be creative, wide-ranging, and allowed to fail. Its
  outputs are diffs, package transactions, unit files, and envelope patches —
  each carrying intent plus oracles.
- The **checker** is narrow and boring. It runs the oracles: tests,
  typecheckers, policy scripts, pacman transaction audits, envelope
  predicates including the canonical hard-invariants file. It cannot be
  talked into a pass.

Ownership of surfaces does not overlap. The proposer does not merge its own
branches. The checker does not synthesise features. Parallel work by tools
or subagents follows the same rule: shared contract first, non-overlapping
paths, then integrate.

## Machine goals

A small, durable set of objectives about the *machine* sits next to the
envelope as operational constraints the background agent may pursue without
a chat turn: keep the explicit package list in sync, snapper before
privileged writes, never break reconstructibility, honour update windows,
and — if the bootstrap bit is set — keep the work runtime synthesised from
seed.

These are not motives. They are not a self. They do not live in a separate
identity store. If a goal cannot be checked, it is not a machine goal — it
is a wish, and wishes belong on the definition surface until they compile
into predicates.

Natural language on the definition surface, mechanical predicates in the
checker, git as the record. That is the stack. Do not add a language runtime
so the OS can “speak intent.” The closed loop (intent → oracles → verify →
emit) is the transfer; a new language is not.

## On-disk layout

Default layout on the Arch substrate. Each tree is its own git repository
unless noted. Nested `AGENTS.md` files apply to their subtree. The canonical
hard-invariants file is the first object in `envelope/`.

```
/srv/aios/
  AGENTS.md              # machine-wide agent contract
  envelope/              # current conditions (git)
    hard-invariants.md   # canonical; checker loads this
  memory/                # operational history (git)
  skills/                # crystallized SKILL.md files (git)
  agent/                 # privileged proposer (git)
  checker/               # independent validator (git)
  state/                 # system-intent log: installs, units, snapshots (git)
  src/                   # synthesised projects; each a git repo
    work-runtime/        # optional; only if bootstrap opted in
    work-runtime-bots/   # optional extension; multi-agent fleets
  seeds/                 # materialised copies of project seeds (git)
  etc-mirror/            # etckeeper remote of /etc (git)
```

Working copies the human touches live under `~/src`. The privileged agent
works in `/srv/aios`. Remotes (GitHub included) are backups and
collaboration, not the source of truth. The local repositories are. The
trusted payload copies seed trees into `/srv/aios/seeds` so a later
reconstruct does not need the network.
