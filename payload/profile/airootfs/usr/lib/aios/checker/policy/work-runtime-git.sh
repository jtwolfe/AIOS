#!/bin/sh
# Live work-runtime tree is its own git repo when the envelope bit is yes.
# Read-only. Host oracles must set AIOS_POLICY_ROOT; never mkdir /srv/aios/src.
set -eu

fail() {
  printf 'work-runtime-git: %s\n' "$*" >&2
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

_tree=$(p /srv/aios/src/work-runtime)
_src=$(p /srv/aios/src)

if [ "${YES}" -eq 0 ]; then
  # Disable leaves git (inert). A non-git /srv/aios/src is still HI-15.
  if [ -e "${_src}" ]; then
    git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
    _inside=$(git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree)
    [ "${_inside}" = true ] \
      || fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
  fi
  exit 0
fi

[ -d "${_tree}" ] || fail "/srv/aios/src/work-runtime missing after yes (HI-17)"
git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "/srv/aios/src/work-runtime is not a git repository"
_inside=$(git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree)
[ "${_inside}" = true ] \
  || fail "/srv/aios/src/work-runtime is not a git repository"
_origin=$(git -c safe.directory="${_tree}" -C "${_tree}" remote get-url origin 2>/dev/null || true)
case "${_origin}" in
  *github*|*http://*|*https://*)
    fail "work-runtime origin is ${_origin}, not local (HI-17)"
    ;;
esac

exit 0
