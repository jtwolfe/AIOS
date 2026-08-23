#!/bin/sh
# HI-17: reconstruction must not wait on a remote for seed trees.
set -eu

fail() {
  printf 'HI-17: %s\n' "$*" >&2
  exit 1
}

[ -d /srv/aios/seeds/work-runtime ] || fail "seeds/work-runtime missing"
[ -d /srv/aios/seeds/work-runtime-bots ] || fail "seeds/work-runtime-bots missing"
[ -f /srv/aios/seeds/work-runtime/AGENTS.md ] \
  || fail "seeds/work-runtime/AGENTS.md missing"
[ -f /srv/aios/seeds/work-runtime-bots/AGENTS.md ] \
  || fail "seeds/work-runtime-bots/AGENTS.md missing"
[ -f /srv/aios/envelope/hard-invariants.md ] \
  || fail "envelope/hard-invariants.md missing"

BARE=/srv/aios/git/seeds.git
[ -d "${BARE}/objects" ] || fail "seeds.git missing"
git --git-dir="${BARE}" rev-parse --verify main >/dev/null 2>&1 \
  || fail "seeds.git has no main"
git --git-dir="${BARE}" cat-file -e main:work-runtime \
  || fail "seeds.git main lacks work-runtime"
git --git-dir="${BARE}" cat-file -e main:work-runtime-bots \
  || fail "seeds.git main lacks work-runtime-bots"

git --git-dir=/srv/aios/git/envelope.git cat-file -e main:hard-invariants.md \
  || fail "envelope.git main lacks hard-invariants.md"

# Origin must be the local bare repo, not GitHub.
_origin=$(git -C /srv/aios/seeds remote get-url origin 2>/dev/null || true)
[ "${_origin}" = /srv/aios/git/seeds.git ] \
  || fail "seeds origin is ${_origin:-missing}, not local seeds.git"

exit 0
