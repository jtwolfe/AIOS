# Hard invariants

Canonical. The checker loads this file. Other documents quote it by id
(HI-01 … HI-17). They do not extend it in prose.

Changing an entry is an envelope patch at layer one and requires explicit
human authority on the definition surface.

On a running machine this file lives at `/srv/aios/envelope/hard-invariants.md`.
In this repository it is `docs/envelope/hard-invariants.md`. The trusted
payload copies it into the machine’s envelope git on first install
(HI-17).

Each entry names a **statement**, a **check** the checker can run without
the model, and an **enforcer**. A vibe is not an invariant.

## HI-01 · Local git is source of truth

**Statement.** Local git is the source of truth for code and privileged enactment.

**Check.** Every privileged change has a commit in the owning repository or
`/srv/aios/state`. Undeclared live state fails reconstructibility.

**Enforcer.** Checker git-source-of-truth oracle; etckeeper; packages.txt.

## HI-02 · Proposer and checker are different processes

**Statement.** The proposer and the checker are different processes.

**Check.** Proposer uid cannot merge to `main`. Checker is a separate systemd
unit. Shared memory is allowed; shared judgement is not.

**Enforcer.** systemd unit isolation; git hooks; checker merge gate.

## HI-03 · No proposer merge to main

**Statement.** No commit to `main` by the proposer. No force-push of published history.

**Check.** pre-receive / update hooks reject proposer-signed commits on `main`
and non-fast-forward of published refs.

**Enforcer.** git hooks in every privileged repository.

## HI-04 · No unsigned root install

**Statement.** No `curl | sh`. No unsigned install as root. No `/usr` mutation outside pacman.

**Check.** Root shell history, pacman log, and filesystem audit match the
declared package list. Unsigned root installs fail.

**Enforcer.** Checker policy; pacman transaction audit; packages.txt.

## HI-05 · Human authority over this list

**Statement.** Hard invariants change only with explicit human authority.

**Check.** A patch to this list requires a recorded human accept on the
definition surface plus checker meta-rule pass.

**Enforcer.** Envelope meta-rules; definition-surface accept log.

## HI-06 · Seatbelts stay on

**Statement.** Snapper, etckeeper, the checker, and the boot seatbelts may not be disabled to make a change easier. A snapper window that does not include a matching boot image is not a seatbelt. A partial upgrade is not a seatbelt.

**Check.** Those units are enabled. `linux` and `linux-lts` are both installed. The current snapper window has a corresponding ESP/UKI generation. A proposal that stops or masks any of these, or that performs a partial upgrade, is rejected.

**Enforcer.** Checker policy (`hi-06-seatbelts.sh`, `boot-seatbelt.sh`, `no-partial-upgrade.sh`); systemd; envelope.


## HI-07 · Conflicts are raised

**Statement.** Direct human instruction outranks skills and derived conditions, but not hard invariants; conflicts are raised.

**Check.** A conflicting instruction produces a raised conflict record, not a
silent pass or a silent swallow.

**Enforcer.** Privileged agent triage; checker.

## HI-08 · Human is not CI

**Statement.** The human is not used as CI. The agent verifies.

**Check.** No proposal closes with “run this and tell me.” Oracles were
executed; evidence is attached.

**Enforcer.** Proposal schema; checker refuses missing evidence.

## HI-09 · No undeclared live state

**Statement.** Undeclared live state is a defect.

**Check.** Reconstruct-from-cold of the current envelope plus git history
satisfies the envelope. Hidden snowflake state fails.

**Enforcer.** Reconstructibility oracle.

## HI-10 · No proposal without oracles

**Statement.** No privileged proposal without oracles. A diff with a story is not a proposal.

**Check.** Proposal documents include a non-empty oracle set the checker can
re-run without the model.

**Enforcer.** Proposal schema; checker.

## HI-11 · Model does not curate memory

**Statement.** The proposing model does not decide what memory is worth keeping.

**Check.** Significant exchanges and privileged actions are stored verbatim.
Deletion is an envelope patch, not model fiat.

**Enforcer.** Memory ingest path; envelope.

## HI-12 · Grow only when the loop is proven

**Statement.** Grow complexity only when the basic loop is proven useful.

**Check.** New daemons, languages, or identity stores unnamed in the envelope
are rejected as parallel architecture.

**Enforcer.** Envelope naming rule; checker.

## HI-13 · Work agents file intents

**Statement.** Work agents never enact privileged change. They file intents.

**Check.** A work-runtime process cannot open the privileged enactment path.
Attempts to `pacman`, `systemctl`, or write outside the work slice are denied
by the OS.

**Enforcer.** systemd slice; filesystem ACLs; capability bounding; `/run/aios/intent.sock`.

## HI-14 · Structured failure handoff

**Statement.** System-scoped failure hands a structured payload to the OS agent, not a random coding CLI.

**Check.** Failure notifications carry unit, journal slice, state commit,
snapper id, matching clause. They open the definition surface under the OS
agent wake.

**Enforcer.** Operator-client notify contract; OS agent.

## HI-15 · Work runtime default off

**Statement.** The work runtime is off until bootstrap records an explicit yes.

**Check.** Given no explicit yes in the envelope, no work-runtime unit is
enabled and `/srv/aios/src/work-runtime` is absent or inert.

**Enforcer.** Bootstrap compiler; checker first-envelope oracle.

## HI-16 · Privilege is an OS property

**Statement.** The privilege boundary is enforced by the operating system, not by work-agent cooperation.

**Check.** Only the privileged agent uid can write envelope, state, units, and
the package list. Work processes run in `aios-work.slice` with
`NoNewPrivileges` and `ProtectSystem=strict`.

**Enforcer.** systemd; filesystem; cgroup; `/run/aios/intent.sock`.

## HI-17 · Seeds are local

**Statement.** Reconstruction does not depend on a remote being reachable. Seed trees live in the machine’s git history.

**Check.** After payload install, `seed/work-runtime` (and bots, if present)
exist as local git objects under `/srv/aios/seeds`. Reconstruct-from-cold
succeeds with the network down.

**Enforcer.** Trusted payload; first privileged materialisation; reconstructibility oracle.
