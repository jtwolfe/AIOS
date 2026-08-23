#!/bin/sh
# HI-06: disabling snapper, etckeeper, the checker, or boot seatbelts is not a shortcut.
set -eu

fail() {
  printf 'HI-06: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

enabled() {
  _u=$1
  _st=$(systemctl is-enabled "${_u}" 2>/dev/null || true)
  [ "${_st}" = enabled ] || fail "${_u} is ${_st:-missing}, not enabled"
}

not_masked() {
  _u=$1
  _st=$(systemctl is-enabled "${_u}" 2>/dev/null || true)
  [ "${_st}" != masked ] || fail "${_u} is masked"
}

command -v systemctl >/dev/null 2>&1 || fail "systemctl missing"
command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Q linux >/dev/null 2>&1 || fail "linux is not installed"
pacman -Q linux-lts >/dev/null 2>&1 || fail "linux-lts is not installed"

enabled aios-checker.service
not_masked aios-checker.service
enabled snapper-timeline.timer
enabled snapper-cleanup.timer
not_masked snapper-timeline.timer
not_masked snapper-cleanup.timer

for _s in snapper-enabled.sh etckeeper-enabled.sh boot-seatbelt.sh no-partial-upgrade.sh; do
  [ -x "${here}/${_s}" ] || fail "missing ${_s}"
  "${here}/${_s}"
done

exit 0
