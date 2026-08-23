#!/bin/sh
# HI-16: the privilege boundary is an OS property, not work-agent cooperation.
set -eu

fail() {
  printf 'HI-16: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -x "${here}/work-slice.sh" ] || fail "work-slice.sh missing"
"${here}/work-slice.sh"

need_uid() {
  id -u "$1" >/dev/null 2>&1 || fail "sysuser $1 missing (L-02)"
}

need_uid aios-agent
need_uid aios-checker
need_uid aios-work

[ -d /run/aios ] || fail "/run/aios missing (tmpfiles)"
_own=$(stat -c '%U' /run/aios)
_grp=$(stat -c '%G' /run/aios)
_mod=$(stat -c '%a' /run/aios)
[ "${_own}" = aios-agent ] || fail "/run/aios owner is ${_own}, not aios-agent"
[ "${_grp}" = aios-work ] || fail "/run/aios group is ${_grp}, not aios-work"
[ "${_mod}" = 750 ] || fail "/run/aios mode is ${_mod}, not 750"

if [ -S /run/aios/intent.sock ]; then
  _own=$(stat -c '%U' /run/aios/intent.sock)
  _grp=$(stat -c '%G' /run/aios/intent.sock)
  _mod=$(stat -c '%a' /run/aios/intent.sock)
  [ "${_own}" = aios-agent ] || fail "intent.sock owner is ${_own}, not aios-agent (L-05)"
  [ "${_grp}" = aios-work ] || fail "intent.sock group is ${_grp}, not aios-work (L-05)"
  [ "${_mod}" = 660 ] || fail "intent.sock mode is ${_mod}, not 660 (L-05)"
fi

# When the user unit exists, denial flags must be on the unit, not hoped for.
U=/usr/lib/systemd/user/aios-work-runtime.service
if [ -f "${U}" ]; then
  grep -q '^NoNewPrivileges=yes$' "${U}" \
    || fail "work-runtime user unit missing NoNewPrivileges=yes"
  grep -q '^ProtectSystem=strict$' "${U}" \
    || fail "work-runtime user unit missing ProtectSystem=strict"
  grep -q 'InaccessiblePaths=.*enact' "${U}" \
    || fail "work-runtime user unit does not hide enact"
  grep -q 'InaccessiblePaths=.*envelope' "${U}" \
    || fail "work-runtime user unit does not hide envelope"
  # L-16: the live OS token lives under /srv/aios/state.
  grep -q 'InaccessiblePaths=.*state' "${U}" \
    || fail "work-runtime user unit does not hide state"
fi

if [ -f /etc/systemd/system/aios-work.slice ]; then
  grep -q 'MemoryMax=' /etc/systemd/system/aios-work.slice \
    || fail "aios-work.slice missing MemoryMax"
  grep -q 'CPUQuota=' /etc/systemd/system/aios-work.slice \
    || fail "aios-work.slice missing CPUQuota"
fi

exit 0
