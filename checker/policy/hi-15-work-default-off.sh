#!/bin/sh
# HI-15: skip is not a yes; work-runtime stays off until bootstrap records one.
set -eu

fail() {
  printf 'HI-15: %s\n' "$*" >&2
  exit 1
}

[ -f /srv/aios/envelope/hard-invariants.md ] \
  || fail "hard-invariants.md missing; cannot read the work-runtime bit"

_ans=/srv/aios/state/bootstrap-in-progress/answers.json
YES=0
if [ -f "${_ans}" ] \
  && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}" \
  && grep -Eq '"work_runtime"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
  YES=1
fi
# Compiled clause after accept: a dedicated enabled flag, not prose in the seed.
if [ "${YES}" -eq 0 ] && [ -f /srv/aios/envelope/work-runtime.md ]; then
  if grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(true|yes|1)[[:space:]]*$' \
    /srv/aios/envelope/work-runtime.md; then
    YES=1
  fi
fi

[ ! -e /etc/systemd/system/aios-work-runtime.service ] \
  || fail "aios-work-runtime.service must not be a system unit (L-23)"
[ ! -e /etc/systemd/system/aios-work-runtime-bots.service ] \
  || fail "aios-work-runtime-bots.service must not be a system unit (L-23)"

user_on() {
  _u=$1
  command -v systemctl >/dev/null 2>&1 || return 1
  _en=$(systemctl --user -M aios-work@ is-enabled "${_u}" 2>/dev/null || true)
  _ac=$(systemctl --user -M aios-work@ is-active "${_u}" 2>/dev/null || true)
  [ "${_en}" = enabled ] && return 0
  [ "${_ac}" = active ] && return 0
  return 1
}

if [ "${YES}" -eq 0 ]; then
  [ ! -e /srv/aios/src ] \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes"
  if user_on aios-work-runtime.service; then
    fail "aios-work-runtime.service enabled/active without an explicit yes"
  fi
  if user_on aios-work-runtime-bots.service; then
    fail "aios-work-runtime-bots.service enabled/active without an explicit yes"
  fi
  if [ -e /var/lib/systemd/linger/aios-work ]; then
    # Linger without the bit still must not have started the work unit.
    if user_on aios-work-runtime.service; then
      fail "linger started work-runtime while the bit is off"
    fi
  fi
fi

exit 0
