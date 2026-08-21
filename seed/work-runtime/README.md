# Work runtime seed

Reconstructible application the privileged AIOS agent synthesises when
bootstrap answers **yes** to "Do you want to work with AI agents on this
system?"

This is not the OS agent. It is user-space software on a managed machine.
System mutation still goes through `/srv/aios/agent` under the envelope.

On a running box the live tree is `/srv/aios/src/work-runtime`, its own git
repository, proposed on a branch, checked, merged. This seed is the contract
the synthesis job must satisfy — not a deployment.

Read [AGENTS.md](AGENTS.md) first. Then [boundaries/invariants.md](boundaries/invariants.md)
and [boundaries/interfaces.md](boundaries/interfaces.md). Skills are loaded
on demand.

Related: [docs/desktop.md](../../docs/desktop.md), [docs/bootstrap.md](../../docs/bootstrap.md).

The live work app is the TUI in work mode (L-18): conversation, skills,
connectors, bridge, store, login. Bots, if the second bit is on, add roster
and job views. Same ids a later GUI will use. Live Grok login is device-code
on another device, with a token file the OS agent cannot share.

