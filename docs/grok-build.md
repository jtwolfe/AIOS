# Grok Build

Grok Build is a sandbox contract for shipping software with an agent: a reconstructible workspace, a written contract, skills on disk, and mechanical QA. AIOS applies that contract to a whole machine — still an operating system, still not a person.

These are not metaphors tacked on after the fact. They are the same discipline at two scales. Where the mapping is inexact, AIOS keeps the stricter of the two.

## Concept mapping

Grok Build maps onto AIOS as follows.

- Isolated workspace → Arch machine with btrfs snapshots and chroots
- AGENTS.md as the contract → envelope plus nested AGENTS.md in every repo
- Skills loaded on demand → SKILL.md playbooks crystallised from work
- startup.sh reconstruct contract → git history plus envelope reconstruct the box
- Mechanical QA → independent checker process; oracles, not a second model opinion
- Human never runs commands for QA → agent verifies; human is authority and brake
- Do not invent parallel rules → do not invent a parallel envelope, skill tree, or language
- Prefer edit over create → prefer edit over create; no souvenir files
- Triage before scaffolding → not every utterance is an install
- Auth and data off until needed → grow complexity only when the loop is proven
- Non-overlapping parallel ownership → proposer and checker; split surfaces
- Always-on teammate with its own computer → optional work runtime on the managed machine; OS agent stays privileged
- Quality bar is non-negotiable → conditions are checkable, not advisory
- Browser / device-code login → live Grok login is `grok login --device-auth` on a TTY (L-17)
- Fullscreen mouse TUI, clickable URLs → AIOS TUI (L-18); GUI later is the same views
- Plan mode / Goal mode (Design → Execute → Verify, stall pause) → Harness B (L-20, L-21)


The work runtime, when synthesised from `seed/work-runtime`, is a Grok Build-shaped application *on* the machine. It is not the machine.

## Plan, execute, verify

Grok Build’s `/plan` gates file edits until the human approves the plan
file. Goal mode is a state machine: Planning → Executing → Verify
(skeptic panel) → stall pause. Unknown or corrupt state restores
**paused**, never self-driving. Infra errors pause. Same-gap fingerprints
auto-pause. Research happens while planning cannot edit.

AIOS copies that *loop*, not the product, as Harness B
([agent-loop.md](agent-loop.md)):

- The proposal (intent + oracles + wiki citations + rollback) is the
  only write until accept. No pacman during “thinking.”
- Execute is `enact` once, one snapper+ESP window.
- Verify is the checker plus canned seatbelt scripts, not a second model.
- Stall pauses and offers TUI rollback (L-19, L-21).

Harness A (the payload) does not run this loop. It is boring on purpose
([bootstrap.md](bootstrap.md)).

## AGENTS.md as contract


Every repository the agent may touch carries an `AGENTS.md` (or nested files deeper in the tree). Scope is the directory tree that contains the file. Deeper files win on conflict. Direct human instruction wins over all of them, subject to hard invariants.

The machine-wide file at `/srv/aios/AGENTS.md` is the analogue of the App Builder workspace contract: what this is, the loop, non-negotiables, and pointers to skills. Agents do not invent a second handbook in the prompt.

This GitHub repository carries the same file so that any agent working on AIOS documentation or code — Grok Build included — is bound by it.

## Skills on disk

Depth lives in files. The core contract stays short. When a class of work recurs (git enactment, pacman transactions, envelope patches, UI, tests), it earns a `SKILL.md` with triggers and references. Agents open the skill *before* building.

Skills are not allowed to contradict the envelope. Promotion of a skill is a git change in `/srv/aios/skills`, reviewed by the checker for overlap.

## Quality bar

Done means shown. The Grok Build bar — production build, typecheck, real render, clean console, both viewports — becomes, on a machine:

- Checker predicates all green for the affected layer.
- Declared package list matches the live explicit set.
- The new git history replays on a clean worktree.
- Snapper pre/post exists for privileged system changes.
- The conversational surface can explain the change from operational history without inventing a reason.

A brand warning in Grok Build is treated as not-done. An envelope warning in AIOS is treated the same. Advisory theatre is how corrigibility dies.

## Live login (device-code)

Grok Build’s default is to open a browser at `auth.x.ai`. Headless and
remote sessions use `grok login --device-auth` (alias `--device-code`):
the terminal prints a verification URL and a user code; the human opens
that URL on **any device**, completes sign-in, and the process polls until
confirmed. Tokens land in a `0600` file, not in the transcript. The TUI
turns the first `https://` URL into a clickable sign-in link.

AIOS has no local browser in v1. Live provider **is** that device-code
path (L-17):

1. After envelope accept, and only if remotes are not vetoed.
2. TUI `login` view shows the URL and user code (clickable when the
   terminal allows; always printed as text for a phone or other PC).
3. Human finishes in a browser elsewhere. The box polls.
4. Token file `0600`. OS agent and work runtime have **different** files
   (L-16). Not in git. `secrets-scan` fails if a token hits a repo.
5. The agent never asks for a password or a pasted API key in chat.
   (Grokbot/InsideMan: connect card; operator signs in; agent never sees
   the password.)

Fixture remains the VM default. CI never requires this flow.

## TUI

Grok Build runs as a fullscreen, mouse-interactive TUI. AIOS v1 is the
same class of client, not a readline REPL.

- Named views in [desktop.md](desktop.md) (L-18).
- Mouse and clickable elements when the terminal supports them.
- Keyboard path for every action (serial fixtures, dumb TTY).
- A later GUI uses the same view ids and actions. Visual similarity,
  identical functionality. The graphical-client hole is “not in the
  payload,” not “undefined screens.”

