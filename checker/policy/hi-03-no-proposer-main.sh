#!/bin/sh
# HI-03: the proposer must not be able to update main.
set -eu

fail() {
  printf 'HI-03: %s\n' "$*" >&2
  exit 1
}

MERGE=/srv/aios/checker/aios_checker/merge.py
[ -f "${MERGE}" ] || fail "merge.py missing"
grep -q 'only aios-checker uid may merge to main' "${MERGE}" \
  || fail "merge.py does not gate main on aios-checker uid"
grep -q 'refusing non-fast-forward update of main' "${MERGE}" \
  || fail "merge.py does not refuse non-fast-forward of main"

TREES="envelope memory skills agent checker state seeds"
for _n in ${TREES}; do
  _bare=/srv/aios/git/${_n}.git
  [ -d "${_bare}/objects" ] || fail "bare repo missing: ${_bare}"
  _own=$(stat -c '%U' "${_bare}")
  [ "${_own}" = aios-checker ] || fail "${_bare} owner is ${_own}, not aios-checker (L-03)"
  _mod=$(stat -c '%a' "${_bare}")
  _o=$(printf '%s' "${_mod}" | awk '{print substr($0,length($0),1)}')
  case "${_o}" in
    2|3|6|7) fail "${_bare} is other-writable" ;;
  esac
  for _h in update pre-receive reference-transaction; do
    [ -x "${_bare}/hooks/${_h}" ] || fail "${_bare}/hooks/${_h} missing (L-03)"
  done
  git --git-dir="${_bare}" rev-parse --verify main >/dev/null 2>&1 \
    || fail "${_n}.git has no main"
  _authors=$(git --git-dir="${_bare}" log --format='%an' main 2>/dev/null || true)
  printf '%s\n' "${_authors}" | grep -qx aios-agent \
    && fail "${_n}.git main has a commit authored by aios-agent"
done

exit 0
