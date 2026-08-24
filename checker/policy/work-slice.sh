#!/bin/sh
# HI-13: a work process that can enact is a checker failure, not a prompt failure.
set -eu

fail() {
  printf 'work-slice: %s\n' "$*" >&2
  exit 1
}

# AIOS_POLICY_ROOT prefixes unit paths. Host oracles must set it.
_root=${AIOS_POLICY_ROOT-}
p() {
  printf '%s%s' "${_root}" "$1"
}

_slice=$(p /etc/systemd/system/aios-work.slice)
_floor=$(p /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf)
if [ -n "${_root}" ]; then
  [ -f "${_slice}" ] || fail "aios-work.slice missing under AIOS_POLICY_ROOT"
  [ -f "${_floor}" ] || fail "aios-work floor drop-in missing under AIOS_POLICY_ROOT"
fi
# P6 slice: if present it must actually deny. Absence is not a green skip of a fake unit.
if [ -f "${_slice}" ]; then
  grep -q '^\[Slice\]' "${_slice}" \
    || fail "aios-work.slice has no [Slice] section"
fi
if [ -f "${_floor}" ]; then
  grep -q 'InaccessiblePaths=.*envelope' "${_floor}" \
    || fail "floor drop-in does not hide envelope"
  grep -q 'InaccessiblePaths=.*state' "${_floor}" \
    || fail "floor drop-in does not hide state"
  grep -q 'InaccessiblePaths=.*enact' "${_floor}" \
    || fail "floor drop-in does not hide enact"
fi

if [ -n "${_root}" ]; then
  exit 0
fi

need_uid() {
  command -v id >/dev/null 2>&1 || fail "id missing"
  id -u "$1" >/dev/null 2>&1 || fail "sysuser $1 missing (L-02)"
}

# Last mode digit is other; group is the tens digit of the last three.
other_write() {
  _m=$1
  _o=$(printf '%s' "${_m}" | awk '{print substr($0,length($0),1)}')
  case "${_o}" in
    2|3|6|7) return 0 ;;
  esac
  return 1
}

group_write() {
  _m=$1
  _g=$(printf '%s' "${_m}" | awk '{print substr($0,length($0)-1,1)}')
  case "${_g}" in
    2|3|6|7) return 0 ;;
  esac
  return 1
}

denied_to_work() {
  _p=$1
  [ -e "${_p}" ] || fail "missing ${_p}"
  _own=$(stat -c '%U' "${_p}")
  _grp=$(stat -c '%G' "${_p}")
  _mod=$(stat -c '%a' "${_p}")
  [ "${_own}" != aios-work ] || fail "${_p} is owned by aios-work"
  if other_write "${_mod}"; then
    fail "${_p} is other-writable"
  fi
  if [ "${_grp}" = aios-work ] && group_write "${_mod}"; then
    fail "${_p} is group-writable by aios-work"
  fi
}

need_uid aios-agent
need_uid aios-checker
need_uid aios-work
UA=$(id -u aios-agent)
UC=$(id -u aios-checker)
UW=$(id -u aios-work)
[ "${UA}" != "${UC}" ] && [ "${UA}" != "${UW}" ] && [ "${UC}" != "${UW}" ] \
  || fail "aios-agent/checker/work uids are not distinct (L-02)"

_groups=$(id -nG aios-work 2>/dev/null || true)
printf '%s\n' "${_groups}" | grep -Eq '(^|[[:space:]])wheel($|[[:space:]])' \
  && fail "aios-work is in wheel"
printf '%s\n' "${_groups}" | grep -Eq '(^|[[:space:]])aios-checker($|[[:space:]])' \
  && fail "aios-work shares aios-checker group (L-02)"
_agroups=$(id -nG aios-agent 2>/dev/null || true)
printf '%s\n' "${_agroups}" | grep -Eq '(^|[[:space:]])wheel($|[[:space:]])' \
  && fail "aios-agent is in wheel"

denied_to_work /srv/aios/envelope
denied_to_work /srv/aios/state
denied_to_work /srv/aios/git
denied_to_work /usr/lib/aios/bin/enact

if [ -f /etc/sudoers.d/aios-work ]; then
  fail "aios-work has sudoers (HI-13)"
fi
if [ -f /etc/sudoers ] && grep -Eq '^[[:space:]]*aios-work' /etc/sudoers 2>/dev/null; then
  fail "aios-work is in sudoers (HI-13)"
fi

if [ -S /run/aios/intent.sock ]; then
  _own=$(stat -c '%U' /run/aios/intent.sock)
  _grp=$(stat -c '%G' /run/aios/intent.sock)
  _mod=$(stat -c '%a' /run/aios/intent.sock)
  [ "${_own}" = aios-agent ] || fail "intent.sock owner is ${_own}, not aios-agent (L-05)"
  [ "${_grp}" = aios-work ] || fail "intent.sock group is ${_grp}, not aios-work (L-05)"
  [ "${_mod}" = 660 ] || fail "intent.sock mode is ${_mod}, not 660 (L-05)"
fi

# Envelope bit default off: a live work tree without an explicit yes is undeclared.
_ans=/srv/aios/state/bootstrap-in-progress/answers.json
_yes=0
if [ -f "${_ans}" ] \
  && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}" \
  && grep -Eq '"work_runtime"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
  _yes=1
fi
if [ "${_yes}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "/srv/aios/src exists while work-runtime is not an explicit yes (HI-15)"
fi

exit 0
