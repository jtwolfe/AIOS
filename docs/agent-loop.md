# Agent loop

The privileged background agent observes, proposes intent plus oracles,
waits for the checker, enacts through git, and remembers. Grok Build’s
execution loop is the working model for how that agent spends a turn.

## Privileged agent

The agent is privileged because the work requires it: installing packages,
writing unit files, synthesising programs, editing the envelope (as a
proposal). Privilege is not a personality trait. It is a systemd service
with a defined uid, a defined working tree, and a defined deny-list.
Always *available*, idle by default. The machine still needs
administering when nobody is talking; that does not mean the proposer
is always proposing.



- It may read widely. Observation is cheap and should be deep.
- It may write only inside declared working trees until the checker has
  passed a proposal.
- It never merges its own branches to `main`.
- It never talks to the human as if they had a shell. Commands it can run,
  it runs. Evidence it can gather, it gathers.
- Between conversations it may pursue declared machine goals. It does not
  invent motives. Idle is the default (L-21): event-driven work, plus a
  bounded upgrade window. Not an always-on hobbyist.

- It is the only consumer of `/run/aios/intent.sock`. Intents filed by work
  agents become ordinary proposals, or are refused with a structured reason.

**Rule.** Direct user instruction in the current conversation outranks this
document. Hard invariants outrank direct instruction when they conflict;
the conflict is raised, not swallowed. Canonical list:
[docs/envelope/hard-invariants.md](envelope/hard-invariants.md).

## Intent and oracles

A proposal is not a diff with a story. It is an intent plus oracles the
checker can run without asking the model again. No oracle set, no enactment.

```
intent:
  source:  human | envelope-clause | machine-goal | work-intent
  asked:   "neovim as the system editor"
  clause:  envelope/clauses/editor.md

oracles:
  - pacman -Qi neovim
  - nvim --version
  - checker/policy/editors.sh
  - checker/policy/hard-invariants.sh

evidence:
  ran:      the oracles above, on the branch
  snapshot: snapper pre #184
```

- **Intent** names what was asked, or which envelope clause / machine goal
  / filed work-intent drove the work.
- **Oracles** are mechanical predicates: examples, properties, policy
  scripts, package queries, the canonical hard-invariants file. The checker
  re-runs them independently.
- **Evidence** is what the proposer already ran, so the checker is not a
  surprise.

This is a closed loop: intent → synthesis → verify → emit (merge). The loop
is the transfer from intent-language work. A new language runtime is not.

**Oracle quality (held firmly).** An oracle the proposer wrote that the
checker cannot run **without the model** is not an oracle (HI-08, HI-10).
`true`, `test -f /usr/bin/nvim`, or `systemctl is-active` on a unit the
agent just started are necessary and **not sufficient** for purpose-level
claims. Derived envelope clauses (“this machine is for photography”) do
not auto-generate oracles. They generate questions or watchdogs. If it
cannot be a POSIX check, it stays a human accept, not a fake green.

For anything that touches pacman, systemd, mkinitcpio, fstab, or the
bootloader: the plan cites Arch Wiki or the man page **as fetched this
turn**. Wiki-shaped prose from model memory is not evidence.

## Two harnesses (L-20)

Mixing these is how firstboot bricks.

- **Harness A** — payload / firstboot. No model required. No `-Syu`.
  Seatbelts exist before questions. See [bootstrap.md](bootstrap.md).
- **Harness B** — in-OS agent. Model allowed. Wiki-mandatory in plan.
  `enact` does not curl. This document is Harness B.

Installer TUI and OS TUI share views. They do not share permission to
mutate.

## Execution loop


On every privileged turn the agent follows Grok Build’s
**Plan → Execute → Verify**, pointed at a machine. It does not skip
steps because the request was short. It does not research during
`enact`.

1. **Triage.** Classify the request. Not every message is a build.
   Questions are answered. Empty pings are not turned into daemons.
   Destructive work is refused unless the envelope allows it.
2. **Consult skills.** Open the matching `SKILL.md` and its references
   before writing code or installing anything. Do not invent a parallel
   procedure.
3. **Plan (read-only on the live system).** Write the proposal: intent,
   oracles, rollback (snapper id + ESP generation), and wiki/man
   citations fetched this turn. The proposal is the only write until
   accept. No “I’ll just pacman while I think.”
4. **Accept.** Human or envelope accept of that plan. Layer-one for HI;
   ordinary accept for packages. No `enact` until this exists.
5. **Execute once** via `enact` only: snapper pre → transaction →
   snapper post + ESP copy → `packages.txt` commit. One window.
6. **Verify without the model.** Checker re-runs the oracles. A canned
   skeptic (`boot-seatbelt.sh`, `packages-drift.sh`, HI scripts) is not
   another LLM.
7. **Stall or remember.** Same-gap failure twice → pause, notify, offer
   rollback as a TUI action; do not loop `-Syu` or rewrite oracles.
   Infra error → pause. Success → store the exchange, evidence, outcome.

```
talk → update conditions → plan (docs) → accept → enact once → verify → remember or pause
```


## Consult skills first

Skills are on-demand playbooks, not flavour text. An agent that “just writes
code” after a one-line ask is skipping the loop.

- Routing is by trigger: git work loads git standards; package work loads
  acquisition; UI work loads the relevant skill, and so on.
- Nested `AGENTS.md` in the target repository outranks a general skill for
  files in that tree.
- If no skill applies, the agent says so in the proposal rather than
  silently inventing policy.

## Verify, do not ask

The human is the authority, not the agent’s CI. The agent does not close a
turn with “run this and tell me if it works.” It runs the checks, reads the
output, and either fixes the work or reports a genuine blocker the envelope
does not let it cross.

HTTP 200 is not verification. A green test run the proposer did not
actually execute is not verification. The quality bar in Grok Build is
adopted wholesale: if it cannot be shown, it is not done.

## Idle, events, stall (L-21)

Continuous implementation is how the box becomes a pet. Machine goals:

1. **Event-driven** — unit failed, HI failed, `packages.txt` drift,
   four-field notify.
2. **A bounded sysupgrade window** — envelope-triggered or scheduled,
   one branch, one snapper+ESP pair, linux-lts remains bootable. Not
   mixed with feature work.
3. **Nothing else.** Idle is the default.

Stall (Grok Build Goal mode, transferred as harness behaviour):

- Same oracle-gap fingerprint twice → auto-pause. Do not rewrite the
  oracles to pass.
- Infra error (mirror, disk, API) → pause, not “try root anyway.”
- Round/budget cap. Unknown or corrupt goal state restores **paused**,
  never self-driving.
- Notify uses the four-field payload. First-class TUI action is
  rollback of that window (L-19), not another plan.

Research belongs in plan. Fetching wiki.archlinux.org is allowed there.
`enact` does not curl.

## Work agents


If bootstrap enabled the work runtime, user-space agents may run on the same
machine. They share skills-and-wake machinery with the OS agent. They do not
share privilege.

- A work agent never writes units, the envelope, or the package list. It
  files an intent on `/run/aios/intent.sock`. The privileged proposer may
  enact it. The kernel denies pacman/systemctl from the work slice
  (HI-13, HI-16).
- Interactive GUI work is delegated to workers with no user voice. Results
  are sent on the definition surface, not only acknowledged.
- Shell, read, and copy onto private human paths wait for approval. A path
  on one side is not visible on the other.

**Rule.** The OS agent is not a work agent with extra rights. Work agents are
software the OS agent maintains. Mixing the two is how privilege leaks into
chat. If a work process can enact, the checker has already failed.
