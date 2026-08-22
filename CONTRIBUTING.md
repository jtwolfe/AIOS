# Contributing

The specification is complete on `main`. Contributions are envelope
clarifications, documentation, and implementation against
[`docs/implementation.md`](docs/implementation.md). Humans and agents
use the same path. Read [`HANDOVER.md`](HANDOVER.md) before writing
code.


## Path

1. Open an issue or start from an existing one. Intent before diff.
2. Branch from `main`: `feat/<slug>`, `docs/<slug>`, or
   `agent/<yyyy-mm-dd>-<slug>`.

3. Prefer editing existing files. Do not add speculative structure.
4. Keep commits atomic and conventional (`feat:`, `fix:`, `docs:`, …).
5. Open a pull request against `main`. Fill in the template: envelope
   clause (or “docs only”), checks run, and what the human should read.
6. Wait for review. The proposer does not merge.

## Documentation

Prose in `docs/` is the specification. `AGENTS.md` is the contract agents
must follow. The README is the manifesto and index. If those three drift,
the docs are wrong — fix them in the same PR.

## Code (when it exists)

- Arch Linux is the assumed substrate.
- All synthesised code and all installs are local git history. See
  [docs/git-standards.md](docs/git-standards.md).
- Tests, typechecks, and policy scripts the checker will re-run must be
  run by the author first.
- No secrets in git. No `curl | sh`. No force-push to published branches.

## Review

Review is against the envelope, not against taste alone. If a change
cannot be checked mechanically, say so in the PR rather than merging on
confidence.
