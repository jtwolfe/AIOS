#!/bin/sh
# HI-01 / HI-04: undeclared packages are live snowflake state.
set -eu

fail() {
  printf 'packages-drift: %s\n' "$*" >&2
  exit 1
}

PIN=/srv/aios/state/packages.txt
BARE=/srv/aios/git/state.git

command -v pacman >/dev/null 2>&1 || fail "pacman missing"
[ -f "${PIN}" ] || fail "missing ${PIN}"
[ -s "${PIN}" ] || fail "${PIN} is empty"

grep -qx linux "${PIN}" || fail "linux missing from packages.txt (HI-06)"
grep -qx linux-lts "${PIN}" || fail "linux-lts missing from packages.txt (HI-06)"

pacman -Q linux >/dev/null 2>&1 || fail "linux is not installed"
pacman -Q linux-lts >/dev/null 2>&1 || fail "linux-lts is not installed"

LIVE=$(mktemp)
trap 'rm -f "${LIVE}"' EXIT
pacman -Qqe >"${LIVE}" || fail "pacman -Qqe failed"
[ -s "${LIVE}" ] || fail "pacman -Qqe produced no explicit packages"

if ! cmp -s "${PIN}" "${LIVE}"; then
  fail "packages.txt does not match pacman -Qqe"
fi

[ -d "${BARE}/objects" ] || fail "state.git missing"
git --git-dir="${BARE}" cat-file -e main:packages.txt 2>/dev/null \
  || fail "packages.txt is not a commit in state.git (HI-01)"

exit 0
