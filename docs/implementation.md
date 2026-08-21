# Implementation plan

Turn the specification into a real OS installer. Test it in a VM on the
workstation. Bare metal comes last.

This is a plan, not a second architecture. If a daemon, file, or control
path is required, it is named here and will be named in the envelope before
it is relied upon. Canonical invariants remain
[docs/envelope/hard-invariants.md](envelope/hard-invariants.md).

The complete spec currently lives at the tip of `docs/precision`. The
proposer does not merge to `main`. A human merges the docs stack when
ready.

## Goal

A signed `archiso` payload that:

1. Verifies itself and the target machine.
2. Installs a minimal Arch (btrfs, snapper, systemd, git, pacman) with
   **no desktop**.
3. Drops a TTY **definition surface** that *is* the installer.
4. Compiles the first envelope from two questions (purpose; work-runtime
   opt-in) plus vetoes.
5. Leaves a reconstructible `/srv/aios` whose privileged agent proposes
   and whose checker, a different process, enacts.

## Non-goals

- Personhood, avatars, identity stores, social channels as kernel.
- A new language runtime.
- A memory product.
- DE/WM lock-in (Hyprland is a valid operator client later, not the OS).
- Privileged work agents. They file intents at `/run/aios/intent.sock`.
- Rewriting the kernel.
- AUR as the default path.

## Order of proof

```
payload boots TTY
  → skeleton + seeds local
    → checker refuses bad proposals
      → agent proposes under git
        → installer compiles first envelope (recoverable)
          → kernel denies work-slice privilege
            → summon/notify on TTY
              → optional work-runtime from local seeds
                → QEMU matrix green
                  → bare metal
```

Do not start P10 because P9 is exciting. Do not synthesise a desktop
because the TTY installer is ugly.

## Future code trees

Named now so they are not invented ad hoc. Created when the matching phase
starts. Each is a git repository from the first file.

```
payload/                 # archiso profile, hashes, signatures
  profile/
  build.sh
  hashes.txt
agent/                   # privileged proposer (fixture + live provider)
checker/                 # independent validator, policy scripts, git hooks
installer/               # TTY conversational installer
intent/                  # intent.sock protocol
operator-client/
  tty/                   # summon + notify
tests/
  vm/                    # QEMU harness
  oracles/               # extra CI wrappers around checker policies
seed/                    # already in this repository
docs/                    # specification, including this plan
```

On a running machine the live copies are under `/srv/aios` as already
specified in [architecture.md](architecture.md).

## Units and paths (target)

| Unit / path | Role |
| --- | --- |
| `aios-agent.service` | Privileged proposer. Defined uid. Never merges to `main`. |
| `aios-checker.service` | Independent validator. Separate uid. No model client. |
| `aios-installer.service` | Bootstrap only. TTY. Restart on-failure. |
| `aios-intent.socket` | `/run/aios/intent.sock`. Agent is the only consumer. |
| `aios-work.slice` | `NoNewPrivileges`, `ProtectSystem=strict`. All work units. |
| `/srv/aios/envelope/hard-invariants.md` | Canonical HI-01…17. |
| `/srv/aios/state/bootstrap-in-progress/` | Installer recovery snapshot. |
| `/srv/aios/seeds/` | Payload-materialised seed git objects (HI-17). |
| `/srv/aios/src/work-runtime/` | Optional synthesis target. |

## Schemas

### Intent (work → OS agent)

```
id:                 uuid
source:             work-runtime | work-runtime-bots
asked:              natural language
clause:             envelope path or null
suggested_oracles:  list (advisory; checker decides)
paths:              workspace paths involved
```

This is not a shell. The agent turns accepted intents into ordinary
proposals.

### Proposal (proposer → checker)

As in [agent-loop.md](agent-loop.md): `intent` + `oracles` + `evidence`.
No oracle set, no enactment. `source` may be `human`, `envelope-clause`,
`machine-goal`, or `work-intent`.

### First envelope compiler

Always includes the canonical hard-invariants file. Adds derived
conditions from: purpose, vetoes, work-runtime bit (default off),
optional later operator-client choice. Shown in plain language. Human
accept is the merge authority for layer one.

### Model provider

The proposer talks to a model through `agent/provider`. Two
implementations:

- **fixture** — scripted answers for VM oracles. Default in `tests/vm`.
- **live** — endpoint/key from envelope-approved config. Never required
  for a green mechanical test.

The checker has no provider.

---

## P0 — Source of truth

**Goal.** The tree implementation grows from is the current spec tip.

**Depends.** Human merge of the docs stack when ready. Proposer does not
merge to `main`.

**Deliverables**

- Complete spec on `docs/precision` (already true).
- This file.
- Future code trees named above.

**Oracles**

- `docs/envelope/hard-invariants.md` exists and is the only HI list.
- `seed/work-runtime` and `seed/work-runtime-bots` exist.
- README specification table names this plan.

**Done.** An implementer can clone the spec tip and know where every new
daemon will live before writing it.

| WP | Title | Delivers |
| --- | --- | --- |
| P0.1 | Keep the spec tip current | `docs/precision` remains complete until a human merges. |
| P0.2 | Name the implementation trees | payload, agent, checker, installer, intent, tests/vm. |

## P1 — Trusted payload

**Goal.** An archiso-shaped image that verifies itself and the machine,
then installs a minimal Arch with no desktop.

**Depends.** P0.

**Deliverables**

- `payload/profile/` — packages.x86_64, pacman.conf, airootfs.
- Minimal set: `base`, `linux`, `linux-firmware`, `btrfs-progs`,
  `snapper`, `git`, `pacman`, `systemd`, `etckeeper`, `networkmanager` or
  `iwd`. `openssh` present, **disabled** until the envelope says so.
- Self-checksum plus minisign signature the human can check out of band.
- First-boot: TTY autologin to the installer, not a graphical session.
- `payload/hashes.txt` — pinned hashes of agent, checker, seeds,
  hard-invariants.
- `payload/build.sh` — reproducible image build from this repository.

**Oracles**

- Image builds from a pinned Arch bootstrap.
- QEMU boot reaches a TTY installer, not a DE.
- Checksum matches `hashes.txt`. Signature verifies.
- No `hyprland`, `gnome`, `plasma`, `sddm`, or `gdm` in the image list.

**Done.** A QEMU VM boots the image to a TTY installer prompt. The payload
is smaller and less free than the running system.

| WP | Title | Delivers |
| --- | --- | --- |
| P1.1 | archiso profile | `payload/profile` with the minimal package list. |
| P1.2 | Self-verify | Checksum + minisign; out-of-band steps in `payload/README.md`. |
| P1.3 | TTY firstboot | getty autologin → `aios-firstboot`. No display manager. |
| P1.4 | Pinned blobs | `hashes.txt` for agent, checker, seeds, HI file. |

## P2 — Machine skeleton

**Goal.** After install, `/srv/aios` exists as git, seeds are local,
snapper and etckeeper are on.

**Depends.** P1.

**Deliverables**

- btrfs layout with snapper for root (and home if separate).
- `/srv/aios/{envelope,memory,skills,agent,checker,state,src,seeds}` each
  a git repo; etckeeper for `/etc`.
- Canonical HI file at `/srv/aios/envelope/hard-invariants.md`.
- Seeds copied into `/srv/aios/seeds` as git objects (HI-17).
- `state/packages.txt` from `pacman -Qqe`.
- Machine-wide `AGENTS.md` installed from this project.

**Oracles**

- Network down: seeds contain work-runtime and hard-invariants.
- `snapper list` works. etckeeper is clean after first commit.
- `git -C /srv/aios/envelope rev-parse HEAD` succeeds.
- `packages.txt` equals `pacman -Qqe`.

**Done.** A freshly payload-installed box has a reconstructible skeleton
before any conversation.

| WP | Title | Delivers |
| --- | --- | --- |
| P2.1 | Disk and snapper | btrfs subvolumes + timeline + pre-enactment hook. |
| P2.2 | Git trees | Init of every `/srv/aios` repo with README and `.gitignore`. |
| P2.3 | Seed materialisation | Copy payload seeds; verify offline. |

## P3 — Checker MVP

**Goal.** An independent, boring process that cannot be talked into a
pass. No model in this unit.

**Depends.** P2.

**Deliverables**

- `checker/` source. `/srv/aios/checker`. `aios-checker.service`,
  separate uid.
- Proposal schema. Missing oracle set → reject.
- Git hooks: deny proposer merge to `main`; deny force-push (HI-03).
- Policy scripts: `hard-invariants.sh`, `packages-drift.sh`,
  `snapper-enabled.sh`, `etckeeper-enabled.sh`, `no-curl-sh.sh`,
  `work-slice.sh`.
- Merge gate: only the checker uid fast-forwards or squash-merges to
  `main`.

**Oracles**

- A diff with a story and no oracle set is rejected.
- Proposer uid cannot push to `main`.
- Stopping snapper to “make a change easier” is rejected (HI-06).
- Checker unit does not import a model client.

**Done.** Privileged enactment is mechanically gated.

| WP | Title | Delivers |
| --- | --- | --- |
| P3.1 | Schema and unit | `aios-checker.service` + proposal schema. |
| P3.2 | Git hooks | `update` / `pre-receive` templates for privileged repos. |
| P3.3 | HI oracles | One script per invariant that can fail closed. |

## P4 — Privileged agent MVP

**Goal.** Always-on proposer with a defined uid, deny-list, and a
fixture-able model adapter.

**Depends.** P3.

**Deliverables**

- `agent/` source. `aios-agent.service`. Does not merge to `main`.
- Loop: triage → skills → branch `agent/<date>-<slug>` → oracles →
  checker → remember.
- Provider adapter: live or fixture. Tests never require a paid API.
- Machine-goal runner: packages.txt sync, snapper before writes,
  reconstructibility, work-runtime synthesis if the bit is set.
- Memory ingest verbatim (HI-11).
- Consumer of `/run/aios/intent.sock`.

**Oracles**

- Agent uid cannot `git push main`.
- A fixture proposer that emits a no-oracle patch is rejected.
- Memory contains the raw exchange, not a model summary in its place.
- Unit restart resumes machine goals; it does not invent motives.

**Done.** The machine can be administered by the agent under the checker
without a human running pacman.

| WP | Title | Delivers |
| --- | --- | --- |
| P4.1 | Unit and uid | `aios-agent.service`, sysuser, deny-list. |
| P4.2 | Provider adapter | Live + fixture. VM tests use fixture. |
| P4.3 | Loop + memory | Turn loop, skill load, verbatim ingest. |
| P4.4 | Machine goals | Checkable operational constraints. |

## P5 — Conversational installer

**Goal.** TTY definition surface that compiles the first envelope from
two questions, with recovery.

**Depends.** P4.

**Deliverables**

- `installer/` — `aios-installer.service`, restart on-failure, TTY-bound.
- Questions: purpose; work-runtime opt-in. Skipping is not a yes.
  Default administer-only.
- Vetoes: never-do, networks, remotes.
- Compiled envelope in plain language. Wait for explicit accept.
- Recovery directory: accepted answers, draft envelope, last snapper id.
- Reject → snapper rollback. No half-installed undeclared state.
- Emergency brake works during bootstrap.

**Oracles**

- Kill installer mid-question; reboot; last accepted answers reappear.
- Unset work-runtime bit → no work-runtime unit (HI-15).
- Reject envelope → snapper undo; `packages.txt` matches pre-conversation.
- First surface is TTY even if a GPU is present.

**Done.** A human can finish bootstrap in a VM by answering two questions
and accepting an envelope.

| WP | Title | Delivers |
| --- | --- | --- |
| P5.1 | TTY definition surface | Installer on getty; same wake contract as later clients. |
| P5.2 | Envelope compiler | Purpose + vetoes + work bit + HI file. |
| P5.3 | Recovery snapshot | `bootstrap-in-progress` + resume on boot. |

## P6 — Privilege boundary

**Goal.** Work processes cannot enact. The kernel says no.

**Depends.** P3, P4.

**Deliverables**

- `intent/` — `/run/aios/intent.sock`. Agent is the only consumer.
- Intent record as above. Not a shell.
- `aios-work.slice` with `NoNewPrivileges`, `ProtectSystem=strict`, tight
  capabilities, no write to privileged trees.
- Refused intents return a structured reason on the definition surface.

**Oracles**

- A process in `aios-work.slice` running `pacman -S` fails as
  permission/capabilities, not as “the model declined” (HI-13, HI-16).
- The same process can file a valid intent; the agent proposes or refuses
  with a reason.
- Work uid cannot open `/srv/aios/envelope` for write.

**Done.** Privilege is an OS property.

| WP | Title | Delivers |
| --- | --- | --- |
| P6.1 | intent.sock | Socket unit, record schema, agent consumer. |
| P6.2 | Work slice | `aios-work.slice` + drop-in for any work unit. |
| P6.3 | Denial oracles | Checker tests that attempt pacman from the slice and expect fail. |

## P7 — Operator client (TTY)

**Goal.** Summon and notify exist. The first client is the TTY. No DE
required.

**Depends.** P5.

**Deliverables**

- `operator-client/tty` — summon and notify.
- Failure payload: unit, journal slice, state commit, snapper id,
  matching clause.
- OS intents: explain failed unit, pending envelope, last snapper,
  open definition surface.
- Graphical clients (GNOME/KDE/Hyprland/tmux adapters) are later
  envelope-driven synthesis, not MVP.

**Oracles**

- Fail a dummy unit → notification carries the four fields and opens the
  OS-agent wake, not a coding CLI (HI-14).
- Summon from the TTY opens the definition surface with envelope +
  memory + skills.
- No key chord is hard-coded into the OS contract.

**Done.** The human can find OS work and be told when the machine fails,
on a box with no desktop.

| WP | Title | Delivers |
| --- | --- | --- |
| P7.1 | Summon | TTY command `aios` lists intents or attaches the definition surface. |
| P7.2 | Notify | systemd failure → structured payload. |

## P8 — Work-runtime synthesis

**Goal.** If and only if bootstrap recorded yes, synthesise the seed as
an ordinary project.

**Depends.** P5, P6.

**Deliverables**

- Machine goal: `envelope.work-runtime=yes` ⇒
  `/srv/aios/src/work-runtime` exists as its own git repo, units in
  `aios-work.slice`.
- Synthesis from `/srv/aios/seeds/work-runtime` (not GitHub).
- Bots extension only if a further envelope clause says so.
- Disable: envelope patch stops user units, leaves git history.

**Oracles**

- Bootstrap no: no work units (HI-15).
- Bootstrap yes, network down: synthesis still completes (HI-17).
- A work-agent pacman attempt still fails (P6).

**Done.** Optional user-space agents exist only when asked, and cannot
administer the machine.

| WP | Title | Delivers |
| --- | --- | --- |
| P8.1 | Synthesis job | Seed → `src/work-runtime`, oracles, checker, merge. |
| P8.2 | Work units | User units in `aios-work.slice`. |
| P8.3 | Bots opt-in | Second envelope bit. Not implied by work-runtime yes. |

## P9 — VM harness

**Goal.** The workstation proves the installer in QEMU/KVM.

**Depends.** P1–P5 for the first useful loop; P1–P8 for the full matrix.

**Deliverables**

- `tests/vm/` — build payload, boot, drive installer via fixture or
  expect, snapshot, reconstruct.
- Targets: `vm-smoke`, `vm-recover`, `vm-reconstruct-offline`,
  `vm-privilege-deny`, `vm-work-yes`, `vm-work-no`.
- Exit non-zero on oracle fail. No human as CI.
- Workstation recipe: nested virt, disk image, serial console.

**Oracles**

- `vm-smoke`: boot → TTY installer → accept administer-only envelope →
  agent+checker running.
- `vm-recover`: kill installer, reboot, resume.
- `vm-reconstruct-offline`: rebuild with nic unplugged; envelope
  satisfied.
- `vm-privilege-deny`: work slice cannot pacman.
- `vm-work-no` / `vm-work-yes`: HI-15 both ways.

**Done.** A failed invariant is a red test on the workstation, not a
conversation.

| WP | Title | Delivers |
| --- | --- | --- |
| P9.1 | QEMU wrapper | `tests/vm/run.sh` with serial and snapshot. |
| P9.2 | Smoke and recover | `vm-smoke`, `vm-recover`. |
| P9.3 | Reconstruct and deny | offline reconstruct, privilege deny, work yes/no. |

## P10 — Bare metal

**Goal.** The same payload, signed, on real hardware. After the VM
matrix is green.

**Depends.** P9 green on the workstation.

**Deliverables**

- USB write + out-of-band signature check.
- Firmware/disk verify from the payload.
- Hardware-specific state commits marked inapplicable on reconstruct.
- No new architecture.

**Oracles**

- Signature verifies on a second machine before boot.
- First surface is still TTY.
- Reconstruct of that metal box satisfies HI-09.

**Done.** A real machine is AIOS. This phase is last on purpose.

| WP | Title | Delivers |
| --- | --- | --- |
| P10.1 | Signed USB procedure | Human-checkable steps; no `curl \| sh`. |
| P10.2 | Metal reconstruct | Skip hardware-specific commits; checker marks them. |

---

## First useful loop (do this first)

The smallest path that is still AIOS:

1. P1 payload boots a TTY in QEMU.
2. P2 skeleton + local seeds.
3. P3 checker rejects a no-oracle patch.
4. P4 fixture agent proposes a legal envelope-neutral change (e.g. set
   hostname from a compiled clause) and the checker merges it.
5. P5 installer asks the two questions, recovers from a kill, accepts
   administer-only.
6. P9 `vm-smoke` + `vm-recover` green.

Only then: P6 denial, P7 notify, P8 work-runtime, full P9 matrix, P10.

## Workstation notes (Jim)

- Nested KVM on the workstation is enough for P1–P9.
- Serial console, not VNC, for the TTY installer (scriptable).
- Keep the payload unsigned in early P1 if signing is blocking; P1.2
  must land before any image leaves the workstation.
- Live model provider is optional until a human wants a real
  conversation in the VM. Fixture covers every oracle listed above.

## Mapping back to the spec

| Spec | Phase |
| --- | --- |
| [bootstrap.md](bootstrap.md) | P1, P2, P5, P9, P10 |
| [architecture.md](architecture.md) | P2, P3, P4, P6 |
| [envelope/hard-invariants.md](envelope/hard-invariants.md) | P3 (oracles), all phases (constraints) |
| [agent-loop.md](agent-loop.md) | P4 |
| [desktop.md](desktop.md) | P7, P8 |
| [git-standards.md](git-standards.md) | P3, P4 |
| [arch-linux.md](arch-linux.md) | P1, P2 |
| [software-acquisition.md](software-acquisition.md) | P4 (later synthesis) |
| [seed/work-runtime](../seed/work-runtime/README.md) | P8 |
| [seed/work-runtime-bots](../seed/work-runtime-bots/README.md) | P8.3 |
