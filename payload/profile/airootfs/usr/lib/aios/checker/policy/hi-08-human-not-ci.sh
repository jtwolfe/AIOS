#!/bin/sh
# HI-08: closing a turn with "run this and tell me" uses the human as CI.
set -eu

fail() {
  printf 'HI-08: %s\n' "$*" >&2
  exit 1
}

SCHEMA=/srv/aios/checker/aios_checker/schema.py
[ -f "${SCHEMA}" ] || fail "schema.py missing"
grep -q 'evidence.ran is required (HI-08)' "${SCHEMA}" \
  || fail "schema.py does not require evidence.ran"
grep -q 'evidence.ran must be a non-empty list (HI-08)' "${SCHEMA}" \
  || fail "schema.py allows empty evidence.ran"

PROP=/srv/aios/state/proposals
if [ -d "${PROP}" ]; then
  for _p in "${PROP}"/*.json; do
    [ -f "${_p}" ] || continue
    grep -q '"evidence"' "${_p}" || fail "${_p} has no evidence (HI-08)"
    grep -Eq '"ran"[[:space:]]*:[[:space:]]*\[\]' "${_p}" \
      && fail "${_p} has empty evidence.ran"
    grep -q '"ran"' "${_p}" || fail "${_p} has no evidence.ran"
  done
fi

TELL='tell me if|run this and tell me|please run this and'
for _d in /srv/aios/state/proposals /srv/aios/memory; do
  [ -d "${_d}" ] || continue
  _hit=$(grep -R -E -l -- "${TELL}" "${_d}" 2>/dev/null | head -n 1 || true)
  [ -z "${_hit}" ] || fail "human-as-CI wording in ${_hit}"
done

exit 0
