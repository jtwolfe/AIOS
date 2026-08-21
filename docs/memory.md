# Memory

Operational history of the machine and of the human’s intent for it. Stored
so the agent can administer this box over time — not so it can reminisce,
and not as a product of its own.

## Design principles

- **Verbatim primary storage** of significant exchanges and system actions.
  Summaries are derived, never the only record.
- **The model does not decide what is worth keeping.** Discard is an
  explicit, attributed act — not a silent judgement about “what matters.”
- **Attribution.** Every remembered act points at a human utterance, an
  envelope clause, a machine goal, or a prior system event.
- **No silent erasure.** Decisions can be superseded. The old decision
  remains, marked with temporal validity.
- **Local first.** The store lives on the machine, in git. Remote copies
  are optional mirrors.

Git is the memory of code and of privileged enactment. Interaction memory
is a sibling store: same discipline (history, attribution,
reconstructibility), different grain (conversations and system actions, not
only diffs). Neither store is a mind.

## Findable by concern

History that cannot be found is not operational. Index by the machine’s
concerns, not by a personality or a palace metaphor.

- **Concerns** — packages, units, network, envelope clauses, projects,
  machine goals.
- **Moments** — one complete do-loop of work (context + tool calls +
  results until stop). A logging grain for system actions, not an episode of
  a life.
- Hierarchical rooms (project / subsystem / topic) are allowed when they
  make retrieval cheaper. They are a filing system, not a product story.

The history of what the human asked and the history of what the machine did
are the same store viewed from two angles. That is administration, not
companionship.

## Layered access

Unbounded does not mean “dump everything into the prompt.” Access is
layered so the agent stays cheap on the hot path and deep when it must be.

- **Always-on core** — the current envelope, open machine goals, recent
  exchanges, and the active skill list. Small enough to load every turn.
- **Scoped retrieval** — pull related exchanges, prior diffs, and skills by
  task, path, concern, or envelope clause.
- **Deep search** — full-text and structural search over the store when the
  agent does not already know what it needs.

This is the same idea as Grok Build skills: depth lives in files loaded on
demand. The core contract stays short. Agents that inline the entire
history on every turn are defective.

## Skills from history

Skills are crystallized, reusable playbooks born from successful work. They
are not a prompt-time invention and not a personality trait.

- A skill is a `SKILL.md` (and optional `references/`) in
  `/srv/aios/skills`.
- It names triggers, the files to open, and the quality bar for that class
  of work.
- Promotion from a successful episode to a skill is an envelope-aware git
  change, reviewed by the checker for overlap and contradiction.
- Nested project `AGENTS.md` files outrank a general skill inside that
  project tree. Direct human instruction outranks both.

Do not invent a parallel skill system. If a pattern is worth repeating, it
becomes a file in the skills repository.

## Temporal validity

Preferences change. Machines change. Memory that cannot represent “this was
true then” becomes a source of stubborn errors.

- Every condition and every remembered decision has an interval:
  effective-from, optional effective-until.
- Supersession is a new record pointing at the old one, not an edit in
  place.
- The checker evaluates the envelope as of now, not as of the oldest
  remembered wish.

The point is corrigibility in time: the human can change their mind without
the system pretending the previous instruction never existed.
