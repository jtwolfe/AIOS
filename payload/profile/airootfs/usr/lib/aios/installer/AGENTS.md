# AGENTS.md

Contract for the TTY installer TUI. Nested files in this tree outrank
this file. Direct human instruction wins, except where a hard invariant
forbids it; those conflicts are raised, not swallowed.

Canonical hard invariants: [`docs/envelope/hard-invariants.md`](../docs/envelope/hard-invariants.md).
Quote them by id. Do not extend them here.

## What this is

A line-oriented TUI in **installer** mode (`aios-installer.service`,
`TTYPath=/dev/console`). Same L-18 view catalog the OS client will use.
Not a raw question script. Not a throwaway wizard. Python 3 stdlib only
(L-01). POSIX wrapper: `/usr/lib/aios/bin/installer` (L-09).

It is not the checker, not the proposer, and not a work agent (HI-02,
HI-13). Work runtime stays default off (HI-15).

## Non-negotiable

1. Named views only: `chrome`, `conversation`, `questions`, `envelope`,
   `accept`, `recovery` (L-18). Do not invent extra view ids.
2. Skip is not a yes. Default administer-only (HI-15). Do not synthesise
   `/srv/aios/src/work-runtime`.
3. Envelope view is reachable without scrolling the transcript. Accept
   and reject are first-class keyboard actions.
4. Recovery is a view with a resume action (L-18). Persist accepted
   answers, envelope draft, snapper_pre, and step under
   `/srv/aios/state/bootstrap-in-progress` (or `AIOS_BOOTSTRAP`). Skip
   is not a yes (HI-15). Malformed snapshot fails closed to questions.
   Reject offers L-19 rollback and does not leave undeclared live state
   (HI-09).
5. Emergency brake is a chrome action (L-12): freeze privileged writes;
   this TUI stays up. Human-only. Do not invent a daemon.
6. Harness A: no sysupgrade during the conversation (L-20). Do not curl.
   Do not open a browser. Live login is after accept (L-17).
7. Never commit to `main`. Never force-push (HI-03).
8. Do not import a model client (HI-02).
9. The unit is not enabled on the live ISO (L-09).
10. Operator login is asked, never derived from purpose. Accept creates
    one non-root human login and no enact sudo (L-13). Privileged writes
    go under `AIOS_ROOT` when set. Host oracles must set it.
