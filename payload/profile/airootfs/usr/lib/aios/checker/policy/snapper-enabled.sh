#!/bin/sh
# HI-06: snapper may not be taken off to make a change easier.
set -eu

fail() {
  printf 'snapper-enabled: %s\n' "$*" >&2
  exit 1
}

enabled() {
  _u=$1
  _st=$(systemctl is-enabled "${_u}" 2>/dev/null || true)
  [ "${_st}" = enabled ] || fail "${_u} is ${_st:-missing}, not enabled (HI-06)"
}

not_masked() {
  _u=$1
  _st=$(systemctl is-enabled "${_u}" 2>/dev/null || true)
  [ "${_st}" != masked ] || fail "${_u} is masked (HI-06)"
}

command -v systemctl >/dev/null 2>&1 || fail "systemctl missing"
command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Q snapper >/dev/null 2>&1 || fail "snapper is not installed"
command -v snapper >/dev/null 2>&1 || fail "snapper binary missing"

[ -f /etc/snapper/configs/root ] || fail "snapper config root missing"
[ -f /etc/snapper/configs/home ] || fail "snapper config home missing"
grep -q '^SUBVOLUME=' /etc/snapper/configs/root \
  || fail "snapper config root has no SUBVOLUME"
grep -q '^SUBVOLUME=' /etc/snapper/configs/home \
  || fail "snapper config home has no SUBVOLUME"

command -v mountpoint >/dev/null 2>&1 || fail "mountpoint missing"
mountpoint -q /.snapshots \
  || fail "/.snapshots is not a mount (L-07 @snapshots)"

enabled snapper-timeline.timer
enabled snapper-cleanup.timer
not_masked snapper-timeline.timer
not_masked snapper-cleanup.timer

exit 0
