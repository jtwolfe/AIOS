#!/bin/sh
# HI-04: unsigned root install is not reconstructible.
set -eu

fail() {
  printf 'no-curl-sh: %s\n' "$*" >&2
  exit 1
}

# Pieces stay on separate lines so this file does not match the assembled pattern.
_fetch='cur''l|wge''t|fetch'
_shell='(ba)?sh'
_bar='\|'
# Optional argv between the fetcher and the pipe (tight form or with flags).
_pre="(${_fetch})([[:space:]].*)?"
_suf="[[:space:]]*(sudo[[:space:]]+)?${_shell}"
PIPE_RE="${_pre}${_bar}${_suf}"

scan_file() {
  _f=$1
  [ -f "${_f}" ] || return 0
  case "${_f}" in
    *no-curl-sh.sh) return 0 ;;
  esac
  grep -E -q -- "${PIPE_RE}" "${_f}" && fail "pipe-to-shell in ${_f} (HI-04)"
  return 0
}

[ -x /usr/lib/aios/bin/firstboot ] || fail "firstboot missing; cannot audit Harness A"

scan_file /root/.bash_history
scan_file /root/.ash_history
scan_file /root/.history
scan_file /var/log/aios-firstboot.log
scan_file /usr/lib/aios/bin/firstboot
scan_file /usr/lib/aios/bin/installer
scan_file /usr/lib/aios/bin/enact

for _d in /usr/lib/aios /srv/aios/agent /srv/aios/checker /srv/aios/state; do
  [ -d "${_d}" ] || continue
  _hit=$(grep -R -E -l --exclude='no-curl-sh.sh' --exclude='*.md' -- "${PIPE_RE}" "${_d}" 2>/dev/null | head -n 1 || true)
  [ -z "${_hit}" ] || fail "pipe-to-shell in ${_hit} (HI-04)"
done

if [ -f /var/log/pacman.log ]; then
  grep -E -q -- "${PIPE_RE}" /var/log/pacman.log \
    && fail "pipe-to-shell in pacman.log (HI-04)"
fi

exit 0
