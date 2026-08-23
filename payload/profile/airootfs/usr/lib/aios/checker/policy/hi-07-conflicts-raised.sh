#!/bin/sh
# HI-07: instruction vs hard invariant must become a record, not a silent pass.
set -eu

fail() {
  printf 'HI-07: %s\n' "$*" >&2
  exit 1
}

record_ok() {
  _f=$1
  [ -s "${_f}" ] || fail "empty conflict record ${_f}"
  grep -Eq 'HI-[0-9]{2}' "${_f}" || fail "${_f} does not name a hard invariant"
}

[ -f /srv/aios/envelope/hard-invariants.md ] \
  || fail "hard-invariants.md missing; cannot judge raised conflicts"

# Existing records must be checkable. Missing dir means no conflict has been raised yet.
for _dir in /srv/aios/state/conflicts /srv/aios/memory/conflicts; do
  [ -d "${_dir}" ] || continue
  for _f in "${_dir}"/*; do
    [ -f "${_f}" ] || continue
    record_ok "${_f}"
  done
done

# A refused proposal that names a clause conflict must have a matching record.
PROP=/srv/aios/state/proposals
if [ -d "${PROP}" ]; then
  for _p in "${PROP}"/*.json; do
    [ -f "${_p}" ] || continue
    if grep -Eq '"accepted"[[:space:]]*:[[:space:]]*false' "${_p}" \
      && grep -Eq 'conflict|HI-[0-9]{2}' "${_p}"; then
      _id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${_p}" | head -n 1)
      _found=0
      for _dir in /srv/aios/state/conflicts /srv/aios/memory/conflicts; do
        [ -d "${_dir}" ] || continue
        if [ -n "${_id}" ] && [ -f "${_dir}/${_id}" ]; then
          _found=1
        fi
        _hit=$(grep -l -F -- "${_id}" "${_dir}"/* 2>/dev/null | head -n 1 || true)
        [ -z "${_hit}" ] || _found=1
      done
      [ "${_found}" -eq 1 ] \
        || fail "proposal ${_p} refused on conflict without a conflict record"
    fi
  done
fi

exit 0
