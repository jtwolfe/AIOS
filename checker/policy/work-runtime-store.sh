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

# Keep in sync with goals.py _ENABLED_LINE/_DISABLED_LINE and enact work_runtime_yes.
_ans=$(p /srv/aios/state/bootstrap-in-progress/answers.json)
_clause=$(p /srv/aios/envelope/work-runtime.md)
YES=0
OFF=0
if [ -f "${_clause}" ]; then
  if grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(false|no|0)[[:space:]]*$' \
    "${_clause}"; then
    OFF=1
  elif grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(true|yes|1)[[:space:]]*$' \
    "${_clause}"; then
    YES=1
  fi
fi
if [ "${OFF}" -eq 0 ] && [ "${YES}" -eq 0 ] && [ -f "${_ans}" ] \
  && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}" \
  && grep -Eq '"work_runtime"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
  YES=1
fi

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
    | grep -E 'routines|connectors' >/dev/null; then
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
