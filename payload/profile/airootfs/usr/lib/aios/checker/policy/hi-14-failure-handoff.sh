#!/bin/sh
# HI-14: a unit failure without unit/journal/commit/snapper/clause is not a handoff.
set -eu

fail() {
  printf 'HI-14: %s\n' "$*" >&2
  exit 1
}

[ -d /srv/aios/state ] || fail "state tree missing; cannot record an HI-14 payload"

has_field() {
  _f=$1
  _pat=$2
  grep -Eq "${_pat}" "${_f}"
}

payload_ok() {
  _f=$1
  [ -s "${_f}" ] || fail "empty HI-14 payload ${_f}"
  has_field "${_f}" '"unit"|"executable"' \
    || fail "${_f} missing unit or executable"
  has_field "${_f}" '"journal"|"journal_slice"' \
    || fail "${_f} missing journal slice"
  has_field "${_f}" '"commit"|"state_commit"' \
    || fail "${_f} missing state commit"
  has_field "${_f}" '"snapper"|"snapper_id"' \
    || fail "${_f} missing snapper id"
  has_field "${_f}" '"clause"' \
    || fail "${_f} missing envelope clause"
}

N=0
for _dir in /run/aios/notify /srv/aios/state/notify /srv/aios/memory/notify; do
  [ -d "${_dir}" ] || continue
  for _f in "${_dir}"/*; do
    [ -f "${_f}" ] || continue
    payload_ok "${_f}"
    N=$((N + 1))
  done
done

# A failed aios unit with no payload is a missing handoff. Other units are not HI-14.
if command -v systemctl >/dev/null 2>&1; then
  FAILED=$(systemctl --failed --plain --no-legend 2>/dev/null || true)
  if [ -n "${FAILED}" ]; then
    _aios=$(printf '%s\n' "${FAILED}" | awk '{print $1}' | grep -E '^aios-' | tr '\n' ' ' || true)
    _aios=$(printf '%s' "${_aios}" | sed 's/[[:space:]]*$//')
    if [ -n "${_aios}" ] && [ "${N}" -eq 0 ]; then
      fail "failed aios unit without an HI-14 payload: ${_aios}"
    fi
  fi
fi

exit 0
