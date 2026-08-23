#!/bin/sh
# HI-09: a file under /srv/aios that git does not know is a snowflake.
set -eu

fail() {
  printf 'HI-09: %s\n' "$*" >&2
  exit 1
}

[ -d /srv/aios ] || fail "/srv/aios missing"
[ ! -e /srv/aios/.git ] || fail "/srv/aios must not be a single git repository"

# Top-level names firstboot already creates. Anything else is undeclared.
for _p in /srv/aios/* /srv/aios/.[!.]*; do
  [ -e "${_p}" ] || continue
  _b=${_p#/srv/aios/}
  case "${_b}" in
    AGENTS.md|envelope|memory|skills|agent|checker|state|seeds|git|etc-mirror|src) ;;
    *) fail "undeclared path ${_p}" ;;
  esac
done

TREES="envelope memory skills agent checker state seeds"
for _n in ${TREES}; do
  _wt=/srv/aios/${_n}
  _bare=/srv/aios/git/${_n}.git
  [ -d "${_bare}/objects" ] || fail "bare repo missing: ${_bare}"
  git --git-dir="${_bare}" rev-parse --verify main >/dev/null 2>&1 \
    || fail "${_n}.git has no main"
  [ -d "${_wt}" ] || fail "worktree missing: ${_wt}"
  if ! git --git-dir="${_bare}" --work-tree="${_wt}" diff --quiet 2>/dev/null; then
    fail "${_wt} has uncommitted paths (HI-09)"
  fi
  _untracked=$(git --git-dir="${_bare}" --work-tree="${_wt}" ls-files --others --exclude-standard 2>/dev/null) \
    || fail "cannot list untracked files in ${_wt}"
  [ -z "${_untracked}" ] || fail "${_wt} has untracked paths (HI-09)"
done

_ans=/srv/aios/state/bootstrap-in-progress/answers.json
_yes=0
if [ -f "${_ans}" ] \
  && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}" \
  && grep -Eq '"work_runtime"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
  _yes=1
fi
if [ "${_yes}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
fi
if [ "${_yes}" -eq 1 ]; then
  git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "work-runtime tree is not git (HI-09)"
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -x "${here}/packages-drift.sh" ] || fail "packages-drift.sh missing"
"${here}/packages-drift.sh"

exit 0
