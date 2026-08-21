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
- Quality bar is non-negotiable → conditions are checkable, not advisory

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
