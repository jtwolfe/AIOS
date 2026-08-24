#!/bin/sh
# P8.11: notes/skills/routines/connectors are git in the work tree.
# Read-only. Host oracles must set AIOS_POLICY_ROOT; never mkdir live paths.
set -eu

fail() {
  printf 'work-runtime-store: %s\n' "$*" >&2
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
YES=${WORK_RUNTIME_YES}

if [ -n "${AIOS_WORK_SRC-}" ]; then
  _tree=${AIOS_WORK_SRC}
else
  _tree=$(p /srv/aios/src/work-runtime)
fi
if [ -n "${AIOS_MEMORY-}" ]; then
  _mem=${AIOS_MEMORY}
else
  _mem=$(p /srv/aios/memory)
fi

is_git() {
  _p=$1
  git -c safe.directory="${_p}" -C "${_p}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || return 1
  _inside=$(git -c safe.directory="${_p}" -C "${_p}" rev-parse --is-inside-work-tree)
  [ "${_inside}" = true ]
}

if is_git "${_mem}"; then
  if git -c safe.directory="${_mem}" -C "${_mem}" ls-files \
    | grep -E '(^|/)(routines|connectors)(/|$)' >/dev/null; then
    fail "memory git tracks routines or connectors; work store is the work tree"
  fi
fi

if [ "${YES}" -eq 1 ]; then
  is_git "${_tree}" || fail "/srv/aios/src/work-runtime is not a git repository"
fi

if is_git "${_tree}"; then
  for _d in notes skills routines connectors; do
    [ -d "${_tree}/${_d}" ] || fail "work store missing ${_d}/"
  done
  _listed=$(git -c safe.directory="${_tree}" -C "${_tree}" ls-files)
  printf '%s\n' "${_listed}" | grep -q '^notes/' \
    || fail "work git does not track notes/"
  printf '%s\n' "${_listed}" | grep -q '^skills/' \
    || fail "work git does not track skills/"
  printf '%s\n' "${_listed}" | grep -q '^routines/' \
    || fail "work git does not track routines/"
  printf '%s\n' "${_listed}" | grep -q '^connectors/' \
    || fail "work git does not track connectors/"
fi

exit 0
