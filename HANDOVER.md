# AIOS handover — for Grok Build `/design`

This file is the briefing packet for the next agent. It is **not** a
second specification. The specification is the docs listed below, at
the tip of branch `docs/implementation`.

If wording here disagrees with `docs/implementation.md` or
`docs/envelope/hard-invariants.md`, those files win. Raise the
conflict. Do not invent a parallel plan.

## Prompt to paste

After cloning the repo (see [Clone](#clone)), from a Grok Build session
on the workstation:

```
/design a detailed and comprehensive phased plan to implement AIOS.

Read HANDOVER.md first, then every file it marks must-read, then
docs/implementation.md in full.

Constraints:
- Do not invent architecture, phases, daemons, views, or a language.
- Use existing phase IDs P0–P11 and locks L-01–L-21 as the spine.
- Expand each phase into implementable work: files, units, oracles,
  must-close questions, and a done line. Requirements and oracles,
  not a source tree of guessed Python.
- First executable slice is P1 (trusted payload → QEMU TTY). Not P8.
- Work runtime is default off. Do not synthesise it in the ISO.
- No desktop, no AUR as default, no pacman -Syu during bootstrap,
  no curl|sh, no secrets, no PII, no merge to main by the proposer.
- Fetch Arch Wiki this turn for pacstrap, systemd-boot, snapper,
  snap-pac, partial upgrades. Do not rely on model memory.
- The plan is not done until P11 (signed public image + full VM
  matrix). P10 metal is extra proof after that.

Write the plan as a document under docs/ (edit docs/implementation.md
or add docs/design-plan.md linked from it). Do not start coding until
the human approves the design.
```

Stop after the design is written and reviewable. Do not `/execute`
until the human says so.

---

## What this project is

**AI Operating System.** An Arch Linux machine a privileged AI agent
maintains so the human does not administer it. Control surface: a
living envelope of **checkable** acceptability conditions. Enactment:
local git. Validation: a **different process** (the checker), not the
model asked again.

It is not a person, not a new language, not a memory product, not
Grokbot, not Grok Build-on-bare-metal, not NixOS, not Qubes.

The only interesting claim: the proposer has room; the checker has
judgement; the kernel (not a prompt) denies work-slice privilege.

Optional work runtime (InsideMan/Grokbot **structure**, not identity)
is synthesised later if bootstrap records an explicit yes. Default is
administer-only.

## Clone

```
git clone https://github.com/jtwolfe/AIOS.git
cd AIOS
git fetch origin
git checkout docs/implementation
```

**Do not start from `main`.** `main` is the manifesto. The complete
spec, seeds, and this handover live on `docs/implementation`.

Proposer does not merge to `main`. Human merges the docs stack (PRs)
when ready. Implementation work: `feat/<slug>` branched from
`docs/implementation` (or from `main` only after that merge).

No force-push of published history. No secrets. No PII (personal
names, emails, phones, addresses, home-machine identifiers). The
operator is a role.

## Must-read before designing (in this order)

1. [HANDOVER.md](HANDOVER.md) (this file)
2. [AGENTS.md](AGENTS.md) — contract. Non-negotiables. Loop.
3. [docs/envelope/hard-invariants.md](docs/envelope/hard-invariants.md)
   — HI-01…17. The checker loads this file. Quote by id. Do not
   extend it in prose.
4. [docs/implementation.md](docs/implementation.md) — **the plan
   spine**: L-01…L-21, P0–P11, coverage table, HI→oracle map, v1
   holes, units, schemas, QEMU recipe, “what later code is not
   allowed to invent.”
5. [docs/bootstrap.md](docs/bootstrap.md) — Harness A
6. [docs/arch-linux.md](docs/arch-linux.md) — boot seatbelts, brick
7. [docs/agent-loop.md](docs/agent-loop.md) — Harness B
8. [docs/software-acquisition.md](docs/software-acquisition.md)
9. [docs/desktop.md](docs/desktop.md) — L-18 view catalog
10. [docs/grok-build.md](docs/grok-build.md) — login + plan/execute/verify
11. [docs/git-standards.md](docs/git-standards.md)
12. [docs/architecture.md](docs/architecture.md)
13. [seed/work-runtime/README.md](seed/work-runtime/README.md) — only
    to know what P8 must synthesise; do not deploy it in P1

Read the rest of `docs/` if a phase needs it. Do not skip 1–10.

## Two harnesses (do not mix)

| | Harness A | Harness B |
| --- | --- | --- |
| When | Payload / firstboot | After envelope accept |
| Model | Not required | Allowed |
| `-Syu` | **Forbidden** | Full `-Syu` window only, one intent |
| Research | Done when building the ISO | Wiki/man **this turn**, in plan only |
| `enact` | Does not exist yet | Once per accepted plan. Does not curl |
| Recovery | `bootstrap-in-progress` + snapper_pre | Stall pause + TUI rollback |

Mixing them (ISO that syncs the world, or agent that pacmans while
thinking) is how the box bricks.

## Locked decisions (summary)

Full text: [docs/implementation.md](docs/implementation.md) “Locked
decisions.” Changing one is a docs patch first.

| ID | Lock |
| --- | --- |
| L-01 | Python 3 (Arch `python`) + POSIX `sh` oracles. No third-party Python deps in v1. No new language. |
| L-02 | uids: `aios-agent`, `aios-checker`, `aios-work`. Separate. |
| L-03 | Bare git, checker-owned. Agent pushes only `refs/heads/agent/*`. No proposer `main`, no force-push. |
| L-04 | Only root path: `/usr/lib/aios/bin/enact` (full `-Syu` window, snapper, ESP copy, `bootctl`, `aios-*` units). Partial `pacman -S` is not allowlisted. |
| L-05 | `/run/aios/intent.sock`. Agent is the only consumer. Not a shell. |
| L-06 | Work slice: `NoNewPrivileges`, `ProtectSystem=strict`, empty caps. Denial is the kernel. |
| L-07 | ESP vfat `/boot` **not in btrfs**. Rest btrfs `@` `@home` `@srv` `@var_log` `@snapshots`. Snapper of `@` does not include the ESP. |
| L-08 | Provider: `fixture` (VM default) and `live`. Checker imports no provider. |
| L-09 | First surface: TTY TUI. No display manager in the payload. |
| L-10 | minisign. Unsigned images do not leave the workstation. |
| L-11 | Until envelope: UTC, `en_US.UTF-8`, hostname `aios`. |
| L-12 | `aios brake`: stop+mask proposer, freeze enact. Human-only. |
| L-13 | One non-root operator login. No sudo to enact. |
| L-14 | OS surface ≠ work surface. One chat with both rights is a fail. |
| L-15 | Work write set named before any work unit. Slice must match. |
| L-16 | Work token ≠ OS token. Work uid cannot read the OS key. |
| L-17 | Live Grok login is device-code (`grok login --device-auth`). URL + user code on TTY; finish on a phone or other PC. After accept. No pasted API key. |
| L-18 | Named TUI views. GUI later is the same ids. Keyboard-complete. |
| L-19 | Boot seatbelts: `linux` **and** `linux-lts`, `kernel-modules-hook`, `snap-pac`, systemd-boot generations, ESP copy in the same enact window as snapper. TUI rollback, not live USB. Partial upgrades fail. |
| L-20 | Two harnesses (table above). |
| L-21 | Agent always *available*, idle by default. Event-driven + bounded upgrade. Same-gap twice or infra → pause. Corrupt goals restore paused, never self-driving. |

HI-06: snapper without a matching boot image is not a seatbelt. A
partial upgrade is not a seatbelt.

## Phase spine (do not rename)

Copy IDs from `docs/implementation.md`. Expand; do not replace.

| Phase | One-line | Start now? |
| --- | --- | --- |
| P0 | Spec tip is source of truth | Docs already; keep current |
| **P1** | Signed-shaped archiso, minimal Arch, TTY, **no `-Syu`**, both kernels | **Yes — first `/execute`** |
| P2 | `/srv/aios` git, seeds local, snapper + ESP generations | After P1 boots TTY |
| P3 | Checker, no model, HI oracles, git hooks | After P2 |
| P4 | Privileged agent, fixture provider, Harness B loop | After P3 |
| P5 | Conversational installer TUI, two questions, recovery | After P4 |
| P6 | `intent.sock` + work slice denial | After P3/P4 |
| P7 | OS TUI: summon, notify, brake, login, snapper rollback | After P5 |
| P8 | Work runtime **every** transferred surface, iff yes | After P5–P7; still has must-closes |
| P9 | Full QEMU matrix. `vm-smoke` is not the product | Continuous; P11 needs all green |
| P10 | Bare metal, same signed payload | After P9+P11 artifacts |
| P11 | Public release: signed ISO, known limitations = v1 holes | After full P9 |

**First useful loop:** P1–P5 + `vm-smoke` + `vm-recover`.

**Release loop:** that, plus P6–P8, full P9, P11. Metal is extra.

**Public release means P11 green**, including every P8 surface if the
image claims work-runtime. Shipping without P8.14 green is not a
release. Cutting P8 to “seed copied, unit started” is a fail.

## v1 holes — do not implement

| Hole | Status |
| --- | --- |
| Graphical operator client in the payload | Out. TUI is v1. Same view ids later. |
| In-place OS upgrade | Out. Reconstruct from payload + git. |
| Multi-operator | Out. One login. |
| Default LUKS on the VM image | Out. Asked on metal. |
| Paid live API in CI | Out. Fixture covers oracles. |
| Bots enabled by work-runtime yes | Out. Second bit, default off. |
| Personhood, avatars, channels, identity store | Never without envelope rewrite. |

An implementer who “just adds” one is drifting.

## Still open — close at the phase that needs them

Do not invent a silent default. Name the answer in the design, as a
must-close, then lock it in `docs/implementation.md` before code.

| Question | Close in |
| --- | --- |
| Pinned Arch bootstrap tarball URL + sha256 | **P1, first hour** |
| Version string location (`os-release` or equivalent) | P1 |
| Exact live OS token path (mode, not readable by `aios-work`) | P4 |
| When a pattern earns a `SKILL.md` | P4 |
| Operator username: asked vs derived from purpose | P5 |
| How summon names the surface (`aios` vs `aios work`) | P7 |
| **System unit vs user unit for work runtime — pick one** | **Before any P8 unit** |
| L-15 write set vs `~/src` — must agree with the slice | P8.2 |
| How bots is asked (OS surface, after work-runtime already yes) | P8.13 |
| LUKS / Secure Boot: asked or listed as hole | P10 |
| Version scheme; where the public key lives out of band | P11 |

P8 “system vs user unit” is the only remaining product hole that
would force a retrofit. It does **not** block P1–P5. Do not
synthesise work-runtime “while we are in the ISO.”

## What a passing design looks like

The `/design` output must, for **every** phase P1–P11:

1. Restate goal, depends, done line (from the spec).
2. List **must-close** questions and the chosen answer or “close when
   this phase starts; here are the options.”
3. Name **files and units** already listed in “Future code trees” /
   “Units and paths.” Do not add unnamed daemons (HI-12).
4. Name **oracles** as fail-closed commands/scripts (`vm-*` targets
   included). A story is not an oracle.
5. Cover every row of the coverage table by P9. If a row has no
   `vm-*` target, the design is incomplete.
6. Call out Harness A vs B, L-19 seatbelts, L-21 idle/stall where
   they apply.
7. Sequence work packages so P1 is independently bootable in QEMU
   without P8.

Include a “first `/execute` session” section that is **only P1**:

- Pin bootstrap tarball
- `payload/profile/packages.x86_64`: `base`, `linux`, `linux-lts`,
  `linux-firmware`, `btrfs-progs`, `snapper`, `snap-pac`,
  `kernel-modules-hook`, `git`, `python`, `pacman`, `systemd`,
  `etckeeper`, `minisign`, `iwd`, `sudo`; `openssh` present and
  **disabled**; no DE
- Partition L-07, systemd-boot, both kernels, no `-Syu` in firstboot
  journal
- TTY autologin to installer stub
- Stop when: QEMU serial reaches a TTY installer, layout matches,
  `linux` and `linux-lts` present, journal has no `-Syu`

Fetch, this turn, at least:

- https://wiki.archlinux.org/title/Archiso
- https://wiki.archlinux.org/title/Systemd-boot
- https://wiki.archlinux.org/title/Snapper
- https://wiki.archlinux.org/title/Pacman (partial upgrades)
- https://wiki.archlinux.org/title/System_maintenance

## Workstation / QEMU

Nested KVM is enough for P1–P9. Serial, not a graphical viewer.
Floor invocation is in `docs/implementation.md` “Workstation recipe.”
32G qcow2, not committed. Offline reconstruct: `-nic none`.

Live Grok login is **not** required for a green mechanical test.
Fixture covers the matrix. Device-code (L-17) is after envelope
accept, on a human box.

## Quality bar

Done means shown. The checker re-runs oracles without the model.
`true`, `test -f`, and `systemctl is-active` on a unit the agent just
started are not enough for purpose-level claims.

Human is not CI (HI-08). Agent is not an always-proposing hobbyist
(L-21).

No `curl | sh`. No unsigned root install. No `/usr` mutation outside
pacman. No secrets in git. No PII in git.

## What you are forbidden to invent

From `docs/implementation.md` plus this handover:

- A second privileged uid, a language runtime, a display manager, a
  default-on work runtime, a key chord as OS contract, a GitHub fetch
  during reconstruct, a model inside the checker, AUR as default, a
  proposer merge to `main`
- Mixing OS and work turns (L-14)
- Snapper without matching ESP generation; dropping `linux-lts`
- `pacman -S` without a full `-Syu` window; `-Syu` in Harness A
- Wiki fetch / curl inside `enact`
- Always-proposing agent; self-driving restore from corrupt goals
- Views not in L-18; a GUI that does not share those ids
- Bots enabled by work-runtime yes
- Personhood, channels, identity stores
- Calling P11 done while any P8.14 fixture is missing
- A parallel phase list (P1a, “MVP ISO”, “week 1 sprint” as a
  substitute for P1–P11)

If the design wants any of those, it is a docs patch first, then
human approval — not a surprise in code.

## Seeds already in tree

- `seed/work-runtime/` — reconstructible app the OS agent synthesises
  **if** bootstrap yes. Not a live deployment. Not privileged.
- `seed/work-runtime-bots/` — optional fleet extension. Second
  envelope bit. Default off. Jobs are path + slice + skill, not selves.

Payload copies these into `/srv/aios/seeds` so reconstruct does not
need GitHub (HI-17).

## After the design is approved

1. Human reviews the design document.
2. Human says `/execute` (or equivalent) for **P1 only**.
3. Next sessions are new plans: P2, then P3, then P4. Do not batch
   the OS loop and the work runtime in one execute.
4. Keep `docs/implementation.md` current if a must-close is answered.
   That answer is a lock, not a comment in code.
