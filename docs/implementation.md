# Implementation plan

Turn the specification into a real OS installer. Prove every product
surface in a VM. Public release is the end of this plan. Bare metal is
last extra proof, not a substitute for the release bar.

This is a plan of **requirements, questions, and oracles**, not a second
architecture and not a source tree of daemons. If a daemon, file, or
control path is required, it is named here and will be named in the
envelope before it is relied upon. Code that appears without a phase,
a must-close, and an oracle is drift. Canonical invariants remain
[docs/envelope/hard-invariants.md](envelope/hard-invariants.md).

The complete spec currently lives at the tip of `docs/implementation`
(this branch), stacking on `docs/precision`. The proposer does not merge
to `main`. A human merges the docs stack (PRs 1–5) when ready.

## Goal

A stranger can download a **signed** `archiso` payload, verify it out of
band, boot a VM, answer two questions, and have a machine that satisfies
HI-01…17. That machine is public-release ready.

1. Verifies itself and the target machine.
2. Installs a minimal Arch (btrfs, snapper, systemd, git, pacman) with
   **no desktop**.
3. Drops a TTY **definition surface** that *is* the installer.
4. Compiles the first envelope from two questions (purpose; work-runtime
   opt-in) plus vetoes. Creates one operator login.
5. Leaves a reconstructible `/srv/aios` whose privileged agent proposes
   and whose checker, a different process, enacts.
6. If work-runtime was yes: every transferred user-work surface has a
   green oracle (wake, skills, connectors, workers, routines, bridge,
   store, surface split, workspace write set). If no: no work units.
7. The payload contains no secrets and no PII. Known limitations are
   listed. Graphical operator clients are not in the image.

Bare metal (P10) is the same payload on real hardware after the VM
matrix is green. Public release (P11) is the signed artifacts plus that
green matrix. Finishing this plan means the installer is done, not that
a first slice exists.

## Non-goals

- Personhood, avatars, identity stores, social channels as kernel.
- A new language runtime.
- A memory product.
- DE/WM lock-in (Hyprland is a valid operator client later, not the OS).
- Privileged work agents. They file intents at `/run/aios/intent.sock`.
- Rewriting the kernel.
- AUR as the default path.

## Explicit v1 holes

Named so they are not accidental omissions. They are **out** of the
image this plan ships. An implementer who “just adds” one is drifting.

| Hole | Why it is out | How it re-enters |
| --- | --- | --- |
| Graphical operator client in the payload | TTY TUI is the first client (L-18). GNOME/KDE/Hyprland/tmux GUI is a later restyle of the same views. | Envelope proposal, own phase, own oracles. Same view ids. |
| In-place OS upgrade | Reconstruct from payload + git is the v1 path. | Later envelope clause, own oracles. |
| Multi-operator / multi-seat | One operator login (L-13). | Envelope patch. |
| Default LUKS on the VM image | VM must stay fixture-scriptable. | Asked on metal (P10), not implied. |
| Paid live API in CI | Fixture covers every oracle. | Human L-17 login on a live box after accept. |
| Bots enabled by work-runtime yes | Second envelope bit, asked later, default off. | P8.13. |
| InsideMan identity, channels, desktops-as-screens, personhood | Transfers are wake, skills, connectors, workers, bridge, routines. Nothing else. | Never, without an envelope rewrite. |

## Order of proof

```
payload boots TTY
  → skeleton + seeds local
    → checker refuses bad proposals
      → agent proposes under git
        → installer compiles first envelope (recoverable)
          → kernel denies work-slice privilege
            → summon/notify on TTY (OS surface)
              → optional work-runtime: every transferred surface
                → QEMU matrix green (including work-yes and work-no)
                  → signed public artifacts
                    → bare metal
```

Do not start P10 because P9 is exciting. Do not synthesise a desktop
because the TTY installer is ugly. Do not call the image releasable
because `vm-smoke` passed — `vm-smoke` is administer-only.

**First useful loop** (prove the OS, not the product): P1–P5 plus
`vm-smoke` / `vm-recover`. **Release loop**: that, plus P6–P8, the full
P9 matrix, P11. Metal is extra.

---

## Locked decisions

Named now so later phases do not invent a parallel stack. Changing one
is a docs patch on this file, not a silent drift in code.

| ID | Decision | Lock |
| --- | --- | --- |
| L-01 | Language | Agent, installer, intent consumer, TTY client, **and the work runtime once synthesised**: Python 3 from official Arch `python`. Checker driver: Python 3 stdlib only. Policy oracles: POSIX `sh`. VM harness: POSIX `sh` + Python 3 + qemu. No third-party Python deps in v1. No new language runtime (HI-12). |
| L-02 | Identities | systemd-sysusers: `aios-agent`, `aios-checker`, `aios-work`. Separate uids. No shared supplementary group that can write privileged trees. |
| L-03 | Privileged repos | Bare git at `/srv/aios/git/<name>.git` owned by `aios-checker`. Agent worktrees at `/srv/aios/<name>` with push only to `refs/heads/agent/*`. `reference-transaction` + `update` hooks deny `aios-agent` on `refs/heads/main` and deny force-push of published refs (HI-02, HI-03). |
| L-04 | Enact helper | `aios-agent` is not root. The only root path is `/usr/lib/aios/bin/enact`, a small allowlisted helper (pacman as a full `-Syu` window, snapper create, ESP/UKI generation copy, `bootctl`, systemctl for `aios-*` units). sudoers: `aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact`. `aios-work` has no sudoers line. Partial `pacman -S` is not on the allowlist. |
| L-05 | Intent transport | `/run/aios/intent.sock` via `aios-intent.socket`. `SOCK_STREAM`. One JSON object per connection, then close. Mode `0660`, owner `aios-agent`, group `aios-work`. Agent is the only consumer. Not a shell. |

| L-06 | Work slice | Every work unit: `Slice=aios-work.slice`, `User=aios-work`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `CapabilityBoundingSet=`, `InaccessiblePaths=` privileged trees. Denial is the kernel, not a prompt (HI-13, HI-16). |
| L-07 | Disk (VM default) | 32G qcow2, GPT. 1G ESP vfat `/boot` (**not** in btrfs). Rest btrfs: `@` → `/`, `@home` → `/home`, `@srv` → `/srv`, `@var_log` → `/var/log`, `@snapshots` for snapper. zram swap. Snapper of `@` does not include the ESP or nested `@home`/`@srv`. L-19 is required or snapper is a false seatbelt. Metal may add a swap partition; that commit is hardware-specific (P10). |
| L-08 | Provider | Two implementations: `fixture` (default in `tests/vm`) and `live`. Live is Grok device-code OAuth (L-17), not a pasted API key. Tests never require a paid API or a browser. Checker imports no provider. |

| L-09 | First surface | TTY **TUI**. `getty` autologin on `tty1` → installer TUI during bootstrap, then the same TUI in OS mode after accept. No display manager in the payload. Views are L-18. |
| L-10 | Signing | minisign. Public key in `payload/minisign.pub` and printed on the out-of-band README. Unsigned images must not leave the workstation (P1.2). |
| L-11 | Time/locale until envelope | UTC, `en_US.UTF-8`, hostname `aios`. Envelope may change these as ordinary proposals. |
| L-12 | Emergency brake | TTY command `aios brake`: stop and mask `aios-agent.service`, freeze `enact`, write `/srv/aios/state/brake`. Installer stays up. Human-only. |
| L-13 | Operator login | Bootstrap creates one non-root human login. After accept, `tty1` autologin is that user. No sudo to enact. They may run `/usr/lib/aios/bin/aios` (summon, status, brake). Service uids stay `nologin`. Root is recovery only. |
| L-14 | Two surfaces | OS definition surface and work definition surface are different sessions. Summon names which. A work turn does not receive privileged tools. An OS turn does not run in `aios-work.slice`. One chat with both rights is a fail. |
| L-15 | Workspace write set | Before any work unit is enabled, this plan and the envelope name the directories a work process may write. Slice `ReadWritePaths` equals that set plus tmp. Operator home outside the set is the approval-gated bridge. Privileged trees stay `InaccessiblePaths`. Shipping P8 while the slice only writes `/srv/aios/src/work-runtime` *and* claiming user work in `~/src` is a fail. |
| L-16 | Work provider | The work runtime has its own provider config and secret path. The work uid cannot read the privileged agent's token. Fixture is default in the VM. Live is L-17 on a separate token file. |
| L-17 | Live Grok login | Same browser OAuth as Grok Build (`grok login --device-auth`): TTY prints a verification URL and user code; the human opens that URL on a **phone or other PC**, completes sign-in at `auth.x.ai` / grok.com, the box polls until confirmed. Token file mode `0600`, not in git, not in the transcript. The AIOS box does not open a local browser (no DE in v1). Refused if the envelope vetoed remotes. First live login is after envelope accept. Fixture covers the matrix. OS token and work token are different files (L-16). |
| L-18 | Views | One named view catalog for installer, OS, work, and bots. TUI is v1. GUI is a later restyle of the **same** view ids and actions (visual similarity, identical functionality). Every action has a keyboard path. Mouse and clickable URLs (Grok Build TUI) when the terminal supports them. Serial/QEMU fixtures are keyboard-complete. |
| L-19 | Boot seatbelts | `linux` **and** `linux-lts` always explicit. `kernel-modules-hook`. `snap-pac` pre/post. systemd-boot entries: current linux, linux-lts, previous ESP generation. ESP/UKI copy in the **same** `enact` window as snapper post. A snapper id without a matching boot image fails `boot-seatbelt.sh` (HI-06). TUI `snapper` rollback uses the previous generation, not a live USB. Partial upgrades fail `no-partial-upgrade.sh`. |
| L-20 | Two harnesses | **A** payload/firstboot: pinned, no model required, **no `-Syu`**, seatbelts before questions. **B** in-OS agent: Plan (wiki/man this turn) → accept → `enact` once → verify without the model → stall pause. Research is allowed in plan. `enact` does not curl. Mixing the harnesses is a fail. |
| L-21 | Idle and stall | Agent is always *available*, idle by default. Machine goals are event-driven plus a bounded sysupgrade window. Same oracle-gap twice → pause, notify, offer rollback. Infra error → pause. Unknown/corrupt goal state restores paused, never self-driving. Not an always-proposing hobbyist. |


The slice drop-in later in this file is the **floor** (write the work-runtime tree only). P8.2 must patch L-15 and that drop-in together. They are not allowed to disagree.

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
    boot-seatbelt.sh
    no-partial-upgrade.sh
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
| `/usr/lib/aios/bin/enact` | Allowlisted root helper. The only sudo path. Pacman as `-Syu` window, snapper, ESP generation, bootctl, aios-* units. |

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
    "policy/packages-drift.sh",
    "policy/boot-seatbelt.sh",
    "policy/no-partial-upgrade.sh"
  ],
  "citations": [
    "https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported"
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
  "operator_login": "operator",
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
  the VM harness. No network. No browser.
- **live** — Grok device-code OAuth (L-17). TTY prints URL + user code;
  human finishes on another device; token file `0600`. Never a pasted
  key in chat. Never required for a green mechanical test.

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
| HI-06 | `policy/hi-06-seatbelts.sh` + `snapper-enabled.sh` + `etckeeper-enabled.sh` + `boot-seatbelt.sh` + `no-partial-upgrade.sh` | Units enabled; both kernels; matching ESP generation; partial upgrade fails. |
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
| extra | `policy/boot-seatbelt.sh` | Both kernels; matching ESP generation for last snapper pair. |
| extra | `policy/no-partial-upgrade.sh` | Privileged `pacman -S` without `-Syu` fails. |
| extra | `policy/secrets-scan.sh` | No tokens, keys, `.env` in git or the payload. |
| extra | `policy/pii-scan.sh` | No personal names, emails, phones, addresses in the tree. |


## Coverage

Every product surface this plan is allowed to ship. If a row has no
oracle by P9, the plan is not finished. An implementer does not get to
skip a row because the first slice worked.

| Area | Phase | Acceptance (must be an oracle, not a story) |
| --- | --- | --- |
| Signed, reproducible payload | P1, P11 | Image builds from a pin. minisign verifies. No DE in the list. |
| No secrets / no PII in image | P1, P3 | `secrets-scan` and `pii-scan` green on payload and git. |
| Disk, snapper, etckeeper | P2 | Layout per L-07. snapper list. etckeeper clean. |
| Boot seatbelts | P2, P4, L-19 | `linux` and `linux-lts` present. snap-pac hooks. Matching ESP generation for last snapper pair. systemd-boot has current, lts, previous. |
| Two harnesses | P1, P5, P4, L-20 | Payload does not `-Syu`. In-OS privileged change has a plan with wiki citations before `enact`. |
| Idle and stall | P4, L-21 | Restart does not invent work. Same-gap fixture pauses. Corrupt goal restores paused. |
| Local seeds | P2, P8 | Work-runtime and bots seeds present with nic down (HI-17). |
| Checker split | P3 | No-oracle patch rejected. Checker has no provider. |
| Git hooks | P3 | Proposer cannot update `main`. No force-push. |
| Privileged agent loop | P4 | Fixture turn: plan (citations) → accept → enact once → checker → memory or pause. |
| Software acquisition | P4 | A package install is a **full `-Syu` window** + commit + `packages.txt` + snapper + ESP copy. Partial `-S` fails. |
| Verbatim memory | P4 | Memory files are raw exchanges (HI-11). |

| Machine goals | P4, P8 | Restart resumes goals. Work synthesis only if the bit is set. |
| Conversational installer | P5 | Two questions. Skip ≠ yes. Recover from kill. Reject rolls back. TUI views (L-18), not a raw script. |
| Operator login | P5 | One non-root login (L-13). Autologin after accept. No sudo to enact. |
| First envelope | P5 | HI file + purpose + vetoes + work bit. Human accept is the merge. Envelope is a **view**, not only a chat blob. |
| Live Grok login | L-17, P4, P8.10 | Device-code. URL + user code on TTY. Finish on a phone or other PC. Token not in git or chat. |
| TUI / view catalog | L-18, P5, P7, P8 | Named views. Keyboard-complete. Mouse/clickable URLs when the terminal allows. GUI later uses the same ids. |
| intent.sock | P6 | Work process can file; agent is the only consumer; not a shell. |
| Kernel privilege | P6 | `pacman` from the slice fails as permission (HI-13, HI-16). |
| OS summon / notify / brake | P7 | Four-field payload. `aios brake`. No key chord in the OS contract. |
| Surface split | P7, P8 | Summon names OS vs work. Mixed-privilege chat fails (L-14). |
| Work synthesis | P8.1 | Yes + nic down → live git exists. No → no work units (HI-15). |
| Workspace write set | P8.2 | Declared set is writable. Outside it, no write without bridge approval. |
| Wake + explicit send | P8.4 | Inject order from the seed. Plain model text is not delivered. |
| Skills | P8.5 | Following a skill without reading its body this turn fails. |
| Connectors | P8.6 | MCP used when present. Secret not in chat. Work uid cannot read OS key. |
| Workers | P8.7 | No user voice. Result is sent on the work surface. Cannot enact. |
| Routines | P8.8 | Cron xor listeners on one standing order. Persisted. Disable leaves git. |
| Operator bridge | P8.9 | Shell/read/copy on private paths wait for approval. Copy is verbatim. |
| Work provider | P8.10 | Own fixture. Work uid cannot read the privileged key path (L-16). |
| Work store | P8.11 | Notes, skills, routines, connectors are git in the work tree, not OS memory. |
| Disable work runtime | P8.12 | Envelope patch stops units. Git remains. HI-15 holds. |
| Bots extension | P8.13 | Second bit, default off. Jobs are path+slice+skill. VM work is an intent. |
| Reconstruct offline | P9 | Envelope satisfied with nic unplugged. |
| Full VM matrix | P9 | Every target below red-fails on oracle miss. |
| Public artifacts | P11 | Signed ISO, hashes, operator README, known limitations, version. |
| Bare metal | P10 | Same payload. After P9 green. Hardware-specific commits marked. |

---

## First-boot sequence

1. UEFI boots the signed ISO. `firstboot` verifies `hashes.txt` and the
   minisign signature before touching disks.
2. Probe firmware and disks. Refuse if the target is not what the
   operator confirmed.
3. Partition per L-07. Mount. `pacstrap` the payload package list
   (`linux` and `linux-lts`). Enable snap-pac, kernel-modules-hook,
   systemd-boot generations. **Do not `-Syu`.**

4. Copy seeds, HI file, sysusers, units, `enact`. systemd-sysusers.
   Init bare git under `/srv/aios/git`. Materialise worktrees.
5. Enable `aios-installer.service` on `getty@tty1` autologin. Reboot
   to disk.
6. Installer on TTY: purpose; work-runtime (skip = no); vetoes; operator
   login name. After every accepted answer, write `bootstrap-in-progress/`.
   Bots is **not** asked here.
7. Show compiled envelope in plain language. Wait for explicit
   `accept`. Reject → snapper undo to `snapper_pre`. Kill/reboot →
   resume from the snapshot (HI-09, recovery).
8. Checker merges the first envelope to `envelope` `main` under the
   human-accept record. Create the operator login (L-13). Agent unit
   starts. Installer stops. `tty1` autologin becomes the operator.
9. If work-runtime was yes, synthesis is a machine goal (P8) and
   bootstrap is not finished until that git exists and P8 oracles
   that do not need a live model are green.

---

## P0 — Source of truth

**Goal.** The tree implementation grows from is the current spec tip, and
this plan already names every product surface that v1 will ship.

**Depends.** Human merge of the docs stack when ready. Proposer does not
merge to `main`.

**Must close.** None left open: L-01…L-21 and the coverage table are
the closures. A new daemon that is not in the units list is a docs
patch first (HI-12). A new view that is not in L-18 is a docs patch
first.


**Deliverables**

- Complete spec on `docs/implementation` (this file plus the stacked
  docs). `docs/precision` is the parent of this branch.
- This file: L-01…L-21, coverage table, HI oracle map, v1 holes.

- Future code trees named above.

**Oracles**

- `docs/envelope/hard-invariants.md` exists and is the only HI list.
- `seed/work-runtime` and `seed/work-runtime-bots` exist.
- README specification table names this plan as P0–P11.
- Coverage table has a row for every transferred work-runtime surface.
- README status is no longer “early conceptual capture” on this branch.

**Done.** An implementer can clone the spec tip and know, for every
surface, which phase accepts it and which oracle fails if they skip it.

| WP | Title | Delivers |
| --- | --- | --- |
| P0.1 | Keep the spec tip current | `docs/implementation` remains complete until a human merges PRs 1–5. |
| P0.2 | Name the implementation trees | payload, agent, checker, installer, intent, operator-client, tests/vm. |
| P0.3 | Lock implementer decisions | L-01…L-21. Code that contradicts them is a docs patch first. |

| P0.4 | Coverage | Every v1 surface has a phase and an oracle in this file. |

## P1 — Trusted payload

**Goal.** An archiso-shaped image that verifies itself and the machine,
then installs a minimal Arch with no desktop.

**Depends.** P0.

**Must close.** What is pinned (bootstrap tarball URL + sha256). What
the image must not contain (secrets, PII, DEs, enabled sshd). Version
string location (`os-release` or equivalent).

**Deliverables**

- `payload/profile/` — `profiledef.sh`, `packages.x86_64`, `pacman.conf`,
  `airootfs`.
- Minimal set: `base`, `linux`, `linux-lts`, `linux-firmware`,
  `btrfs-progs`, `snapper`, `snap-pac`, `kernel-modules-hook`, `git`,
  `python`, `pacman`, `systemd`, `etckeeper`, `minisign`, `iwd`, `sudo`.
  `openssh` present, **disabled** until the envelope says so. No
  `pacman -Syu` in firstboot (L-20).

- Self-checksum plus minisign signature the human can check out of band.
- First-boot: TTY autologin to the installer, not a graphical session.
- `payload/hashes.txt` — pinned sha256 of agent, checker, installer,
  seeds, hard-invariants, enact, sysusers, units.
- `payload/build.sh` — reproducible image build from this repository,
  pinned Arch bootstrap tarball URL + sha256.
- Seeds copied into the airootfs so P2 does not fetch GitHub.

**Oracles**

- Image builds from a pinned Arch bootstrap.
- QEMU boot reaches a TTY installer, not a DE.
- Checksum matches `hashes.txt`. Signature verifies.
- No `hyprland`, `gnome`, `plasma`, `sddm`, or `gdm` in the image list.
- `openssh.service` is disabled.
- `secrets-scan` and `pii-scan` green on the image contents.
- Seeds for work-runtime and work-runtime-bots are inside the image.
- `linux` and `linux-lts` both in the image list. Firstboot journal
  contains no `-Syu` (L-20).


**Done.** A QEMU VM boots the image to a TTY installer prompt. The payload
is smaller and less free than the running system. It is fit to become
the public artifact after later phases, not a throwaway demo ISO.

| WP | Title | Delivers |
| --- | --- | --- |
| P1.1 | archiso profile | `payload/profile` with the minimal package list. |
| P1.2 | Self-verify | Checksum + minisign; out-of-band steps in `payload/README.md`. |
| P1.3 | TTY firstboot | getty autologin → `aios-firstboot`. No display manager. |
| P1.4 | Pinned blobs | `hashes.txt` for agent, checker, installer, seeds, HI file, enact. |
| P1.5 | Clean image | No secrets, no PII, sshd disabled, no DE. |

## P2 — Machine skeleton

**Goal.** After install, `/srv/aios` exists as git, seeds are local,
snapper and etckeeper are on.

**Depends.** P1.

**Must close.** Bare-repo names (already listed). Operator home exists
even before the login is created (subvolume `@home`).

**Deliverables**

- btrfs layout per L-07 with snapper for `@` (and `@home`).
- systemd-boot installed to the ESP. Entries: linux, linux-lts.
  `snap-pac` hooks enabled. `kernel-modules-hook` enabled. First ESP
  generation copied next to the initial snapper snapshot (L-19).

- Bare repos `/srv/aios/git/{envelope,memory,skills,agent,checker,state,seeds}.git`.
  Worktrees at `/srv/aios/{envelope,memory,skills,agent,checker,state,seeds}`.
  etckeeper for `/etc`.
- Canonical HI file at `/srv/aios/envelope/hard-invariants.md`.
- Seeds copied into `/srv/aios/seeds` as git objects (HI-17).
- `state/packages.txt` from `pacman -Qqe`.
- Machine-wide `AGENTS.md` installed from this project.
- sysusers and tmpfiles from the payload. Hook templates may be empty
  until P3, but the paths exist.

**Oracles**

- Network down: seeds contain work-runtime, work-runtime-bots, and
  hard-invariants.
- `snapper list` works. etckeeper is clean after first commit.
- `linux` and `linux-lts` both in `packages.txt`. `bootctl list` shows
  linux and linux-lts. `boot-seatbelt.sh` green with no privileged
  change yet.

- `git -C /srv/aios/git/envelope.git rev-parse main` succeeds.
- `packages.txt` equals `pacman -Qqe`.

**Done.** A freshly payload-installed box has a reconstructible skeleton
before any conversation.

| WP | Title | Delivers |
| --- | --- | --- |
| P2.1 | Disk and snapper | btrfs subvolumes + timeline + pre-enactment hook. |
| P2.2 | Git trees | Bare repos + worktrees + README + `.gitignore` + hook paths. |
| P2.3 | Seed materialisation | Copy payload seeds; verify offline. |
| P2.4 | Boot seatbelts | linux-lts, snap-pac, kernel-modules-hook, systemd-boot generations (L-19). |


## P3 — Checker MVP

**Goal.** An independent, boring process that cannot be talked into a
pass. No model in this unit.

**Depends.** P2.

**Must close.** Proposal schema location (`schema.py` + `intent/schema.json`
may wait until P6; the checker already rejects missing oracles).

**Deliverables**

- `checker/` source. `/srv/aios/checker`. `aios-checker.service`,
  uid `aios-checker`.
- Proposal schema (`schema.py`). Missing oracle set → reject.
- Git hooks: `update`, `pre-receive`, `reference-transaction` as L-03.
- Policy scripts listed in the HI → oracle map, plus `secrets-scan.sh`
  and `pii-scan.sh`.
- Merge gate: only the checker uid fast-forwards or squash-merges to
  `main`.
- Import guard: `grep -n provider checker/` is empty.
- HI-12 named-daemons: a unit not in this plan or the envelope fails.

**Oracles**

- A diff with a story and no oracle set is rejected.
- Proposer uid cannot update `main` (reference-transaction fails).
- Stopping snapper to “make a change easier” is rejected (HI-06).
- Checker unit does not import a model client.
- A token-shaped string in a commit is rejected.
- A personal email or personal name in a commit is rejected.

**Done.** Privileged enactment is mechanically gated.

| WP | Title | Delivers |
| --- | --- | --- |
| P3.1 | Schema and unit | `aios-checker.service` + proposal JSON schema. |
| P3.2 | Git hooks | `update` / `pre-receive` / `reference-transaction` templates. |
| P3.3 | HI oracles | One script per invariant that can fail closed. |
| P3.4 | Secrets and PII | `secrets-scan.sh`, `pii-scan.sh`. |

## P4 — Privileged agent MVP

**Goal.** Always-*available* proposer, idle by default (L-21), with a
defined uid, deny-list, and a fixture-able model adapter. The OS loop
is complete even with no work runtime. Harness B, not Harness A.


**Depends.** P3.

**Must close.** Live key path (outside git, mode that `aios-work` cannot
read). Skill crystallization rule (when a pattern earns a `SKILL.md`).
Proposal schema field for wiki/man citations on pacman/systemd/btrfs/boot
changes (empty → reject those classes).


**Deliverables**

- `agent/` source. `aios-agent.service`. User `aios-agent`. Does not
  merge to `main`.
- Loop: triage → skills → **plan** (wiki this turn, no enact) → accept →
  branch `agent/<date>-<slug>` → `enact` once → oracles → checker →
  remember or stall-pause (L-20, L-21).
- Provider adapter: live or fixture. Tests never require a paid API.
- `enact` helper + sudoers as L-04 (includes ESP copy, `bootctl`,
  `-Syu` window only).
- Machine-goal runner: idle default; event-driven repair; bounded
  sysupgrade window; snapper+ESP before writes; reconstructibility;
  work-runtime synthesis if the bit is set. Same-gap stall pauses.
- Memory ingest verbatim (HI-11).
- Software acquisition: a `pacman` enactment is a **full `-Syu`
  window**, a commit, a `packages.txt` update, a snapper+ESP pair.
  Partial `-S` is rejected.

- Conflict raise (HI-07): instruction vs HI produces a record, not a
  silent pass.
- Consumer of `/run/aios/intent.sock` (socket may land in P6; agent
  already refuses unknown writers).

**Oracles**

- Agent uid cannot `git push main`.
- A fixture proposer that emits a no-oracle patch is rejected.
- Memory contains the raw exchange, not a model summary in its place.
- Unit restart resumes machine goals; it does not invent motives.
- `aios-agent` is not in group `wheel`. `enact` is the only sudo path.
- Installing a package from a fixture turn updates `packages.txt` and
  leaves a snapper pair **and** a matching ESP generation.
  `no-partial-upgrade.sh` rejects a fixture that runs `pacman -S`
  without `-Syu`.
- A fixture that proposes pacman/systemd/boot change with empty wiki
  citations is rejected.
- Same-gap stall: two identical oracle failures → goal paused, notify
  fired, no third attempt.
- Work uid cannot read the live provider key path (L-16, even before
  P8 exists).


**Done.** The machine can be administered by the agent under the checker
without a human running pacman.

| WP | Title | Delivers |
| --- | --- | --- |
| P4.1 | Unit and uid | `aios-agent.service`, sysuser, deny-list, `enact`. |
| P4.2 | Provider adapter | Live + fixture. VM tests use fixture. Key not in git. |
| P4.3 | Loop + memory | Turn loop, skill load, verbatim ingest. |
| P4.4 | Machine goals | Idle default, events, bounded upgrade, stall pause (L-21). |
| P4.5 | Acquisition | Full `-Syu` window = commit + packages.txt + snapper + ESP (L-19). |
| P4.6 | Plan citations | Wiki/man this turn for pacman/systemd/boot. Empty → reject. |


## P5 — Conversational installer

**Goal.** The TUI in **installer** mode compiles the first envelope from
two questions plus an operator login, with recovery. Not a raw question
script.

**Depends.** P4.

**Must close.** Operator username: asked, or derived from purpose, and
written to `answers.json`. Bots is **not** a first-envelope question.
Installer uses L-18 views: `conversation`, `questions`, `envelope`,
`accept`, `recovery`, `chrome`. Live Grok login is **not** during
unsigned firstboot (L-17: after accept). Harness A: **no `-Syu`** during
the conversation (L-20).


**Deliverables**

- `installer/` — `aios-installer.service`, restart on-failure, TTY TUI
  on `tty1`. Same view catalog the OS client will use (L-18).
- Questions: purpose; work-runtime opt-in; operator login name.
  Skipping work-runtime is not a yes. Default administer-only.
- Vetoes: never-do, networks, remotes.
- Envelope **view** shows the compiled HI file + derived clauses. Wait
  for explicit accept. Accept/Reject are first-class actions (keyboard
  and clickable).
- Operator login created on accept (L-13). No sudoers for enact.
- Recovery directory: `answers.json`, `envelope.draft.md`, `snapper_pre`,
  `step`. Recovery is a view, not only a log line.
- Reject → snapper rollback. No half-installed undeclared state.
- Emergency brake in chrome during bootstrap.

**Oracles**

- Kill installer mid-question; reboot; last accepted answers reappear.
- Unset work-runtime bit → no work-runtime unit (HI-15).
- Reject envelope → snapper undo; `packages.txt` matches pre-conversation.
- First surface is the TUI even if a GPU is present. No display manager.
- After accept, `tty1` autologin is the operator, not root, not
  `aios-agent`.
- Operator cannot `sudo enact`.
- `answers.json` has no `bots` key, or `bots` is false.
- Envelope view is reachable without scrolling the transcript.
- Every installer action has a keyboard path (serial fixture).
- Installer journal contains no `pacman -Syu` (L-20). Reject still
  matches pre-conversation `packages.txt` **and** ESP generations.


**Done.** A human can finish bootstrap in a VM inside the TUI. The box
has someone to log in as. The same TUI becomes OS mode; it is not a
throwaway wizard.

| WP | Title | Delivers |
| --- | --- | --- |
| P5.1 | Installer TUI | L-18 installer views on getty. Same catalog as later OS. |
| P5.2 | Envelope compiler | Purpose + vetoes + work bit + HI file as the envelope view. |
| P5.3 | Recovery snapshot | `bootstrap-in-progress` + resume on boot + recovery view. |
| P5.4 | Operator login | One non-root user, no enact sudo (L-13). |

## P6 — Privilege boundary

**Goal.** Work processes cannot enact. The kernel says no.

**Depends.** P3, P4.

**Must close.** Socket path, mode, owner (already L-05). Floor write set
until P8.2 (work-runtime tree only).

**Deliverables**

- `intent/schema.json`. Socket unit as L-05. Agent is the only consumer.
- Intent record as above. Not a shell. `source` includes
  `work-runtime` and `work-runtime-bots`.
- `aios-work.slice` plus the drop-in in L-06.
- Refused intents return a structured reason on the **OS** definition
  surface.
- `enact` is not executable by `aios-work`.

**Oracles**

- A process in `aios-work.slice` running `pacman -S` fails as
  permission/capabilities, not as “the model declined” (HI-13, HI-16).
- The same process can file a valid intent; the agent proposes or refuses
  with a reason.
- Work uid cannot open `/srv/aios/envelope` for write.
- Work uid cannot execute `/usr/lib/aios/bin/enact`.
- Work uid cannot read the privileged provider key path.

**Done.** Privilege is an OS property. A future work runtime cannot
accidentally become the OS agent.

| WP | Title | Delivers |
| --- | --- | --- |
| P6.1 | intent.sock | Socket unit, record schema, agent consumer. |
| P6.2 | Work slice | `aios-work.slice` + drop-in for any work unit. |
| P6.3 | Denial oracles | Checker tests that attempt pacman from the slice and expect fail. |

## P7 — Operator client (TUI)

**Goal.** Summon and notify exist. The first client is the TUI (L-18).
No DE required. Summon names **which** surface (OS vs work). GUI later
is a restyle of these views, not a second app.

**Depends.** P5.

**Must close.** How the operator names the surface (`aios` vs
`aios work`, a flag, two commands). Graphical clients stay a v1 hole.
Every L-18 OS view is reachable from chrome.

**Deliverables**

- `operator-client/tty` — TUI: summon, status, brake, notify, **login**.
- OS views: `chrome`, `conversation`, `envelope`, `intents`, `notify`,
  `snapper` (inspect **and rollback**), `packages`, `login`, `brake`.

- Failure payload: unit, journal slice, state commit, snapper id,
  matching clause. Notify view, not a coding CLI.
- Work summon is refused if the envelope bit is off. If on, it opens
  work views, not OS tools (L-14).
- Keyboard-complete. Mouse and clickable URLs (Grok Build TUI) when the
  terminal supports them.
- Graphical clients (GNOME/KDE/Hyprland) are later restyles of L-18.
  Not in the payload.

**Oracles**

- Fail a dummy unit → notification carries the four fields and opens the
  notify + OS conversation views (HI-14).
- Summon OS opens envelope + memory + OS skills + privileged tools.
- Summon work with the bit off is refused with a reason.
- No key chord is hard-coded into the OS contract.
- `aios brake` stops and masks the proposer; the TUI stays.
- Envelope, snapper, and packages are reachable without scrolling chat.
- Serial fixture: every OS action works with keys only.
- `snapper` rollback of a fixture-failed upgrade boots the previous
  ESP generation and matching `@`; box reaches TTY (L-19).


**Done.** The human can find OS work on a box with no desktop, see our
objects as views, and cannot mix OS privilege into a work turn.

| WP | Title | Delivers |
| --- | --- | --- |
| P7.1 | Summon | TUI command that names OS vs work. |
| P7.2 | Notify | systemd failure → notify view → OS conversation. |
| P7.3 | Brake | `aios brake` in chrome; installer/TUI stays. |
| P7.4 | Surface split | Work summon is a different session (L-14). |
| P7.5 | OS views | L-18 OS catalog. Keyboard-complete. Clickable when possible. |
| P7.6 | Login view | L-17 device-code. URL + code. Token not in transcript. |
| P7.7 | Snapper rollback | Previous ESP generation + matching `@`. Keyboard path. Not a live USB. |


## P8 — Work-runtime (every transferred surface)

**Goal.** If and only if bootstrap recorded yes, the seed becomes a
running user-space runtime whose **every** transferred surface has an
oracle. Copying markdown is not done. A vague “agents work” is not done.

**Depends.** P5, P6, P7.

**Must close before any work unit is enabled**

- Write set (L-15): which directories. Patch the slice drop-in in the
  same commit. `~/src` vs `/srv/aios/src/work-runtime` may not disagree.
- System unit vs user unit: pick one. Update
  `seed/work-runtime/envelope/work-runtime.md` oracles to match. Do not
  ship both.
- How bots is asked: on the OS definition surface, after work-runtime
  is already yes. Never as a third bootstrap question.

This phase does **not** specify Python files. It specifies questions
and oracles. An implementation that cannot fail an oracle below is
incomplete, even if a daemon starts.

**Deliverables**

- Machine goal: `envelope.work-runtime=yes` ⇒
  `/srv/aios/src/work-runtime` exists as its own git repo, units in
  `aios-work.slice`.
- Synthesis from `/srv/aios/seeds/work-runtime` (not GitHub). Bootstrap
  is not finished until that git exists.
- Units named in this plan / envelope before they exist (HI-12).
- Language lock L-01 holds for this tree.
- Disable: envelope patch stops units, leaves git history.

**Oracles (all required for P8 done)**

- Bootstrap no: no work units (HI-15).
- Bootstrap yes, network down: synthesis still completes (HI-17).
- A work-agent pacman attempt still fails (P6).
- Write succeeds inside the declared write set. Write outside it
  without a recorded bridge approval fails. Privileged trees fail
  always (L-15).
- A work turn does not receive privileged tools. An OS turn does not
  run in `aios-work.slice` (L-14).
- Wake injects, in order: work `AGENTS.md`, skills catalog, tools from
  `interfaces.md`, operational notes, envelope bit. No psyche.
- Plain model text is not delivered. Delivery is an explicit send.
  A question ends the turn.
- Following a skill without reading its body this turn fails.
- If a Connector exists for a service, it is used. A token pasted into
  chat fails. Work uid cannot read the OS provider token (L-16, L-17).
- Work TUI views (L-18): `conversation`, `skills`, `connectors`,
  `bridge`, `store`, `login`. Bots, if the second bit is on: `roster`,
  `job`. Sidebar list + transcript + info pane (Grokbot *structure*,
  jobs not selves).
- A Worker has no user-visible voice. Its result is sent on the work
  surface. It cannot enact.
- A routine is cron **or** listeners, never both. It is a file in the
  work store. Disable leaves git.
- Bridge: shell/read/copy on a private path does not run until
  approval. Copy is verbatim, not a mount.
- Work store (notes, skills, routines, connectors) is git in the work
  tree, not `/srv/aios/memory`.
- Bots bit off by default. A roster entry is path + slice + skill, not
  a self. VM define/start/stop/snapshot/destroy is an intent, not
  `virsh` from the slice. Handoff payload is operational (paths,
  oracles, last evidence).

**Done.** Optional user-space agents exist only when asked, cannot
administer the machine, and every transferred InsideMan-shaped surface
is checkable. Skipping a surface because “we will add it later” is
failing this phase.

| WP | Title | Delivers (requirement, not code) |
| --- | --- | --- |
| P8.1 | Synthesis job | Seed → live git, offline, machine goal, HI-15 / HI-17. |
| P8.2 | Write set | L-15 declared. Slice matches. Envelope oracle matches unit type. |
| P8.3 | Surface split | Work summon ≠ OS summon. Mixed-privilege chat fails. |
| P8.4 | Wake and send | Inject order from the seed. Explicit send. Question ends the turn. |
| P8.5 | Skills | Catalog. Read body this turn. OS skills are not a privilege back door. |
| P8.6 | Connectors | MCP preferred. Secrets not in chat. Not the OS key. |
| P8.7 | Workers | No voice. Result sent. Cannot enact. |
| P8.8 | Routines | Cron xor listeners. Persisted. Disable leaves git. |
| P8.9 | Operator bridge | Approval **view**. Verbatim copy, not a mount. |
| P8.10 | Work provider | Own fixture/live. L-17 device-code. Work uid cannot read the OS token. |
| P8.11 | Work store | Notes/skills/routines/connectors as git in the work tree. Store view. |
| P8.12 | Disable | Envelope patch stops units. Git remains. |
| P8.13 | Bots | Second bit. Jobs not selves. VM work is an intent. Handoff schema. |
| P8.14 | Fixture album | One scripted turn per surface above. Each is a vm-work-* oracle. |
| P8.15 | Work views | L-18 work catalog. Keyboard-complete. Same ids a later GUI will use. |
| P8.16 | Bots views | Roster + job card. No avatars. Structure copied; identity refused. |

## P9 — VM harness

**Goal.** The workstation proves the **whole** installer, including every
P8 oracle, in QEMU/KVM. `vm-smoke` is not the product.

**Depends.** P1–P5 for the first useful loop; P1–P8 for the full matrix.
P11 requires the full matrix.

**Must close.** Every coverage-table row has a named target below.

**Deliverables**

- `tests/vm/` — build payload, boot, drive installer via fixture or
  expect, snapshot, reconstruct.
- Exit non-zero on oracle fail. No human as CI.
- Workstation recipe below.
- Fixture files under `tests/vm/fixtures/` for every P8.14 turn.

**Oracles (full matrix)**

- `vm-smoke`: boot → TTY installer → accept administer-only →
  agent+checker running. Operator login exists. No work units.
- `vm-recover`: kill installer, reboot, resume.
- `vm-reconstruct-offline`: rebuild with nic unplugged; envelope
  satisfied.
- `vm-privilege-deny`: work slice cannot pacman, cannot enact, cannot
  read the OS key.
- `vm-brake`: brake masks the proposer; TTY stays.
- `vm-notify`: dummy unit fail → four-field payload on OS surface.
- `vm-work-no`: HI-15. Work summon refused.
- `vm-work-yes`: synthesis from seeds with nic down. Live git exists.
- `vm-work-write-set`: write in set succeeds; write outside without
  approval fails.
- `vm-work-surface`: work turn has no privileged tools; OS turn is not
  in the slice.
- `vm-work-wake`: inject order; explicit send; question ends the turn.
- `vm-work-skill`: follow without reading body fails.
- `vm-work-connector`: token-in-chat fails; OS key unreadable.
- `vm-work-worker`: no voice; result sent; cannot enact.
- `vm-work-routine`: cron xor listeners.
- `vm-work-bridge`: private path blocked until approval.
- `vm-bots-off`: work-runtime yes does not start bots units.
- `vm-bots-job`: with bit on, a job is path+slice+skill; `virsh` from
  the slice fails; a VM start is an intent.
- `vm-tui-keys`: installer + OS actions complete over serial with no
  mouse. Envelope view reachable without chat scroll.
- `vm-login-oob`: live-login fixture prints a URL and user code; no
  token in the transcript; token file not in git. Remotes-veto refuses
  login.
- `vm-boot-seatbelt`: after a fixture `-Syu`, `boot-seatbelt.sh` green;
  both kernels present; last snapper pair has ESP generation;
  `bootctl list` shows previous.
- `vm-no-partial-upgrade`: fixture `pacman -S` without `-Syu` is
  rejected. No mixed userspace.
- `vm-no-bootstrap-syu`: installer journal has no `-Syu` (L-20).
- `vm-stall-pause`: two identical oracle failures pause the goal;
  no third attempt; notify fired; rollback action available.
- `vm-secrets` / `vm-pii`: scans green on the running tree.


**Done.** A failed invariant is a red test on the workstation, not a
conversation. A skipped P8 surface is a red test, not a note.

| WP | Title | Delivers |
| --- | --- | --- |
| P9.1 | QEMU wrapper | `tests/vm/run.sh` + `qemu.sh` with serial and snapshot. |
| P9.2 | OS loop | `vm-smoke`, `vm-recover`, `vm-brake`, `vm-notify`. |
| P9.3 | Reconstruct and deny | `vm-reconstruct-offline`, `vm-privilege-deny`. |
| P9.4 | Work matrix | `vm-work-*` and `vm-bots-*` for every P8 oracle. |
| P9.5 | Scans | `vm-secrets`, `vm-pii`. |
| P9.6 | TUI and login | `vm-tui-keys`, `vm-login-oob`. |
| P9.7 | Seatbelts and stall | `vm-boot-seatbelt`, `vm-no-partial-upgrade`, `vm-no-bootstrap-syu`, `vm-stall-pause`. |


## P10 — Bare metal

**Goal.** The same payload, signed, on real hardware. After the VM
matrix is green. Not a shortcut around P9 or P11.

**Depends.** P9 full matrix green. P11 artifacts exist (the USB is the
signed public image).

**Must close.** LUKS: asked here or listed as a v1 hole. Secure Boot:
asked here or listed as a v1 hole. Hardware-specific commits: how the
checker marks them inapplicable.

**Deliverables**

- USB write + out-of-band signature check.
- Firmware/disk verify from the payload.
- Hardware-specific state commits marked inapplicable on reconstruct.
- No new architecture.

**Oracles**

- Signature verifies on a second machine before boot.
- First surface is still TTY.
- Reconstruct of that metal box satisfies HI-09.
- Operator login and brake still work.
- Work-runtime bit is whatever the envelope still says.

**Done.** A real machine is AIOS. This phase is last on purpose.

| WP | Title | Delivers |
| --- | --- | --- |
| P10.1 | Signed USB procedure | Human-checkable steps; no `curl \| sh`. |
| P10.2 | Metal reconstruct | Skip hardware-specific commits; checker marks them. |
| P10.3 | Metal questions | LUKS / Secure Boot either asked or named as v1 holes. |

## P11 — Public release

**Goal.** The installer is done. A stranger can verify, boot, and use
it. This is the end of the plan, not a marketing pass after a demo.

**Depends.** P9 full matrix green. P1.2 signing in place.

**Must close.** Version scheme. Where the public key lives out of band.
What the known-limitations list contains (must include every v1 hole
row). Whether `main` on this GitHub repo is the tagged release (human
merge).

**Deliverables**

- Versioned signed ISO + `hashes.txt` + minisign signature.
- Operator README: verify, boot, two questions, operator login, brake,
  what yes/no to work-runtime means, how to reconstruct.
- `LICENSE`. Security reporting path (no secrets in the image).
- Known limitations = the v1 holes table, plus anything P9 does not
  pretend to cover.
- Tag that rebuilds the same ISO from this repository.
- Coverage table: every row has a green P9 target.

**Oracles**

- Out-of-band verify instructions work on a clean workstation.
- `vm-smoke` through `vm-pii` all green against the **signed** ISO, not
  an unsigned development image.
- Image `secrets-scan` and `pii-scan` green.
- README does not tell the operator to run `curl | sh`.
- HI-12: no unnamed units in the image.
- Known limitations mentions: no graphical client in the payload,
  no in-place upgrade, bots not implied by work-runtime yes.

**Done.** Public release. Metal may still be pending; the product is
not. Shipping without P8.14 green is not a release.

| WP | Title | Delivers |
| --- | --- | --- |
| P11.1 | Artifacts | Signed ISO, hashes, minisign, version. |
| P11.2 | Operator docs | Verify, boot, questions, brake, reconstruct. |
| P11.3 | Limits | v1 holes published. No silent “later.” |
| P11.4 | Release matrix | Full P9 against the signed image. |

---

## First useful loop (OS only)

The smallest path that is still AIOS, not the product:

1. P1 payload boots a TTY in QEMU.
2. P2 skeleton + local seeds.
3. P3 checker rejects a no-oracle patch.
4. P4 fixture agent proposes a legal envelope-neutral change (e.g. set
   hostname from a compiled clause) and the checker merges it.
5. P5 installer asks the questions, recovers from a kill, accepts
   administer-only, creates the operator login.
6. P9 `vm-smoke` + `vm-recover` green.

## Release loop (the plan is not done before this)

Then, in order: P6 denial, P7 notify and surface split, P8 every
transferred surface, P9 full matrix, P11 signed artifacts. P10 metal
is extra proof after P11.

Do not cut P8 to “seed copied, unit started.” That is how slop and
drift get into a public image.

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
| [bootstrap.md](bootstrap.md) | P1, P2, P5, P9, P10, P11, L-20 |
| [architecture.md](architecture.md) | P2, P3, P4, P6, L-14, L-21 |
| [envelope/hard-invariants.md](envelope/hard-invariants.md) | P3 (oracles), all phases (constraints), HI-06 seatbelts |
| [agent-loop.md](agent-loop.md) | P4, L-20, L-21 |
| [desktop.md](desktop.md) | P7, P8, L-19 rollback |
| [git-standards.md](git-standards.md) | P3, P4 |
| [arch-linux.md](arch-linux.md) | P1, P2, L-19 |
| [software-acquisition.md](software-acquisition.md) | P4, L-19 |
| [memory.md](memory.md) | P4 |
| [grok-build.md](grok-build.md) | P4 loop, L-17, L-20 |
| [seed/work-runtime](../seed/work-runtime/README.md) | P8 |
| [seed/work-runtime-bots](../seed/work-runtime-bots/README.md) | P8.13 |


## What later code is not allowed to invent

If a future patch wants any of the following, it is a docs patch to this
file (and, if needed, the envelope) first:

- A second privileged uid, a language runtime, a display manager, a
  default-on work runtime, a key chord as OS contract, a GitHub fetch
  during reconstruct, a model inside the checker, a `curl | sh` path,
  AUR as the default install, or a merge-to-main by the proposer.
- Mixing OS and work turns in one session (L-14).
- A work-slice write set that disagrees with the declared workspace
  (L-15).
- A work provider that shares the privileged agent's token (L-16).
- Pasting an API key as the live login path (L-17).
- A view that is not in the L-18 catalog, or a GUI that does not share
  those ids.
- A snapper window without a matching ESP generation, or dropping
  `linux-lts` (L-19, HI-06).
- `pacman -S` without a full `-Syu` window, or `-Syu` during Harness A
  (L-20).
- Research (wiki fetch, curl) inside `enact`.
- An always-proposing agent, or a goal that restores self-driving from
  corrupt state (L-21).
- Bots enabled by work-runtime yes.

- Personhood, channels, identity stores, or a second envelope “the
  fleet lives in.”
- Calling P11 done while any P8.14 fixture is missing.
