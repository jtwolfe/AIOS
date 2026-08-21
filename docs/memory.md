# Memory

A natural, unbounded store of interactions with both the user and the
system. The history of the relationship and the history of the machine are
the same store viewed from two angles.

## Design principles

- **Verbatim primary storage** of significant exchanges and system actions.
  Summaries are derived, never the only record.
- **Attribution.** Every remembered act points at a human utterance, an
  envelope clause, or a prior system event.
- **No silent erasure.** Decisions can be superseded. The old decision
  remains, marked with temporal validity.
- **Local first.** The store lives on the machine, in git. Remote copies
  are optional mirrors.

Git is the memory of code and of privileged enactment. Interaction memory
is a sibling store: same discipline (history, attribution,
reconstructibility), different grain (conversations, not only diffs).

## Layered access

Unbounded does not mean “dump everything into the prompt.” Access is
layered so the agent stays cheap on the hot path and deep when it must be.

- **Always-on core** — the current envelope, the open task, recent
  exchanges, and the active skill list. Small enough to load every turn.
- **Scoped retrieval** — pull related exchanges, prior diffs, and skills by
  task, path, or envelope clause.
- **Deep search** — full-text and structural search over the store when the
  agent does not already know what it needs.

This is the same idea as Grok Build skills: depth lives in files loaded on
demand. The core contract stays short. Agents that inline the entire
history on every turn are defective.

## Skills from history

Skills are crystallized, reusable patterns born from successful interaction
history. They are not a prompt-time invention.

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
the system pretending the previous mind never existed.
