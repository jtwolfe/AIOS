# Git standards

If the AI writes code or installs anything, that work is managed locally
with high-quality git versioning and professional development standards.
There is no unversioned live mutation.

This is a hard invariant of AIOS, not a style preference.

## The enactment law

The live machine is a checkout of local git history plus the current
envelope. Anything the agent does that cannot be shown as a commit is
undeclared state, and undeclared state is a defect.

**Rule.** Local repositories are the source of truth. GitHub and other
remotes are mirrors and collaboration. The agent does not treat a
successful push as a substitute for a local, reviewable history.

## What is a repository

- Every synthesised program under `/srv/aios/src/<name>` is its own git
  repository from the first file.
- The envelope, memory, skills, agent, checker, and system-intent trees are
  repositories.
- `/etc` is tracked with etckeeper.
- Dotfiles are a repository. They are not a pile of files in `$HOME`.
- A change that spans two repositories is two branches and two reviews,
  linked by the same intent slug — not one secret script that reaches into
  both.

Initialise with a `.gitignore`, an `AGENTS.md` if the tree will be edited
by an agent, and a README that states purpose. Do not create files “for
later.”

## Branch, test, merge

Trunk-based, short-lived branches. `main` is always reconstructible and
always passing the checker.

1. **Intent** — a human request or an envelope-driven task.
2. **Branch** — `agent/<yyyy-mm-dd>-<slug>` off `main`. Never work on
   `main`.
3. **Synthesise** — edit existing files first. Keep the diff reviewable.
4. **Test** — mechanical checks the checker will re-run independently.
5. **Commit** — atomic, conventional, complete. One logical change.
6. **Review** — the checker, not the proposer, reads the diff against the
   envelope.
7. **Merge** — fast-forward or squash to `main`. Main stays
   reconstructible.
8. **Snapshot** — btrfs snapper snapshot after privileged system enactment.

```sh
git switch main
git pull --ff-only
git switch -c agent/2026-08-21-neovim-as-editor

# ...synthesise, test...

git add -p
git commit -m "feat(editor): install neovim under envelope clause 12"

git switch main
# checker fast-forwards or squash-merges after independent validation
```

### Branch names

- Agent work: `agent/<yyyy-mm-dd>-<slug>`
- Human work: `feat/`, `fix/`, `docs/` as usual
- No work on `main`. No long-lived agent branches.

### Remotes

If a GitHub remote exists, the agent opens a pull request after the local
checker has a passing proposal. The PR is documentation of the review, not
the review itself. Local merge authority remains on the machine unless the
envelope says otherwise.

## Commit quality

- **Atomic.** One logical change per commit. A package install is not mixed
  with a drive-by refactor.
- **Conventional.** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
  `build`, `revert`. Optional scope: `feat(envelope):`.
- **Complete.** The body names the envelope clause, the originating
  exchange, and the checks that were run.
- **Signed** when SSH or GPG signing is available on the box. Signing is a
  should; history is a must.
- **No secrets.** Tokens, keys, and `.env` files never enter git. The
  checker scans for them.
- **No PII.** Personal names, emails, phone numbers, addresses, and
  home-machine identifiers do not enter the tree. The operator is a role.
  A workstation is generic.

```
feat(state): install neovim and configured.d overlay

Envelope: envelope/clauses/editor.md
Memory:   memory/exchanges/2026-08-21-editor
Checks:   pacman -Qi neovim; nvim --version; checker/policy/editors.sh
Snapshot: snapper pre #184
```

Stage with intent (`git add -p` or named paths). `git add .` is not a
habit.

## Installs are commits

Software acquisition is not a side channel. A `pacman -S` that does not
appear in `/srv/aios/state` is a broken enactment, even if the package
works.

- Update `state/packages.txt` from `pacman -Qqe`.
- Record the transaction reason, envelope clause, and snapper pre/post ids.
- Language-level dependencies belong to the project repository as lockfiles,
  never as host-global installs.
- AUR builds happen in a chroot. The resulting package, PKGBUILD pin, and
  checksums are committed before install.

## Forbidden moves

- Committing to `main` as the proposer.
- Force-pushing to `main` or to any published branch.
- Amending commits the checker has already seen.
- `git add .` as a habit.
- `curl | sh`, unsigned install scripts, and mutating `/usr` outside
  pacman.
- Rewriting history to hide a failed enactment. Revert forward.
- Empty commits, generated noise, or `WIP` on `main`.

Professional standards here mean the boring ones: small diffs, named
reasons, passing checks, review by someone who did not write the patch —
even when that someone is another process.
