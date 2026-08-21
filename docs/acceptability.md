# Acceptability

Checkable acceptability conditions are the primary control surface. The AI
is free to propose almost any change as long as the resulting state
continues to satisfy the current envelope.

## Four layers

Conditions are layered so that everyday work cannot quietly rewrite the
constitution. Outer layers are few and stable. Inner layers are allowed to
move.

1. **Hard invariants** — few, stable, mechanically enforceable. Change only
   with explicit human authority.
2. **Meta-rules** — how the envelope itself may change. Stricter than
   ordinary derived conditions.
3. **Derived conditions** — compiled from human statements. Trackable back
   to the originating exchange.
4. **Operational constraints** — generated during work, including machine
   goals. Short-lived relative to invariants. Must not silently promote.

Each condition names: the predicate to run, the evidence it needs, the
layer it belongs to, and the originating exchange in memory. Unattributed
conditions are rejected by the checker.

A proposal’s **oracles** are the predicates the checker will re-run for that
change. Envelope conditions are the standing oracles of the machine. Same
idea at two timescales.

## Checkable means mechanical

A condition that can only be evaluated by asking a model “does this seem
fine?” is not a condition. It is a vibe. AIOS refuses to treat vibes as
control.

- Commands with expected exit codes and output predicates.
- Tests, typecheckers, linters, and build gates.
- File-presence, permission, and hash checks.
- Package-set diffs against the declared list.
- Policy scripts in the checker repository.

**Rule.** Prefer independent checkers over a second opinion from the same
model that proposed the change. Shared memory is allowed. Shared judgement
is not.

## Evolving the envelope

The envelope is living. Derived conditions and operational constraints
change as the machine and the human’s intent for it change. Evolution is
itself under meta-rules:

- Envelope patches are git diffs in `/srv/aios/envelope`, never in-memory
  edits.
- Promoting a constraint into a hard invariant requires explicit human
  authority on the definition surface.
- Demoting or deleting a hard invariant is the same: human authority,
  recorded, with a reason that remains in memory.
- The agent may propose envelope changes. The checker validates the patch
  against meta-rules. The human is the merge authority for layers one and
  two.

## Human authority

The human is the ultimate source of the highest conditions and the
emergency brake. That is not ceremonial:

- The definition surface can halt privileged enactment immediately.
- Halt is a mechanical interlock (systemd stop + freeze of the proposer),
  not a polite request.
- The human is not used as QA. The agent and the checker verify. The human
  sets what “acceptable” means and can reject a merged result after the
  fact, which then becomes a new condition.

Direct human instruction always outranks nested `AGENTS.md` files, skills,
and derived conditions — except where a hard invariant forbids the
instruction (for example: do not destroy backups, do not disable the
checker). Conflicts of that kind are raised, not silently resolved.
