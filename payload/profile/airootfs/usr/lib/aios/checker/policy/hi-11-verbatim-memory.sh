#!/bin/sh
# HI-11: a model summary in place of the raw exchange is curated memory.
set -eu

fail() {
  printf 'HI-11: %s\n' "$*" >&2
  exit 1
}

WT=/srv/aios/memory
BARE=/srv/aios/git/memory.git
[ -d "${BARE}/objects" ] || fail "memory.git missing"
git --git-dir="${BARE}" rev-parse --verify main >/dev/null 2>&1 \
  || fail "memory.git has no main"
[ -d "${WT}" ] || fail "memory worktree missing"

# Firstboot leaves README only. Exchange files, once present, must keep the raw turn.
for _f in "${WT}"/exchanges/* "${WT}"/moments/*; do
  [ -f "${_f}" ] || continue
  [ -s "${_f}" ] || fail "empty memory file ${_f}"
  _lines=$(wc -l <"${_f}" | tr -d ' ')
  if grep -Eq '^[[:space:]]*(Summary|TL;DR|model summary)[[:space:]]*:' "${_f}"; then
    grep -Eq 'asked:|operator:|human:|"asked"|user:' "${_f}" \
      || fail "${_f} is a summary without the raw exchange"
  fi
  [ "${_lines}" -ge 1 ] || fail "${_f} has no content"
done

exit 0
