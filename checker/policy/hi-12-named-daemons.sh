#!/bin/sh
# HI-12: an unnamed daemon is a parallel architecture.
set -eu

fail() {
  printf 'HI-12: %s\n' "$*" >&2
  exit 1
}

named() {
  case "$1" in
    aios-agent.service|aios-checker.service|aios-installer.service) return 0 ;;
    aios-intent.socket|aios-work.slice) return 0 ;;
    aios-work-runtime.service|aios-work-runtime-bots.service) return 0 ;;
    *) return 1 ;;
  esac
}

[ -f /etc/systemd/system/aios-checker.service ] \
  || fail "aios-checker.service missing"
[ -f /etc/systemd/system/aios-installer.service ] \
  || fail "aios-installer.service missing"

[ ! -e /etc/systemd/system/aios-firstboot.service ] \
  || fail "aios-firstboot.service is not a named unit"
[ ! -e /etc/systemd/system/aios-installer-serial.service ] \
  || fail "aios-installer-serial.service is not a named unit"
[ ! -e /etc/systemd/system/aios-work-runtime.service ] \
  || fail "aios-work-runtime.service must not be a system unit (L-23)"
[ ! -e /etc/systemd/system/aios-work-runtime-bots.service ] \
  || fail "aios-work-runtime-bots.service must not be a system unit (L-23)"
[ ! -e /usr/lib/systemd/system/aios-work-runtime.service ] \
  || fail "aios-work-runtime.service must not be a system unit (L-23)"
[ ! -e /usr/lib/systemd/system/aios-work-runtime-bots.service ] \
  || fail "aios-work-runtime-bots.service must not be a system unit (L-23)"

LIST=$(mktemp)
trap 'rm -f "${LIST}"' EXIT
: >"${LIST}"
for _dir in /etc/systemd/system /usr/lib/systemd/system /usr/lib/systemd/user; do
  [ -d "${_dir}" ] || continue
  find "${_dir}" -maxdepth 1 \( \
    -name 'aios-*.service' -o -name 'aios-*.socket' -o -name 'aios-*.slice' \
    -o -name 'aios-*.timer' -o -name 'aios-*.target' -o -name 'aios-*.path' \
    \) \( -type f -o -type l \) -print >>"${LIST}" 2>/dev/null || true
done

while IFS= read -r _u; do
  [ -n "${_u}" ] || continue
  _b=${_u##*/}
  named "${_b}" || fail "unnamed unit ${_b}"
  case "${_u}" in
    /etc/systemd/system/aios-work-runtime.service|/usr/lib/systemd/system/aios-work-runtime.service)
      fail "aios-work-runtime.service must not be a system unit (L-23)"
      ;;
    /etc/systemd/system/aios-work-runtime-bots.service|/usr/lib/systemd/system/aios-work-runtime-bots.service)
      fail "aios-work-runtime-bots.service must not be a system unit (L-23)"
      ;;
  esac
done <"${LIST}"

exit 0
