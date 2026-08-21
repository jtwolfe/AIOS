# Desktop

People do things on computers. The operator client of the OS agent is
present from day one. A work runtime for user tasks is optional, opted into
at bootstrap, and never privileged.

**Nothing here is DE- or WM-shaped.** Hyprland, GNOME, KDE, a pure TTY, or a
tmux/screen session are all valid *operator clients* of the same contracts.
The envelope chooses which client is installed. The definition surface and
the work runtime do not care.

## Three authorities

Do not collapse these. The OS agent administers the machine. The operator
client summons and notifies. User-work agents, if enabled, do user work. Same
box. Different rights.

1. **Operator** — human authority, private paths, emergency brake. Reached
   through the operator client, which summons and notifies. Nothing here is
   privileged.
2. **Managed substrate** — the OS agent, envelope, git, checker, and
   snapper. System mutation happens only here.
3. **Work runtime** — optional. User tasks on the managed machine. Files
   intents; never enacts privileged change.

**Rule.** System mutation — packages, units, envelope, network policy — is
only the OS agent, under git, checker, and snapper. A work agent that needs
a package files an intent on `/run/aios/intent.sock`. It does not pacman.
The kernel denies it if it tries (HI-13, HI-16).

## Operator client

Integrate an operator client from bootstrap, not as a later plugin. Until a
graphical client is installed, that client is the TTY definition surface the
payload already started. The client is how the human finds OS intents and is
told when the machine fails. It has no privilege of its own.

The contracts are transport-agnostic:

- **Summon** — open the definition surface, or list OS intents, from whatever
  input model the installed client provides (keybind, command palette, menu,
  TTY command, tmux binding).
- **Notify** — surface system-scoped failure with a structured payload the
  human can accept into the definition surface.
- **Definition surface** — a first-class session: GUI window, TTY, tmux pane,
  or SSH session. Natural language. Same wake contract regardless of transport.

OS intents are not a second chatbot. They open the definition surface with the
same wake contract the privileged agent already uses: envelope, operational
memory, skills, tools, machine goals.

Typical OS intents: explain a failed unit, pending envelope changes, last
snapper window, open the definition surface.

Key chords, palettes, and notification daemons belong to the installed client
(GNOME, KDE, Hyprland, i3, plain shell). Document them in the client’s own
files. Do not hard-code them into the OS contract.

## Failure handoff

A process crash, a unit entering failed, a pacman transaction abort, disk or
memory past envelope thresholds, a checker rejection — these are
system-scoped. The notification does not open a random coding CLI. It hands a
structured payload to the OS agent.

- Unit name or executable
- Journal slice since last healthy
- Last related state commit and snapper id
- Matching envelope clause and skill path, if any

A failed test in a project is not system-scoped. If the work runtime is
enabled, that failure may wake a work agent. If it is not, it is ordinary
user software and stays out of the OS loop.

## Work runtime

Optional. Asked at bootstrap: *do you want to work with AI agents on this
system?* No is a complete answer. The machine is still AIOS.

When yes, the privileged agent synthesises a user-space application from
[`seed/work-runtime`](../seed/work-runtime/README.md) — the same way it
synthesises any other program: branch, oracles, checker, git. Completing that
synthesis is a machine goal: bootstrap is not done until the live tree exists
under `/srv/aios/src/work-runtime` as its own git repository. The runtime is
integral to the project as a seed, not as a second operating system. It is
not tied to a desktop environment.

Machinery worth transferring from a Grok Bot-class product, and nothing else:

- **Wake inject** — each turn gets context: skills catalog, tools,
  operational notes. No psyche, no avatar as identity.
- **Skills** — read the `SKILL.md` body in this turn before following it.
- **Connectors** — MCP preferred; browser is fallback.
- **Workers** — background actors with no user-visible voice. Results are
  sent, not only acknowledged.
- **Operator bridge** — shell, read, and copy onto private human paths only
  after approval.
- **Routines** — cron or event listeners, never both on one standing order.
  User standing orders, not machine goals.

Do not transfer personhood, avatars as identity, social channels as the
kernel, or a second cloud computer as the product. Those are a teammate app.
AIOS is an operating system that may host user-work agents.

For multi-agent fleets (home-server workers maintaining VMs, long-running
rosters, inter-agent handoff without a human in every turn), see the optional
extension [`seed/work-runtime-bots`](../seed/work-runtime-bots/README.md).
Core work-runtime stays lean. Bots is opt-in on top of it, still unprivileged.

Isolation for experimental enactment is a git worktree or btrfs subvolume of
system-intent, plus a systemd slice for CPU and memory. Snapper is the
privileged-change seatbelt, not the agent sandbox.

## What AIOS builds

The seed is the reconstructible application. On a yes at bootstrap, the OS
agent treats it as a synthesis job under `/srv/aios/src/work-runtime`. The
seed is not a live deployment and not a roster of people. The trusted payload
has already materialised the seed trees into `/srv/aios/seeds`, so synthesis
does not fetch GitHub.

```
seed/work-runtime/
  AGENTS.md                 # contract: not privileged
  README.md
  envelope/work-runtime.md  # clause compiled from bootstrap
  boundaries/
    invariants.md
    interfaces.md
  skills/
    wake.md
    handoff.md
    bridge.md
    connectors.md

seed/work-runtime-bots/     # optional extension; multi-agent fleets
  AGENTS.md
  README.md
  boundaries/
    invariants.md
  skills/
    roster.md
    fleet.md
```

After synthesis the live tree is a git repository like any other under
`/srv/aios/src`. Updates to the runtime are ordinary proposals. Disabling it
is an envelope patch: stop the user units, leave the git history.
