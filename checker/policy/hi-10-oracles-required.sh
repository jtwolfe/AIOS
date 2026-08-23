#!/bin/sh
# HI-10: a diff with a story is not a proposal.
set -eu

fail() {
  printf 'HI-10: %s\n' "$*" >&2
  exit 1
}

SCHEMA=/srv/aios/checker/aios_checker/schema.py
[ -f "${SCHEMA}" ] || fail "schema.py missing"
grep -q 'oracles must be a non-empty list (HI-10)' "${SCHEMA}" \
  || fail "schema.py does not reject an empty oracle set"
grep -q 'oracles missing (HI-10)' "${SCHEMA}" \
  || fail "schema.py does not reject a missing oracle set"

PROP=/srv/aios/state/proposals
if [ -d "${PROP}" ]; then
  for _p in "${PROP}"/*.json; do
    [ -f "${_p}" ] || continue
    grep -q '"oracles"' "${_p}" || fail "${_p} has no oracles"
    grep -Eq '"oracles"[[:space:]]*:[[:space:]]*\[\]' "${_p}" \
      && fail "${_p} has an empty oracle set"
    grep -q '"intent"' "${_p}" || fail "${_p} has no intent"
  done
fi

exit 0
