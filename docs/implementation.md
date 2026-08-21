# Implementation plan

Turn the specification into a real OS installer. Test it in a VM on the
workstation. Bare metal comes last.

This is a plan, not a second architecture. If a daemon, file, or control
path is required, it is named here and will be named in the envelope before
it is relied upon. Canonical invariants remain
[docs/envelope/hard-invariants.md](envelope/hard-invariants.md).

The complete spec currently lives at the tip of `docs/implementation`
(this branch), stacking on `docs/precision`. The proposer does not merge
to `main`. A human merges the docs stack (PRs 1–5) when ready.

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

---

## Locked decisions

Named now so later phases do not invent a parallel stack. Changing one
is a docs patch on this file, not a silent drift in code.

| ID | Decision | Lock |
| --- | --- | --- |
| L-01 | Language | Agent, installer, intent consumer, TTY client: Python 3 from official Arch `python`. Checker driver: Python 3 stdlib only. Policy oracles: POSIX `sh`. VM harness: POSIX `sh` + Python 3 + qemu. No third-party Python deps in MVP. No new language runtime (HI-12). |
| L-02 | Identities | systemd-sysusers: `aios-agent`, `aios-checker`, `aios-work`. Separate uids. No shared supplementary group that can write privileged trees. |
| L-03 | Privileged repos | Bare git at `/srv/aios/git/<name>.git` owned by `aios-checker`. Agent worktrees at `/srv/aios/<name>` with push only to `refs/heads/agent/*`. `reference-transaction` + `update` hooks deny `aios-agent` on `refs/heads/main` and deny force-push of published refs (HI-02, HI-03). |
| L-04 | Enact helper | `aios-agent` is not root. The only root path is `/usr/lib/aios/bin/enact`, a small allowlisted helper (pacman, snapper create, systemctl for `aios-*` units). sudoers: `aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact`. `aios-work` has no sudoers line. |
| L-05 | Intent transport | `/run/aios/intent.sock` via `aios-intent.socket`. `SOCK_STREAM`. One JSON object per connection, then close. Mode `0660`, owner `aios-agent`, group `aios-work`. Agent is the only consumer. Not a shell. |
| L-06 | Work slice | Every work unit: `Slice=aios-work.slice`, `User=aios-work`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `CapabilityBoundingSet=`, `InaccessiblePaths=` privileged trees. Denial is the kernel, not a prompt (HI-13, HI-16). |
| L-07 | Disk (VM default) | 32G qcow2, GPT. 1G ESP vfat `/boot`. Rest btrfs: `@` → `/`, `@home` → `/home`, `@srv` → `/srv`, `@var_log` → `/var/log`, `@snapshots` for snapper. zram swap. Metal may add a swap partition; that commit is hardware-specific (P10). |
| L-08 | Provider | `agent/provider/` has two implementations: `fixture` (default in `tests/vm`) and `live` (urllib to an envelope-approved URL). Tests never require a paid API. Checker imports no provider. |
| L-09 | First surface | TTY. `getty` autologin on `tty1` → `aios-installer` during bootstrap, then `aios` (summon) after accept. No display manager in the payload. |
| L-10 | Signing | minisign. Public key in `payload/minisign.pub` and printed on the out-of-band README. Unsigned images must not leave the workstation (P1.2). |
| L-11 | Time/locale until envelope | UTC, `en_US.UTF-8`, hostname `aios`. Envelope may change these as ordinary proposals. |
| L-12 | Emergency brake | TTY command `aios brake`: stop and mask `aios-agent.service`, freeze `enact`, write `/srv/aios/state/brake`. Installer stays up. Human-only. |

---

## Future code trees

Named now so they are not invented ad hoc. Created when the matching phase
starts. Each is a git repository from the first file.

```
payload/                      # P1 — archiso profile
  README.md
  build.sh
  hashes.txt
  minisign.pub
  profile/
    profiledef.sh
    packages.x86_64
    pacman.conf
    bootstrap_packages.x86_64
    airootfs/
      etc/systemd/system/
      etc/systemd/system-generators/
      usr/lib/aios/bin/{firstboot,enact,installer,agent,checker,aios}
      usr/lib/sysusers.d/aios.conf
      usr/lib/tmpfiles.d/aios.conf
      srv/aios/seeds/           # copied in, already git
agent/                        # P4 — privileged proposer
  AGENTS.md
  README.md
  pyproject.toml              # name only; stdlib, no deps
  aios_agent/
    loop.py
    triage.py
    skills.py
    memory.py
    provider/{base.py,fixture.py,live.py}
    intent_consume.py
    goals.py
checker/                      # P3 — independent validator
  AGENTS.md
  README.md
  aios_checker/
    main.py
    schema.py
    merge.py
  policy/                     # POSIX sh, one file per HI plus extras
    hi-01-git-source.sh
    … hi-17-seeds-local.sh
    packages-drift.sh
    snapper-enabled.sh
    etckeeper-enabled.sh
    no-curl-sh.sh
    work-slice.sh
    secrets-scan.sh
  hooks/
    update
    reference-transaction
    pre-receive
installer/                    # P5 — TTY conversational installer
  aios_installer/{main.py,questions.py,compiler.py,recover.py}
intent/                       # P6 — record schema (consumed by agent)
  schema.json
  README.md
operator-client/
  tty/{aios.py,notify.py}     # P7
tests/
  vm/
    run.sh
    qemu.sh
    fixtures/{smoke.json,recover.json,work-yes.json,work-no.json}
    oracles/
  oracles/                    # extra CI wrappers around checker policies
seed/                         # already in this repository
docs/                         # specification, including this plan
```

On a running machine the live copies are under `/srv/aios` as already
specified in [architecture.md](architecture.md). Bare privileged git is
under `/srv/aios/git/`. Seeds stay at `/srv/aios/seeds/`.

## Units and paths (target)

| Unit / path | Role |
| --- | --- |
| `aios-agent.service` | Privileged proposer. User `aios-agent`. Never merges to `main`. |
| `aios-checker.service` | Independent validator. User `aios-checker`. No model client. |
| `aios-installer.service` | Bootstrap only. TTY. `Restart=on-failure`. |
| `aios-intent.socket` | `/run/aios/intent.sock`. Agent is the only consumer. |
| `aios-work.slice` | `NoNewPrivileges`, `ProtectSystem=strict`. All work units. |
| `/usr/lib/aios/bin/enact` | Allowlisted root helper. The only sudo path. |
| `/usr/lib/aios/bin/aios` | TTY summon / brake / status. |
| `/srv/aios/envelope/hard-invariants.md` | Canonical HI-01…17. |
| `/srv/aios/state/bootstrap-in-progress/` | Installer recovery snapshot. |
| `/srv/aios/state/brake` | Emergency brake flag. |
| `/srv/aios/state/packages.txt` | `pacman -Qqe` pin. |
| `/srv/aios/seeds/` | Payload-materialised seed git objects (HI-17). |
| `/srv/aios/src/work-runtime/` | Optional synthesis target. |
| `/srv/aios/git/*.git` | Bare privileged repos, checker-owned. |

### sysusers

```
# /usr/lib/sysusers.d/aios.conf
u aios-agent  - "AIOS privileged proposer"   /srv/aios  /usr/bin/nologin
u aios-checker - "AIOS independent checker"  /srv/aios  /usr/bin/nologin
u aios-work   - "AIOS unprivileged work"     /home      /usr/bin/nologin
g aios-work   -
```

### Slice drop-in (work units)

```
# /etc/systemd/system/aios-work.slice
[Unit]
Description=AIOS unprivileged work
[Slice]
MemoryMax=2G
CPUQuota=200%
```

Work `.service` files include:

```
[Service]
Slice=aios-work.slice
User=aios-work
Group=aios-work
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
LockPersonality=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime
InaccessiblePaths=/srv/aios/envelope /srv/aios/state /srv/aios/agent /srv/aios/checker /srv/aios/git /etc/systemd/system /usr/lib/aios/bin/enact
```

### Socket

```
# aios-intent.socket
[Unit]
Description=AIOS work-intent socket
[Socket]
ListenStream=/run/aios/intent.sock
SocketUser=aios-agent
SocketGroup=aios-work
SocketMode=0660
Accept=no
[Install]
WantedBy=sockets.target
```

`aios-agent.service` has `Sockets=aios-intent.socket` and consumes the fd.

---

## Schemas

### Intent (work → OS agent)

JSON, one object, UTF-8. Written to the socket; the agent ACKs a JSON
result on the same connection.

```
{
  "id": "uuid-v4",
  "source": "work-runtime",
  "asked": "install neovim as the system editor",
  "clause": null,
  "suggested_oracles": ["pacman -Qi neovim"],
  "paths": ["/srv/aios/src/work-runtime"]
}
```

`source` is `work-runtime` or `work-runtime-bots`. `clause` is an envelope
path or null. `suggested_oracles` are advisory; the checker decides.
This is not a shell. The agent turns accepted intents into ordinary
proposals. Refused intents return:

```
{
  "id": "uuid-v4",
  "accepted": false,
  "reason": "clause conflict with HI-04",
  "surface": "definition"
}
```

### Proposal (proposer → checker)

File: `/srv/aios/state/proposals/<id>.json` committed on the agent
branch of the owning repo. Missing oracle set → reject (HI-10).

```
{
  "id": "uuid-v4",
  "branch": "agent/2026-08-21-neovim-as-editor",
  "repos": ["state", "envelope"],
  "intent": {
    "source": "human",
    "asked": "neovim as the system editor",
    "clause": "envelope/clauses/editor.md"
  },
  "oracles": [
    "policy/hard-invariants.sh",
    "pacman -Qi neovim",
    "policy/packages-drift.sh"
  ],
  "evidence": {
    "ran": ["policy/hard-invariants.sh"],
    "snapper_pre": 184
  }
}
```

`intent.source` is `human` | `envelope-clause` | `machine-goal` |
`work-intent`. Schema lives in `checker/aios_checker/schema.py` and
`intent/schema.json`.

### First envelope compiler

Always includes the canonical hard-invariants file. Adds derived
conditions from: purpose, vetoes, work-runtime bit (default off),
optional later operator-client choice. Shown in plain language. Human
accept is the merge authority for layer one.

Inputs (recovery-durable):

```
# /srv/aios/state/bootstrap-in-progress/answers.json
{
  "purpose": "…",
  "work_runtime": false,
  "vetoes": { "never": [], "networks": [], "remotes": false },
  "step": "questions",
  "snapper_pre": 1,
  "accepted": false
}
```

Skipping `work_runtime` is not a yes. Default `false`.

### Model provider

The proposer talks to a model through `agent/aios_agent/provider`.

- **fixture** — scripted turns under `tests/vm/fixtures/`. Default in
  the VM harness. No network.
- **live** — `urllib` to an envelope-approved endpoint and key path.
  Never required for a green mechanical test.

The checker has no provider and must not import `aios_agent.provider`.

---

## HI → oracle map

One POSIX script per invariant, plus the extras named in P3. Each script
exits 0 on pass, non-zero on fail, prints a one-line reason on stderr.
The checker re-runs them without the model.

| HI | Script | Notes |
| --- | --- | --- |
| HI-01 | `policy/hi-01-git-source.sh` | Privileged paths have commits; `packages.txt` matches. |
| HI-02 | `policy/hi-02-split.sh` | Distinct uids; two units; checker has no provider import. |
| HI-03 | `hooks/update` + `policy/hi-03-no-proposer-main.sh` | Agent cannot update `main`; no force-push. |
| HI-04 | `policy/hi-04-no-unsigned-root.sh` + `no-curl-sh.sh` | pacman log vs packages.txt; no curl\|sh in history. |
| HI-05 | `policy/hi-05-human-authority.sh` | HI file patches require accept log. |
| HI-06 | `policy/hi-06-seatbelts.sh` + `snapper-enabled.sh` + `etckeeper-enabled.sh` | Units enabled; proposals that mask them fail. |
| HI-07 | `policy/hi-07-conflicts-raised.sh` | Conflict records exist when instruction vs HI. |
| HI-08 | `schema.py` (missing evidence → reject) | No “run this and tell me.” |
| HI-09 | `policy/hi-09-no-undeclared-state.sh` | Reconstruct oracle. |
| HI-10 | `schema.py` (empty oracles → reject) | — |
| HI-11 | `policy/hi-11-verbatim-memory.sh` | Memory files are raw exchanges. |
| HI-12 | `policy/hi-12-named-daemons.sh` | Units not named here or in the envelope fail. |
| HI-13 | `policy/work-slice.sh` | Work uid cannot pacman / write envelope. |
| HI-14 | `policy/hi-14-failure-handoff.sh` | Notify payload has the four fields. |
| HI-15 | `policy/hi-15-work-default-off.sh` | No work units unless envelope bit. |
| HI-16 | `policy/hi-16-os-privilege.sh` | Slice flags, inaccessible paths, socket mode. |
| HI-17 | `policy/hi-17-seeds-local.sh` | Seeds present as git with nic down. |

---

## First-boot sequence

1. UEFI boots the signed ISO. `firstboot` verifies `hashes.txt` and the
   minisign signature before touching disks.
2. Probe firmware and disks. Refuse if the target is not what the
   operator confirmed.
3. Partition per L-07. Mount. `pacstrap` the payload package list.
4. Copy seeds, HI file, sysusers, units, `enact`. systemd-sysusers.
   Init bare git under `/srv/aios/git`. Materialise worktrees.
5. Enable `aios-installer.service` on `getty@tty1` autologin. Reboot
   to disk.
6. Installer on TTY: purpose; work-runtime (skip = no); vetoes. After
   every accepted answer, write `bootstrap-in-progress/`.
7. Show compiled envelope in plain language. Wait for explicit
   `accept`. Reject → snapper undo to `snapper_pre`. Kill/reboot →
   resume from the snapshot (HI-09, recovery).
8. Checker merges the first envelope to `envelope` `main` under the
   human-accept record. Agent unit starts. Installer stops.
9. If work-runtime was yes, synthesis is a machine goal (P8) and
   bootstrap is not finished until that git exists.

---

## P0 — Source of truth

**Goal.** The tree implementation grows from is the current spec tip.

**Depends.** Human merge of the docs stack when ready. Proposer does not
merge to `main`.

**Deliverables**

- Complete spec on `docs/implementation` (this file plus the stacked
  docs). `docs/precision` is the parent of this branch.
- This file, including locked decisions L-01…L-12 and the HI oracle map.
- Future code trees named above.

**Oracles**

- `docs/envelope/hard-invariants.md` exists and is the only HI list.
- `seed/work-runtime` and `seed/work-runtime-bots` exist.
- README specification table names this plan.
- README status is no longer “early conceptual capture” on this branch.

**Done.** An implementer can clone the spec tip and know where every new
daemon will live, which uid owns it, and which oracle fails if they drift,
before writing it.

| WP | Title | Delivers |
| --- | --- | --- |
| P0.1 | Keep the spec tip current | `docs/implementation` remains complete until a human merges PRs 1–5. |
| P0.2 | Name the implementation trees | payload, agent, checker, installer, intent, operator-client, tests/vm. |
| P0.3 | Lock implementer decisions | L-01…L-12 in this file. Code that contradicts them is a docs patch first. |

## P1 — Trusted payload

**Goal.** An archiso-shaped image that verifies itself and the machine,
then installs a minimal Arch with no desktop.

**Depends.** P0.

**Deliverables**

- `payload/profile/` — `profiledef.sh`, `packages.x86_64`, `pacman.conf`,
  `airootfs`.
- Minimal set: `base`, `linux`, `linux-firmware`, `btrfs-progs`,
  `snapper`, `git`, `python`, `pacman`, `systemd`, `etckeeper`,
  `minisign`, `iwd`, `sudo`. `openssh` present, **disabled** until the
  envelope says so.
- Self-checksum plus minisign signature the human can check out of band.
- First-boot: TTY autologin to the installer, not a graphical session.
- `payload/hashes.txt` — pinned sha256 of agent, checker, installer,
  seeds, hard-invariants, enact.
- `payload/build.sh` — reproducible image build from this repository,
  pinned Arch bootstrap tarball URL + sha256.

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
| P1.4 | Pinned blobs | `hashes.txt` for agent, checker, installer, seeds, HI file, enact. |

## P2 — Machine skeleton

**Goal.** After install, `/srv/aios` exists as git, seeds are local,
snapper and etckeeper are on.

**Depends.** P1.

**Deliverables**

- btrfs layout per L-07 with snapper for `@` (and `@home`).
- Bare repos `/srv/aios/git/{envelope,memory,skills,agent,checker,state,seeds}.git`.
  Worktrees at `/srv/aios/{envelope,memory,skills,agent,checker,state,seeds}`.
  etckeeper for `/etc`.
- Canonical HI file at `/srv/aios/envelope/hard-invariants.md`.
- Seeds copied into `/srv/aios/seeds` as git objects (HI-17).
- `state/packages.txt` from `pacman -Qqe`.
- Machine-wide `AGENTS.md` installed from this project.

**Oracles**

- Network down: seeds contain work-runtime and hard-invariants.
- `snapper list` works. etckeeper is clean after first commit.
- `git -C /srv/aios/git/envelope.git rev-parse main` succeeds.
- `packages.txt` equals `pacman -Qqe`.

**Done.** A freshly payload-installed box has a reconstructible skeleton
before any conversation.

| WP | Title | Delivers |
| --- | --- | --- |
| P2.1 | Disk and snapper | btrfs subvolumes + timeline + pre-enactment hook. |
| P2.2 | Git trees | Bare repos + worktrees + README + `.gitignore` + hooks. |
| P2.3 | Seed materialisation | Copy payload seeds; verify offline. |

## P3 — Checker MVP

**Goal.** An independent, boring process that cannot be talked into a
pass. No model in this unit.

**Depends.** P2.

**Deliverables**

- `checker/` source. `/srv/aios/checker`. `aios-checker.service`,
  uid `aios-checker`.
- Proposal schema (`schema.py`). Missing oracle set → reject.
- Git hooks: `update`, `pre-receive`, `reference-transaction` as L-03.
- Policy scripts listed in the HI → oracle map.
- Merge gate: only the checker uid fast-forwards or squash-merges to
  `main`.
- Import guard: `grep -n provider checker/` is empty.

**Oracles**

- A diff with a story and no oracle set is rejected.
- Proposer uid cannot update `main` (reference-transaction fails).
- Stopping snapper to “make a change easier” is rejected (HI-06).
- Checker unit does not import a model client.

**Done.** Privileged enactment is mechanically gated.

| WP | Title | Delivers |
| --- | --- | --- |
| P3.1 | Schema and unit | `aios-checker.service` + proposal JSON schema. |
| P3.2 | Git hooks | `update` / `pre-receive` / `reference-transaction` templates. |
| P3.3 | HI oracles | One script per invariant that can fail closed. |

## P4 — Privileged agent MVP

**Goal.** Always-on proposer with a defined uid, deny-list, and a
fixture-able model adapter.

**Depends.** P3.

**Deliverables**

- `agent/` source. `aios-agent.service`. User `aios-agent`. Does not
  merge to `main`.
- Loop: triage → skills → branch `agent/<date>-<slug>` → oracles →
  checker → remember.
- Provider adapter: live or fixture. Tests never require a paid API.
- `enact` helper + sudoers as L-04.
- Machine-goal runner: packages.txt sync, snapper before writes,
  reconstructibility, work-runtime synthesis if the bit is set.
- Memory ingest verbatim (HI-11).
- Consumer of `/run/aios/intent.sock` (socket may land in P6; agent
  already refuses unknown writers).

**Oracles**

- Agent uid cannot `git push main`.
- A fixture proposer that emits a no-oracle patch is rejected.
- Memory contains the raw exchange, not a model summary in its place.
- Unit restart resumes machine goals; it does not invent motives.
- `aios-agent` is not in group `wheel`. `enact` is the only sudo path.

**Done.** The machine can be administered by the agent under the checker
without a human running pacman.

| WP | Title | Delivers |
| --- | --- | --- |
| P4.1 | Unit and uid | `aios-agent.service`, sysuser, deny-list, `enact`. |
| P4.2 | Provider adapter | Live + fixture. VM tests use fixture. |
| P4.3 | Loop + memory | Turn loop, skill load, verbatim ingest. |
| P4.4 | Machine goals | Checkable operational constraints. |

## P5 — Conversational installer

**Goal.** TTY definition surface that compiles the first envelope from
two questions, with recovery.

**Depends.** P4.

**Deliverables**

- `installer/` — `aios-installer.service`, restart on-failure, TTY-bound
  on `tty1`.
- Questions: purpose; work-runtime opt-in. Skipping is not a yes.
  Default administer-only.
- Vetoes: never-do, networks, remotes.
- Compiled envelope in plain language. Wait for explicit accept.
- Recovery directory: `answers.json`, `envelope.draft.md`, `snapper_pre`,
  `step`.
- Reject → snapper rollback. No half-installed undeclared state.
- Emergency brake works during bootstrap (`aios brake`).

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

- `intent/schema.json`. Socket unit as L-05. Agent is the only consumer.
- Intent record as above. Not a shell.
- `aios-work.slice` plus the drop-in in L-06.
- Refused intents return a structured reason on the definition surface.

**Oracles**

- A process in `aios-work.slice` running `pacman -S` fails as
  permission/capabilities, not as “the model declined” (HI-13, HI-16).
- The same process can file a valid intent; the agent proposes or refuses
  with a reason.
- Work uid cannot open `/srv/aios/envelope` for write.
- Work uid cannot execute `/usr/lib/aios/bin/enact`.

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

- `operator-client/tty` — `aios` (summon, status, brake) and notify.
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
| P7.3 | Brake | `aios brake` stops and masks the proposer; installer stays. |

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
- Workstation recipe below.

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
| P9.1 | QEMU wrapper | `tests/vm/run.sh` + `qemu.sh` with serial and snapshot. |
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

---

## Workstation recipe

Nested KVM is enough for P1–P9. Serial console, not a graphical viewer,
so the TTY installer is scriptable.

Default QEMU invocation (locked for the harness; flags may grow, this
is the floor):

```
qemu-system-x86_64 \
  -machine q35,accel=kvm \
  -cpu host \
  -m 4096 \
  -smp 2 \
  -drive file=work/aios.qcow2,if=virtio,format=qcow2 \
  -cdrom dist/aios-*.iso \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -serial stdio \
  -display none \
  -no-reboot
```

- Disk image: 32G qcow2 at `work/aios.qcow2` (not committed).
- Offline reconstruct: drop `-netdev` / `-device virtio-net-pci`, use
  `-nic none`.
- Drive the installer over stdio with `tests/vm/fixtures/*.json`.
- Keep the payload unsigned only while P1.1 is blocking; P1.2 must land
  before any image leaves the workstation.
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

## What later code is not allowed to invent

If a future patch wants any of the following, it is a docs patch to this
file (and, if needed, the envelope) first:

- A second privileged uid, a language runtime, a display manager, a
  default-on work runtime, a key chord as OS contract, a GitHub fetch
  during reconstruct, a model inside the checker, a `curl | sh` path,
  AUR as the default install, or a merge-to-main by the proposer.
