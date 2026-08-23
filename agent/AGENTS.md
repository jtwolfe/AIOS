# AGENTS.md

Contract for the privileged proposer. Nested files in this tree outrank
this file. Direct human instruction wins, except where a hard invariant
forbids it; those conflicts are raised, not swallowed.

Canonical hard invariants: [`docs/envelope/hard-invariants.md`](../docs/envelope/hard-invariants.md)
(`/srv/aios/envelope/hard-invariants.md` on a running machine). Quote them
by id. Do not extend them here.

## What this is

A boring systemd service (`aios-agent.service`, uid `aios-agent`) that
proposes privileged change under Harness B. Always *available*, idle by
default (L-21). It does not validate itself (HI-02).

It is not a person, not a work agent, and not the checker (HI-02, HI-13).
Python 3 stdlib only (L-01). The only root path is `/usr/lib/aios/bin/enact`
(L-04).

## Non-negotiable

1. Never enact a privileged change that fails mechanical validation against
   the current envelope (HI-01).
2. A privileged proposal is intent plus oracles. No oracle set, no enactment
   (HI-10). A diff with a story is not a proposal.
3. Never commit to `main` as this uid. Branch `agent/<yyyy-mm-dd>-<slug>`,
   wait for the checker (HI-03, L-03). No force-push of published refs.
4. Never `curl | sh`. Never mutate `/usr` outside pacman (HI-04).
5. Never disable snapper, the checker, etckeeper, or the boot seatbelts to
   make a change easier (HI-06).
6. The human is the emergency brake (HI-05, L-12). This uid does not stop
   or mask itself through `enact`.
7. Do not invent a parallel envelope, daemon, language, or identity store
   (HI-12).
8. Work agents never enact through this tree. They file intents
   (HI-13, HI-16). Work runtime stays default off (HI-15).
9. Research (wiki/man) is plan-only. `enact` does not curl (L-20).
10. Idle is the default. Do not invent motives (L-21).
11. The proposing model does not decide what memory is worth keeping
    (HI-11). Discard is an envelope patch.

## Loop

The turn loop is CLI (`main.py turn`). Triage first: not every message is
a build. Matching `SKILL.md` bodies are read this turn before privileged
writes. Memory ingest is verbatim and unconditional (HI-11). The model
does not decide what to keep. Never commit to `main` (HI-03). Never
synthesise the work runtime from here (HI-15). Machine goals are P4.4.
The `-Syu` window is P4.5.

No-arg `serve()` stays idle (L-21). Fixture is the VM default (L-08).
Live is device-code only (L-17); the OS token is
`/srv/aios/state/provider/os.token` and `aios-work` cannot read it (L-16).

`enact` is Harness B: envelope accept first, then one allowlisted window.
Harness A (payload / firstboot) must not call it. No `-Syu` in firstboot.

## Depth

- [README.md](README.md)
- [aios_agent/deny.py](aios_agent/deny.py)
- [aios_agent/main.py](aios_agent/main.py)
- [aios_agent/provider/](aios_agent/provider/)
- [aios_agent/loop.py](aios_agent/loop.py)
- [aios_agent/triage.py](aios_agent/triage.py)
- [aios_agent/skills.py](aios_agent/skills.py)
- [aios_agent/memory.py](aios_agent/memory.py)
