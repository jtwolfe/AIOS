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

**Constraint.** The agent must not disable snapper, etckeeper, or the
checker in order to make a change easier. Those are hard invariants of the
substrate.

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
