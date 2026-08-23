# AGENTS.md

Contract for the independent checker. Nested files in this tree outrank
this file. Direct human instruction wins, except where a hard invariant
forbids it; those conflicts are raised, not swallowed.

Canonical hard invariants: [`docs/envelope/hard-invariants.md`](../docs/envelope/hard-invariants.md)
(`/srv/aios/envelope/hard-invariants.md` on a running machine). Quote them
by id. Do not extend them here.

## What this is

A boring systemd service (`aios-checker.service`, uid `aios-checker`) that
re-runs oracles without asking a model. It cannot be talked into a pass.

It is not a proposer, not a model client, and not a work agent (HI-02,
HI-13). Python 3 stdlib only (L-01). Policy oracles are POSIX `sh` and
land beside this driver.

## Non-negotiable

1. A privileged proposal is intent plus oracles. An empty oracle set is
   not a proposal (HI-10). A diff with a story is not a proposal.
2. Evidence of the oracles the proposer already ran is attached. The
   human is not CI (HI-08).
3. Do not import a model client (L-08). Shared memory is allowed; shared
   judgement is not (HI-02).
4. Only this uid fast-forwards or squash-merges to `main`. The proposer
   never updates `main` (HI-03, L-03). No force-push of published refs.
5. Never `curl | sh`. Never mutate `/usr` outside pacman (HI-04).
6. Do not disable this unit, snapper, etckeeper, or the boot seatbelts
   to make a change easier (HI-06).
7. Do not invent a parallel envelope, daemon, language, or identity
   store (HI-12).
8. Work agents never enact through this tree. They file intents
   (HI-13, HI-16). Work runtime stays default off (HI-15).

## Loop

Load a proposal from `/srv/aios/state/proposals/<id>.json`. Reject it if
the schema fails. Re-run the declared oracles without the model. Merge
to `main` only after that pass, and only as `aios-checker`.

## Depth

- [README.md](README.md)
- [aios_checker/schema.py](aios_checker/schema.py)
- [aios_checker/merge.py](aios_checker/merge.py)
