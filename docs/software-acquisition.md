# Software acquisition

There is no classical package manager as the primary path. New programs and
capabilities are materialised by the AI itself: synthesised or acquired,
validated against the envelope, installed as git history. The install
mechanism is the AI.

## Three acquisition paths

The agent chooses the cheapest path that still satisfies the envelope. It
does not synthesise a text editor if pacman already has one, and it does
not install a sprawling stack for a one-line ask.

1. **System package** — official Arch repos via pacman, recorded in the
   system-intent repository.
2. **Project dependency** — language lockfiles inside the project that
   needs them.
3. **Synthesis** — the agent writes a program into `/srv/aios/src/<name>`,
   with tests as oracles, and installs only after the checker passes.

AUR is a variant of path one, with extra isolation. It is never the
default when an official package exists.

**Rule.** Grow complexity only when the basic loop is proven useful. A new
capability that requires three new daemons is a smell unless the envelope
asked for those daemons.

## System packages

- Prefer official repositories. Pin the reason in the state commit, not a
  mystery flag.
- Explicit packages only in `packages.txt` (`pacman -Qqe`). Dependencies
  are pacman’s problem.
- Removals are first-class. An unused privileged package is a proposed
  uninstall, not a souvenir.
- Updates are a separate intent: one branch, one snapper **and ESP**
  window, one review. Not mixed with feature work.
- Arch only supports **full system upgrades**. A privileged `pacman -S`
  (or `IgnorePkg` that leaves the rest moving) is a partial upgrade and
  fails `no-partial-upgrade.sh` (HI-06). Install a package only as part
  of a `-Syu` window, or refuse.
- `linux` and `linux-lts` both stay explicit in `packages.txt`. Removing
  either is rejected. A sysupgrade that does not leave linux-lts
  bootable is rejected.
- Bootstrap (Harness A) does **not** `-Syu`. The ISO’s package set is
  the machine until envelope accept.

The checker re-runs `pacman -Qqe` and diffs it against
`state/packages.txt`. Drift is a failed check, not a warning the agent can
dismiss. It also re-runs `boot-seatbelt.sh`: both kernels present,
modules dir for the running kernel exists, last snapper pair has a
matching ESP generation.


## Project dependencies

- Node, Python, Rust, Go — each project owns its lockfile, and the lockfile
  is committed.
- No host-global `pip install`, `npm i -g`, or cargo installs into `$HOME`
  as a substitute for a project.
- Toolchains themselves (rustup, uv, npm) are either pacman packages or
  declared in the project README with a bootstrap script in git.
- Native modules that need compile flags are documented in the project, not
  discovered next week as a broken box.

## Synthesised programs

When the agent writes a program, it is a professional software project from
the first commit. Code is emitted only when the oracles pass — the same
closed loop as any other privileged change.

- A repository of its own, with `.gitignore`, tests, and a README that a
  stranger could run.
- Prefer editing existing files inside an existing project over starting a
  new one.
- Do not add error handling, fallbacks, feature flags, or abstractions for
  situations that cannot happen. The right amount of complexity is what the
  task requires.
- Do not gold-plate. Do not skip the finish line. If it cannot be run, it
  is not done.
- Installation of a synthesised program is a unit file or a path entry
  recorded in the state repo, not a copy into `/usr/local` by hand.

Inspired techniques (intent loops, memory systems, agent skills,
reconstructible systems) are reference points, not a binding architecture
and not a reason to ship a new language on the box. The envelope decides
what is allowed to land.
