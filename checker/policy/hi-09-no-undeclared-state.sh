#!/bin/sh
# HI-09: a file under /srv/aios that git does not know is a snowflake.
# Host oracles set AIOS_POLICY_ROOT; never mkdir live paths.
set -eu

fail() {
  printf 'HI-09: %s\n' "$*" >&2
  exit 1
}

_root=${AIOS_POLICY_ROOT-}
p() {
  printf '%s%s' "${_root}" "$1"
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${here}/work-runtime-bit.sh"
work_runtime_compute_yes "${_root}"
_yes=${WORK_RUNTIME_YES}

if [ "${_yes}" -eq 0 ]; then
  work_runtime_inert_git "${_root}" \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
else
  git -c safe.directory="$(p /srv/aios/src/work-runtime)" \
    -C "$(p /srv/aios/src/work-runtime)" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "work-runtime tree is not git (HI-09)"
fi

if [ -n "${_root}" ]; then
  exit 0
fi

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

[ -x "${here}/packages-drift.sh" ] || fail "packages-drift.sh missing"
"${here}/packages-drift.sh"

exit 0
