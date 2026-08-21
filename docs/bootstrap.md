# Bootstrap

A minimal trusted payload verifies the target machine and drops the human
into a conversational interface that is the installer. High-level intent
becomes the first envelope. The AI then constructs the concrete system
inside it.

## Trusted payload

Bootstrap is the one moment the system cannot yet check itself. The payload
therefore stays small, signed, and boring.

- Shape: an `archiso`-based USB or a verified network image.
- It verifies firmware, disks, and a checksum of itself against a published
  signature the human can check out of band.
- It installs a minimal Arch: btrfs, snapper, systemd, git, pacman, a
  network, and the privileged agent plus checker at known hashes.
- It does not install a desktop, a theme, or a development zoo. Those are
  envelope-driven later.

**Constraint.** The payload is allowed to be less free than the running
system. Room comes after a checkable root of trust exists.

## Conversational installer

After the minimal root is up, the human is not handed a list of packages to
tick. They are handed a conversation.

- “What is this machine for?” is a first-class question. The answer becomes
  derived conditions, not a hostname only.
- “Do you want to work with AI agents on this system?” is the other
  first-class question. No leaves the OS agent as the only agent. Yes compiles
  a work-runtime clause and the privileged agent synthesises the work runtime
  from [`seed/work-runtime`](../seed/work-runtime/README.md). See
  [docs/desktop.md](desktop.md).
- Vetoes are collected early: what the agent must never do, which networks
  it may join, whether it may speak to remotes.
- The installer shows the compiled envelope in plain language and waits for
  acceptance before privileged enactment begins.

Skipping the work-runtime question is not a yes. Default is administer-only.

This is the Grok Build idea that the human should not be asked to operate
the sandbox plumbing. They see a product surface. The agent sees disks,
unit files, and git.

## First envelope

The first envelope always contains, at minimum, the hard invariants in the
reference: git-backed enactment, proposer/checker split, snapper, no
`curl | sh`, human emergency brake, local source of truth. The
conversational answers add derived conditions on top — purpose, vetoes, and
the work-runtime bit.

Only then does the agent propose the rest: users, ssh, editor, language
toolchains, the shape of `/srv/aios`, and if opted in, synthesis of the work
runtime under `/srv/aios/src/work-runtime`. Each proposal is a branch. The
first day is not a blank cheque.

## Reconstruct from history

Bootstrap is also how a machine is rebuilt. A lost disk is not a lost
operating system if the remotes of `/srv/aios` and the envelope survive.

1. Run the trusted payload on new hardware.
2. Clone the local-of-record remotes.
3. Check out the envelope at the desired commit. The checker verifies it
   against meta-rules.
4. Replay system-intent from `state/` with snapper windows, skipping
   hardware-specific commits the checker marks inapplicable.
5. Resume the conversational surface. Memory is the same store. The
   work-runtime bit is whatever the envelope still says.

If that replay cannot produce a machine that satisfies the envelope, the
unreplayable step is a bug in enactment, not a reason to keep undocumented
side state.
