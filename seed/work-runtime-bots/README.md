# Work-runtime-bots seed

Optional extension of the work runtime for multi-agent fleets: home-server
workers that maintain VMs on the AIOS host, long-running rosters, inter-agent
handoff without a human in every turn.

This is not the OS agent. It is not a roster of people. It is user-space
software on a managed machine. System mutation still goes through
`/srv/aios/agent` under the envelope. Fleet members file intents. They do
not pacman, they do not write units, they do not touch the envelope.

Opt-in is an envelope clause on top of an already-enabled work runtime.
Default off. Core `seed/work-runtime` stays lean; this tree is the extra
contract.

On a running box the live tree is `/srv/aios/src/work-runtime-bots`, its own
git repository, proposed on a branch, checked, merged. This seed is the
contract the synthesis job must satisfy — not a deployment.

The trusted payload materialises this tree into `/srv/aios/seeds` so
synthesis does not need GitHub (HI-17).

Read [AGENTS.md](AGENTS.md) first. Then
[boundaries/invariants.md](boundaries/invariants.md). Skills are loaded on
demand.

Related: [docs/desktop.md](../../docs/desktop.md),
[seed/work-runtime](../work-runtime/README.md).
