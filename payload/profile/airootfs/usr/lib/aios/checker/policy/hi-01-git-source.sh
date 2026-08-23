#!/bin/sh
# HI-01: a privileged change that is not a commit is undeclared live state.
set -eu

fail() {
  printf 'HI-01: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

TREES="envelope memory skills agent checker state seeds"
for _n in ${TREES}; do
  _bare=/srv/aios/git/${_n}.git
  _wt=/srv/aios/${_n}
  [ -d "${_bare}/objects" ] || fail "bare repo missing: ${_bare}"
  git --git-dir="${_bare}" rev-parse --verify main >/dev/null 2>&1 \
    || fail "${_n}.git has no main"
  [ -d "${_wt}" ] || fail "worktree missing: ${_wt}"
  git -C "${_wt}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "${_wt} is not a git worktree"
done

[ -f /srv/aios/envelope/hard-invariants.md ] \
  || fail "envelope/hard-invariants.md missing"
git --git-dir=/srv/aios/git/envelope.git cat-file -e main:hard-invariants.md \
  || fail "hard-invariants.md is not a commit in envelope.git"

[ -d /srv/aios/etc-mirror/objects ] || fail "etc-mirror missing"
git --git-dir=/srv/aios/etc-mirror rev-parse --verify HEAD >/dev/null 2>&1 \
  || fail "etc-mirror has no HEAD"

[ -x "${here}/packages-drift.sh" ] || fail "packages-drift.sh missing"
"${here}/packages-drift.sh"

exit 0
