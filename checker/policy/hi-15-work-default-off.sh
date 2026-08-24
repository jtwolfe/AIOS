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

inert_tree() {
  _tree=$(p /srv/aios/src/work-runtime)
  _src=$(p /srv/aios/src)
  [ -e "${_src}" ] || return 0
  git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes"
  _inside=$(git -c safe.directory="${_tree}" -C "${_tree}" rev-parse --is-inside-work-tree)
  [ "${_inside}" = true ] \
    || fail "/srv/aios/src exists while work-runtime is not an explicit yes"
}

if [ "${YES}" -eq 0 ]; then
  inert_tree
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
