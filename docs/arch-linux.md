# Arch Linux

Start from a thin classical substrate. Arch is the chosen base: rolling,
documented, scriptable, and reconstructible from a package list plus git.
The kernel is not rewritten on day one.

## Why Arch

The substrate has to get out of the way without becoming a mystery. Arch is
chosen because it is already close to what an agent can reason about:

- A small, explicit package manager (`pacman`) with a complete transaction
  log.
- Rolling releases, so the machine does not rot behind LTS freezes while the
  agent keeps current skills.
- The Arch Wiki as a high-quality, checkable corpus for how the system
  actually works.
- systemd as the service model for the privileged agent, the checker, and
  user-level helpers.
- A culture of reconstructing a box from a package list, dotfiles, and a
  handful of unit files — which is exactly AIOS’s posture.

Arch is the substrate, not the identity. AIOS is not “an Arch installer with
a chatbot.” The envelope, the split checker, and git-backed enactment are
the operating system. Arch is what they stand on.

## What the substrate provides

- **pacman** for official packages. Every privileged transaction is mirrored
  as a commit in `/srv/aios/state`.
- **AUR via isolated chroots** (`extra-x86_64-build` / `makechrootpkg`),
  never a raw `makepkg` against the live root as the default path.
- **systemd** user and system units, stored in git, installed as declared
  files — not edited ad hoc in `/etc`.
- **archiso** as the shape of the trusted bootstrap payload.
- **etckeeper** so `/etc` has history.

## Isolation and rollback

Room for the agent requires a mechanical undo. The default storage layout is
btrfs with snapper timelines and pre-enactment snapshots.

```sh
# Before any privileged system enactment:
snapper create --type pre --description "pre ${INTENT_SLUG}"

# After a successful merge to the system-intent repo:
snapper create --type post --pre-number "$PRE" --description "post ${INTENT_SLUG}"
```

Untrusted builds and experiments run in systemd-nspawn containers or
dedicated chroots, not on the host. The emergency brake is a snapper
rollback plus a git revert of the corresponding state commit — two
mechanical operations, not a conversation.

Snapper is the seatbelt around privileged system enactment, not a parallel
“agent PC.” Experimental work sits in a git worktree or a btrfs subvolume of
system-intent, under a systemd slice that caps CPU and memory. Promote to live
only after the checker passes and a snapper window exists.

**Constraint.** The agent must not disable snapper, etckeeper, the
checker, or the boot seatbelts in order to make a change easier
(HI-06). Those are hard invariants of the substrate.

## Flexibility, not Nix rigidity

Arch is chosen for room: pacman, systemd, no vendor policy language.
That is not a licence to `-Syu` whenever the model is bored, and it is
not NixOS or Qubes. The substrate stays Arch. The *operational*
contract is how the box stays unbricked without becoming a pure
function or a VM per window.

Official Arch policy is law for this substrate, not flavour:

- **Partial upgrades are unsupported.** `pacman -S foo` on a stale sync
  is how ABI breaks. The agent either sysupgrades in one snapper+ESP
  window or refuses and says why. `IgnorePkg` of `linux` while the rest
  moves is the same class of brick.
- Updates are **one intent**, never mixed with “install a thing”
  ([software-acquisition.md](software-acquisition.md)).
- The Arch Wiki and man pages are the checkable corpus. For any change
  that touches pacman, systemd, mkinitcpio, fstab, or the bootloader,
  the plan fetches those pages **this turn**. Model memory of how
  snapper rollback works is not evidence.

## The brick this disk layout actually has

The VM default (L-07) is ESP vfat `/boot`, rest btrfs (`@`, `@home`,
`@srv`, `@var_log`, `@snapshots`). Snapper snapshots `@`. It does
**not** snapshot the ESP. Nested `@home` / `@srv` are **not** in a
snapshot of `@`. Arch Wiki is explicit on both points.

So the failure that kills a “human does not administer” box is:

1. A transaction writes a new kernel/initramfs to the ESP.
2. `@` is later rolled back (or left mixed) without a matching boot
   image, or the ESP moves without `@`.
3. Next reboot: kernel/modules mismatch. Snapper from a running system
   cannot help. Wiki’s rollback path is a live USB.

Snapper-alone on this layout is a **false seatbelt**. HI-06 treats that
as a failed check.

## Boot seatbelts (L-19)

Keep Arch. Steal operational habits, not a new OS:

| Habit | Why it stops bricks |
| --- | --- |
| Always `linux` **and** `linux-lts` in `packages.txt` | Firmware boot menu still has a last-known-good kernel |
| `kernel-modules-hook` | `-Syu` does not instantly kill the live kernel |
| `snap-pac` pre/post on every pacman transaction | A pre image exists even if the agent dies mid-transaction |
| systemd-boot generations: current `linux`, `linux-lts`, previous ESP copy | Rollback is a boot menu + TUI action, not a live USB |
| ESP/UKI copy in the **same** `enact` window as snapper post | A snapper id that has no matching boot image fails `boot-seatbelt.sh` |
| Full `-Syu` only, one intent | Partial upgrades are unsupported |

Bootloader for v1 is **systemd-boot** (in `systemd`; no extra package,
no AUR Limine helper, no grub-btrfs). Entries: current linux,
linux-lts, previous generation. The TUI `snapper` view’s rollback
action selects that previous generation and the matching `@` snapshot.

Untrusted builds still run in nspawn/chroots. The emergency brake is
still stop-proposer plus freeze `enact`. Rollback of a failed upgrade
is the TUI action, not a conversation about `btrfs subvolume`.

## Tracking the live system


Reconstructibility is a daily property, not a disaster-recovery brochure.

- `/var/log/pacman.log` — native transaction history.
- A declared package list committed in `state/packages.txt` after every
  install or removal (`pacman -Qqe` for explicit packages).
- Lockfiles for every language toolchain in the project that owns them.
  Never a global `pip install` into the host.
- Hostname, users, and ssh policy as files in git, applied by the agent
  after the checker passes.

A new box of the same class should be stand-up-able from: Arch bootstrap
media, the envelope, and the git remotes of `/srv/aios`. Anything that
cannot survive that test is undeclared state and is treated as a defect.
