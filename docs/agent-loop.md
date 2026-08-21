# Agent loop

The privileged background agent observes, proposes, waits for the checker,
enacts through git, and remembers. Grok Build’s execution loop is the
working model for how that agent spends a turn.

## Privileged agent

The agent is privileged because the work requires it: installing packages,
writing unit files, synthesising programs, editing the envelope (as a
proposal). Privilege is not a personality trait. It is a systemd service
with a defined uid, a defined working tree, and a defined deny-list.

- It may read widely. Observation is cheap and should be deep.
- It may write only inside declared working trees until the checker has
  passed a proposal.
- It never merges its own branches to `main`.
- It never talks to the human as if they had a shell. Commands it can run,
  it runs. Evidence it can gather, it gathers.

**Rule.** Direct user instruction in the current conversation outranks this
document. Hard invariants outrank direct instruction when they conflict;
the conflict is raised, not swallowed.

## Execution loop

On every turn the agent follows a loop modelled on Grok Build. It does not
skip steps because the request was short.

1. **Triage.** Classify the request. Not every message is a build.
   Questions are answered. Empty pings are not turned into daemons.
   Destructive work is refused unless the envelope allows it.
2. **Consult skills.** Open the matching `SKILL.md` and its references
   before writing code or installing anything. Do not invent a parallel
   procedure.
3. **Establish the contract.** For non-trivial work: paths, types, layout,
   and which repo owns the change. Shared contract before parallel writes.
4. **Propose on a branch.** Edit in place. Prefer existing files. Keep the
   diff reviewable.
5. **Mechanical QA.** Tests, builds, typechecks, policy scripts — whatever
   the checker will re-run. The agent runs them first so the checker is not
   a surprise.
6. **Hand to the checker.** A merge request against local `main` (and a
   GitHub PR if a remote is configured). The checker is a different
   process.
7. **Remember.** Store the exchange, the diff, the evidence, and the
   outcome. Crystallise a skill only when the pattern has earned a file.

```
talk → update conditions → propose → validate → act → remember
```

## Consult skills first

Skills are not flavour text. They are the on-demand depth of the agent’s
judgement. An agent that “just writes code” after a one-line ask is
skipping the loop.

- Routing is by trigger: git work loads git standards; package work loads
  acquisition; UI work loads the relevant skill, and so on.
- Nested `AGENTS.md` in the target repository outranks a general skill for
  files in that tree.
- If no skill applies, the agent says so in the proposal rather than
  silently inventing policy.

## Verify, do not ask

The human is the authority, not the agent’s CI. The agent does not close a
turn with “run this and tell me if it works.” It runs the checks, reads the
output, and either fixes the work or reports a genuine blocker the envelope
does not let it cross.

HTTP 200 is not verification. A green test run the proposer did not
actually execute is not verification. The quality bar in Grok Build is
adopted wholesale: if it cannot be shown, it is not done.
