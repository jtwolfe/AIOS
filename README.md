# AIOS

**AI Operating System**

A definitional, reconstructible system in which a privileged AI agent continuously shapes the machine under a living set of checkable acceptability conditions, while maintaining a natural, unbounded store of interactions with both the human and the system itself.

## Core Idea

An operating system that *is* the AI needs two things that normally conflict:

1. **Room** — real freedom for the AI to reshape what the machine is, how resources are used, what abstractions exist, and how the system presents itself.
2. **Control** — a reliable way to keep the system corrigible and to protect the human’s interests.

AIOS resolves this by making **checkable acceptability conditions** the primary control surface. The AI is free to propose and enact almost any change (new tools, interfaces, layouts, even limited self-modification) as long as the resulting state continues to satisfy the current conditions. Those conditions are themselves evolvable, but only under stricter meta-rules and with human authority over the highest layer.

The system is definitional: the running machine is the current best concrete realization of the current rule set, maintained by the AI.

## Key Elements

### Bootstrap
A minimal trusted payload (USB or network) verifies against the target machine and drops the user into a conversational interface that *is* the installer. High-level intent expressed in natural language is turned into the initial set of acceptability conditions. The AI then constructs the concrete system inside that envelope.

### Two Surfaces
- **Conversational definition surface** — how the human injects intent, refines conditions, requests new capability, and inspects the current envelope.
- **Background privileged agent** — a long-running service with deep observation and enactment rights. Every privileged action must pass mechanical validation against the current conditions before execution.

### Rules Engine
Acceptability conditions are layered:
- Hard invariants (few, stable, mechanically enforceable)
- Derived conditions (from human statements)
- Operational constraints (generated during work)
- Meta-rules (governing how the envelope itself may change)

Validation is separated from proposal. The proposing intelligence and the checking mechanism share memory but are not the same process.

### Interaction Memory
A natural, unbounded store of interactions with both the user and the system. Design principles:
- Verbatim primary storage of significant exchanges and system actions
- Layered access (cheap always-on core + scoped retrieval + deep search)
- Temporal validity so decisions can be superseded without erasure
- Skills as crystallized, reusable patterns born from successful interaction history

The history of the relationship and the history of the machine are the same store viewed from two angles.

### Software Acquisition
There is no classical package manager as the primary path. New programs and capabilities are materialised by the AI itself: the agent synthesises, validates against current conditions, and installs. The install mechanism *is* the AI.

## Design Posture

- Start from a thin classical substrate (Linux + modern isolation primitives). Do not rewrite the kernel on day one.
- Prefer mechanical / independently checkable validation over “ask the model again.”
- Keep the human as the ultimate source of the highest conditions and the emergency brake.
- Grow complexity only when the basic loop (talk → update conditions → propose → validate → act → remember) is proven useful.
- Treat the projects and techniques that inspired this thinking (intent languages, memory systems, agent skills, reconstructible systems) as reference points, not as binding architecture.

## Status

Early conceptual capture. This repository records the high-level intent. Concrete implementation, MVP scoping, and experiments will follow.

## License

To be determined.
