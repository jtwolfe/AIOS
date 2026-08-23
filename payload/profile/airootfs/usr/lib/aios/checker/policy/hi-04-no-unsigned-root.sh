#!/bin/sh
# HI-04: /usr outside pacman and unsigned root installs are not reconstructible.
set -eu

fail() {
  printf 'HI-04: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ -x "${here}/packages-drift.sh" ] || fail "packages-drift.sh missing"
"${here}/packages-drift.sh"
[ -x "${here}/no-curl-sh.sh" ] || fail "no-curl-sh.sh missing"
"${here}/no-curl-sh.sh"

[ -f /etc/pacman.conf ] || fail "pacman.conf missing"
# Uncommented SigLevel must still require package signatures.
_sig=$(grep -E '^[[:space:]]*SigLevel' /etc/pacman.conf || true)
[ -n "${_sig}" ] || fail "pacman.conf has no SigLevel"
printf '%s\n' "${_sig}" | grep -Eq 'Never' \
  && fail "pacman SigLevel allows unsigned packages"
printf '%s\n' "${_sig}" | grep -Eq 'Required' \
  || fail "pacman SigLevel is not Required"

command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Qo /usr/bin/pacman >/dev/null 2>&1 \
  || fail "/usr/bin/pacman is not owned by a package"
pacman -Qo /usr/bin/systemctl >/dev/null 2>&1 \
  || fail "/usr/bin/systemctl is not owned by a package"

# A stray tree under /usr/local is a root install that never hit packages.txt.
if [ -d /usr/local/bin ]; then
  _stray=$(find /usr/local/bin -type f -maxdepth 1 2>/dev/null | head -n 1 || true)
  [ -z "${_stray}" ] || fail "unsigned file in /usr/local/bin: ${_stray}"
fi

exit 0
