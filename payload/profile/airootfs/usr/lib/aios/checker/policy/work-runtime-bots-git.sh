#!/bin/sh
# Live work-runtime-bots tree is its own git repo when the second bit is on.
# Read-only. Host oracles must set AIOS_POLICY_ROOT; never mkdir /srv/aios/src.
set -eu

fail() {
  printf 'work-runtime-bots-git: %s\n' "$*" >&2
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
bots_compute_yes "${_root}"
YES=${WORK_RUNTIME_YES}
BOTS=${BOTS_YES}
if [ "${YES}" -eq 0 ]; then
  BOTS=0
fi

_tree=$(p /srv/aios/src/work-runtime-bots)

if [ "${BOTS}" -eq 0 ]; then
  bots_inert_git "${_root}" \
    || fail "/srv/aios/src/work-runtime-bots exists while bots is not an explicit yes (HI-15)"
  [ ! -e "$(p /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service)" ] \
    || fail "aios-work-runtime-bots.service enabled without an explicit yes"
  [ ! -e "$(p /etc/systemd/system/aios-work-runtime-bots.service)" ] \
    || fail "aios-work-runtime-bots.service must not be a system unit (L-23)"
  exit 0
fi

[ -d "${_tree}" ] || fail "/srv/aios/src/work-runtime-bots missing after yes (HI-17)"
git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "/srv/aios/src/work-runtime-bots is not a git repository"
_inside=$(git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree)
[ "${_inside}" = true ] \
  || fail "/srv/aios/src/work-runtime-bots is not a git repository"
_origin=$(git -c safe.directory="${_tree}" -C "${_tree}" remote get-url origin 2>/dev/null || true)
case "${_origin}" in
  *github*|*http://*|*https://*)
    fail "work-runtime-bots origin is ${_origin}, not local (HI-17)"
    ;;
esac
[ ! -e "$(p /etc/systemd/system/aios-work-runtime-bots.service)" ] \
  || fail "aios-work-runtime-bots.service must not be a system unit (L-23)"

exit 0
