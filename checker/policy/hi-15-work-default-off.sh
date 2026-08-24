#!/bin/sh
# HI-15: skip is not a yes; work-runtime stays off until bootstrap records one.
# After disable, units are off and git may remain (inert). Host oracles set
# AIOS_POLICY_ROOT; never mkdir live paths.
set -eu

fail() {
  printf 'HI-15: %s\n' "$*" >&2
  exit 1
}

_root=${AIOS_POLICY_ROOT-}
p() {
  printf '%s%s' "${_root}" "$1"
}

if [ -z "${_root}" ]; then
  [ -f /srv/aios/envelope/hard-invariants.md ] \
    || fail "hard-invariants.md missing; cannot read the work-runtime bit"
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${here}/work-runtime-bit.sh"
work_runtime_compute_yes "${_root}"
YES=${WORK_RUNTIME_YES}

[ ! -e "$(p /etc/systemd/system/aios-work-runtime.service)" ] \
  || fail "aios-work-runtime.service must not be a system unit (L-23)"
[ ! -e "$(p /etc/systemd/system/aios-work-runtime-bots.service)" ] \
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
  work_runtime_inert_git "${_root}" \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes"
  [ ! -e "$(p /etc/systemd/user/default.target.wants/aios-work-runtime.service)" ] \
    || fail "aios-work-runtime.service enabled without an explicit yes"
  [ ! -e "$(p /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service)" ] \
    || fail "aios-work-runtime-bots.service enabled without an explicit yes"
  if [ -z "${_root}" ]; then
    if user_on aios-work-runtime.service; then
      fail "aios-work-runtime.service enabled/active without an explicit yes"
    fi
    if user_on aios-work-runtime-bots.service; then
      fail "aios-work-runtime-bots.service enabled/active without an explicit yes"
    fi
    if [ -e /var/lib/systemd/linger/aios-work ]; then
      if user_on aios-work-runtime.service; then
        fail "linger started work-runtime while the bit is off"
      fi
    fi
  fi
fi

exit 0
