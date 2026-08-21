# AIOS

**AI Operating System**

An operating system a privileged AI agent maintains so the human does not
have to administer the machine. Definitional and reconstructible: a living
envelope of checkable acceptability conditions, enacted as local git, with
an operational store of what was asked and what the system did.

The substrate is **Arch Linux**. Every line of code the agent writes, and every
package it installs, is managed **locally in git** to professional development
standards. Remotes (this GitHub repository included) are mirrors and
collaboration — the local history is the source of truth.

AIOS is not a person, not a new language, and not a memory product.

## Core Idea

An operating system managed by an AI needs two things that normally conflict:

1. **Room** — real freedom for the AI to reshape what the machine is, how
   resources are used, what abstractions exist, and how the system presents
   itself.
2. **Control** — a reliable way to keep the system corrigible and to protect
   the human’s interests.

AIOS resolves this by making **checkable acceptability conditions** the
primary control surface. The AI is free to propose and enact almost any
change (new tools, interfaces, layouts, even limited self-modification) as
long as the resulting state continues to satisfy the current conditions.
Those conditions are themselves evolvable, but only under stricter meta-rules
and with human authority over the highest layer.

A proposal is **intent plus oracles**. Enactment is never an unrecorded live
mutation. Passed work lands as a reviewable git history on the machine: a
branch, tests the checker re-runs independently, a merge. The running machine
is the current best concrete realization of the current rule set.

## What this is not

| Not | Because |
| --- | --- |
| A person, presence, or psyche | The privileged agent is a systemd service that administers the machine. Privilege is not a personality. |
| A new programming language | The definition surface is natural language. Control is mechanical predicates. Record is git. |
| A memory product | History exists so the agent can keep *this* box reconstructible over time — not so it can reminisce. |
| A teammate product by default | Work agents are optional software, opted into at bootstrap. They file intents. They are not a second self. |

Inspired techniques (intent loops, memory systems, agent skills,
reconstructible systems, Grok Build, Grok Bot-class runtimes) are **reference
points, not a binding architecture**. If wording starts sounding like a
companion, a language, or a memory app, cut it.

## The basic loop

```
talk → update conditions → propose → validate → act → remember
```

Propose means *intent + oracles*. Validate means the checker re-runs those
oracles without asking the model again. Grow complexity only when this loop
is proven useful.

## Specification

| Document | Subject |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Contract for any AI working on this project or on a running machine |
| [docs/architecture.md](docs/architecture.md) | Two surfaces, desktop client, proposer/checker, machine goals, layout |
| [docs/desktop.md](docs/desktop.md) | Shell as client, failure handoff, optional work runtime |
| [docs/arch-linux.md](docs/arch-linux.md) | Why Arch, pacman, btrfs/snapper, reconstructibility |
| [docs/acceptability.md](docs/acceptability.md) | Envelope layers, mechanical checks, human authority |
| [docs/memory.md](docs/memory.md) | Operational history, findability by concern, skills, temporal validity |
| [docs/agent-loop.md](docs/agent-loop.md) | Privileged agent execution loop; intent and oracles |
| [docs/git-standards.md](docs/git-standards.md) | Local git as the enactment law |
| [docs/software-acquisition.md](docs/software-acquisition.md) | pacman, lockfiles, synthesis — the AI is the installer |
| [docs/bootstrap.md](docs/bootstrap.md) | Trusted payload and conversational installer |
| [docs/grok-build.md](docs/grok-build.md) | Mapping the Grok Build sandbox contract onto a whole OS |
| [docs/reference.md](docs/reference.md) | Glossary, hard invariants, repository map |
| [seed/work-runtime](seed/work-runtime/README.md) | Reconstructible application the OS agent synthesises if opted in |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Human and agent contribution path |

## Key Elements

### Bootstrap

A minimal trusted payload (USB or network, `archiso`-shaped) verifies against
the target machine and drops the user into a conversational interface that
*is* the installer. Two first-class questions: *what is this machine for?*,
and *do you want to work with AI agents on this system?*. High-level intent
becomes the first envelope. Skipping the work-runtime question is not a yes.

### Two Surfaces

- **Conversational definition surface** — how the human injects intent,
  refines conditions, requests new capability, and inspects the current
  envelope. Natural language. No new language runtime.
- **Background privileged agent** — an always-on worker with deep
  observation and enactment rights. Every privileged action must pass
  mechanical validation against the current conditions before execution. It
  is a systemd service, not a presence.

The desktop is a *client* of those surfaces: launcher intents and failure
toasts that open the definition surface already briefed. An optional work
runtime, if synthesised from seed, is user-space software on the managed box.

### Rules Engine

Acceptability conditions are layered:

- Hard invariants (few, stable, mechanically enforceable)
- Derived conditions (from human statements)
- Operational constraints (generated during work, including machine goals)
- Meta-rules (governing how the envelope itself may change)

Validation is separated from proposal. The proposing intelligence and the
checking mechanism share the operational store but are not the same process.

### Operational history

A natural, unbounded store of interactions with both the user and the system.

- Verbatim primary storage of significant exchanges and system actions
- The proposing model does not decide what is worth keeping
- Indexed by machine concern (packages, units, network, envelope, projects)
- Layered access (cheap always-on core + scoped retrieval + deep search)
- Temporal validity so decisions can be superseded without erasure
- Skills as crystallized playbooks born from successful work

The history of what the human asked and the history of what the machine did
are the same store viewed from two angles. That is administration, not
companionship.

### Software Acquisition

There is no classical package manager as the primary path. New programs and
capabilities are materialised by the AI itself: the agent synthesises,
validates against current conditions, and installs. The install mechanism
*is* the AI. Official Arch packages, project lockfiles, and synthesised
programs are three paths; all of them become git history. Synthesised code is
emitted only when its oracles pass. The work runtime, when opted in, is one
such synthesis job.

## Design Posture

- Start from a thin classical substrate (Arch Linux + modern isolation
  primitives). Do not rewrite the kernel on day one.
- Prefer mechanical / independently checkable validation over “ask the model
  again.” No proposal without oracles.
- Keep the human as the ultimate source of the highest conditions and the
  emergency brake.
- Grow complexity only when the basic loop is proven useful.
- Treat the projects and techniques that inspired this thinking as reference
  points, not as binding architecture. Transfer the closed loop (intent →
  oracles → verify → emit), not a language; transfer operational memory, not a
  mind; transfer an always-on worker and machine goals, not a self; transfer
  wake, skills, connectors, workers, and an approval-gated bridge, not a
  teammate product.
- Prefer editing existing files to creating new ones. Do not invent a
  parallel set of rules.

## Status

Early conceptual capture. This repository records the high-level intent.
Concrete implementation, MVP scoping, and experiments will follow — through
the loop, not around it.

## License

To be determined.
