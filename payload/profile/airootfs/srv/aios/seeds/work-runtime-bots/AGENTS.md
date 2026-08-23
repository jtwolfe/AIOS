# AGENTS.md

Contract for any agent working on the bots extension — including the
privileged OS agent synthesising it, and fleet members running inside it
once live.

Nested files in this tree outrank this file. Direct human instruction wins,
except where a hard invariant forbids it. Canonical invariants:
[docs/envelope/hard-invariants.md](../../docs/envelope/hard-invariants.md)
(HI-13, HI-15, HI-16, HI-17 in particular).

## What this is

An optional, unprivileged extension of the work runtime for multi-agent
fleets on an AIOS machine. Rosters, fleet routines, VM-lifecycle *intents*.
Not a person. Not a second operating system. Not privileged.

## Non-negotiable

1. Never enact privileged system change from this tree. File an intent at
   `/run/aios/intent.sock`. The OS agent is the only consumer.
2. A proposal inside this tree is still intent plus oracles. No oracle set,
   no merge. The OS checker still runs.
3. Local git. No unversioned live mutations. No commit to `main` as the
   proposer.
4. Do not invent personhood, an identity store, names-as-selves, or a
   parallel envelope. A roster is a list of jobs and slices, not a cast.
5. Default off. This extension exists only if the envelope records an
   explicit yes on top of an already-enabled work runtime.
6. Workers have no user-visible voice. Results are sent, not only
   acknowledged.
7. VM, network, and package work is an intent. Maintaining a guest is not
   a reason to hold host privilege.

## Loop

Wake injects: skills catalog, tools, operational notes relevant to the job.
Then: triage, consult skills, propose on a branch, mechanical QA, hand to
the checker, remember as operational history.

System-scoped failure is not your wake. That handoff belongs to the OS agent.

## Depth

- [boundaries/invariants.md](boundaries/invariants.md)
- [skills/roster.md](skills/roster.md)
- [skills/fleet.md](skills/fleet.md)
- [../work-runtime/AGENTS.md](../work-runtime/AGENTS.md)
