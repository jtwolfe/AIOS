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

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${here}/work-runtime-bit.sh"
work_runtime_compute_yes "${_root}"
YES=${WORK_RUNTIME_YES}

_tree=$(p /srv/aios/src/work-runtime)
_src=$(p /srv/aios/src)

if [ "${YES}" -eq 0 ]; then
  work_runtime_inert_git "${_root}" \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
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
