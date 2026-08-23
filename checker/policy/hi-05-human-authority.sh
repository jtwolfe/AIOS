#!/bin/sh
# HI-05: a hard-invariant patch without a recorded human accept is not layer one.
set -eu

fail() {
  printf 'HI-05: %s\n' "$*" >&2
  exit 1
}

HI=/srv/aios/envelope/hard-invariants.md
BARE=/srv/aios/git/envelope.git

[ -f "${HI}" ] || fail "hard-invariants.md missing"
[ -d "${BARE}/objects" ] || fail "envelope.git missing"

_i=1
while [ "${_i}" -le 17 ]; do
  _id=$(printf 'HI-%02d' "${_i}")
  grep -q "${_id}" "${HI}" || fail "canonical file missing ${_id}"
  _i=$((_i + 1))
done

git --git-dir="${BARE}" cat-file -e main:hard-invariants.md \
  || fail "hard-invariants.md is not on envelope main"

# Firstboot's initial commit is payload materialisation, not a definition-surface
# patch. A later blob change needs an accept record (answers.json or state/accepts).
N=$(git --git-dir="${BARE}" log --follow --pretty=%H -- hard-invariants.md 2>/dev/null | wc -l | tr -d ' ')
[ -n "${N}" ] || N=0
if [ "${N}" -gt 1 ]; then
  _ok=0
  _ans=/srv/aios/state/bootstrap-in-progress/answers.json
  if [ -f "${_ans}" ] && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
    _ok=1
  fi
  if [ -d /srv/aios/state/accepts ]; then
    _any=$(find /srv/aios/state/accepts -type f 2>/dev/null | head -n 1 || true)
    [ -z "${_any}" ] || _ok=1
  fi
  [ "${_ok}" -eq 1 ] \
    || fail "hard-invariants.md changed without a recorded human accept"
fi

exit 0
