# Desktop

People do things on computers. The shell is a client of the OS agent from
day one. A work runtime for user tasks is optional, opted into at
bootstrap, and never privileged.

## Three authorities

Do not collapse these. The OS agent administers the machine. The desktop
summons and notifies. User-work agents, if enabled, do user work. Same box.
Different rights.

1. **Operator surface** — human authority, private paths, emergency brake.
   The shell summons and notifies. Nothing here is privileged.
2. **Managed substrate** — the OS agent, envelope, git, checker, and
   snapper. System mutation happens only here.
3. **Work runtime** — optional. User tasks on the managed machine. Files
   intents; never enacts privileged change.

**Rule.** System mutation — packages, units, envelope, network policy — is
only the OS agent, under git, checker, and snapper. A work agent that needs
a package files an intent. It does not pacman.

## Shell as client

Integrate the desktop from bootstrap, not as a later plugin. The
Hyprland-shaped shell (command palette, apps-only palette, notifications) is
how the human finds things and is told when the machine fails. It has no
privilege of its own.

- **Unified palette** — apps and OS intents in one box. Typical chord:
  Super + Space.
- **Apps-only palette** — Super + Alt + Space, if you want that split.
- **Definition surface** — a first-class window, summonable from the
  palette, a keybind, or a notification action.

OS intents in the palette are not a second chatbot. They open the definition
surface with the same wake contract the privileged agent already uses:
envelope, operational memory, skills, tools, machine goals.

Typical OS intents: explain a failed unit, pending envelope changes, last
snapper window, open the definition surface.

## Failure handoff

A process crash, a unit entering failed, a pacman transaction abort, disk or
memory past envelope thresholds, a checker rejection — these are
system-scoped. The toast does not open a random coding CLI. It hands a
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
synthesises any other program: branch, oracles, checker, git. The runtime is
integral to the project as a seed, not as a second operating system.

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

Isolation for experimental enactment is a git worktree or btrfs subvolume of
system-intent, plus a systemd slice for CPU and memory. Snapper is the
privileged-change seatbelt, not the agent sandbox.

## What AIOS builds

The seed is the reconstructible application. On a yes at bootstrap, the OS
agent treats it as a synthesis job under `/srv/aios/src/work-runtime`. The
seed is not a live deployment and not a roster of people.

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
```

After synthesis the live tree is a git repository like any other under
`/srv/aios/src`. Updates to the runtime are ordinary proposals. Disabling it
is an envelope patch: stop the user units, leave the git history.
