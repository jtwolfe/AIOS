#!/bin/sh
# HI-06: /etc without history is not a seatbelt.
set -eu

fail() {
  printf 'etckeeper-enabled: %s\n' "$*" >&2
  exit 1
}

command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Q etckeeper >/dev/null 2>&1 || fail "etckeeper is not installed"
command -v etckeeper >/dev/null 2>&1 || fail "etckeeper binary missing"

[ -f /etc/etckeeper/etckeeper.conf ] || fail "etckeeper.conf missing"
grep -Eq '^[[:space:]]*VCS=["'\'']?git["'\'']?' /etc/etckeeper/etckeeper.conf \
  || fail "etckeeper VCS is not git"

# Pacman hook is the Arch path; without it, /etc drifts across -Syu.
_hook=
for _h in \
  /usr/share/libalpm/hooks/etckeeper-pre-install.hook \
  /usr/share/libalpm/hooks/etckeeper.hook \
  /usr/share/libalpm/hooks/zz-etckeeper.hook \
  /etc/pacman.d/hooks/etckeeper.hook
do
  if [ -f "${_h}" ]; then
    _hook=${_h}
    break
  fi
done
if [ -z "${_hook}" ]; then
  _found=$(find /usr/share/libalpm/hooks /etc/pacman.d/hooks -name '*etckeeper*' -type f 2>/dev/null | head -n 1 || true)
  [ -n "${_found}" ] || fail "etckeeper pacman hook missing"
fi

[ -d /srv/aios/etc-mirror/objects ] || fail "etc-mirror git missing"
git --git-dir=/srv/aios/etc-mirror rev-parse --verify HEAD >/dev/null 2>&1 \
  || fail "etc-mirror has no HEAD"

# Live /etc/.git is often root-only; the mirror is the reconstructible copy.
if [ -x /usr/bin/etckeeper ] && [ -r /etc/.git/HEAD ]; then
  _st=$(etckeeper vcs status --porcelain 2>/dev/null || true)
  [ -z "${_st}" ] || fail "etckeeper worktree is dirty"
fi

exit 0
