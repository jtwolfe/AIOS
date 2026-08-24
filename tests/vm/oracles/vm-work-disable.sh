#!/bin/sh
# P8.14 / P8.12: disable is an envelope patch; stop units, leave git (HI-15).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ ! -f /etc/systemd/system/aios-work-runtime.service ] \
    || die "guest has system work unit (L-23)"
  if [ -d /srv/aios/src/work-runtime/.git ]; then
    git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null \
      || die "disable left a non-git work tree"
  fi
  printf 'ok: vm-work-disable (guest). HI-15.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-disable
p814_payload_no_src
grep -q 'Disable is an envelope patch' "${SEED}/envelope/work-runtime.md" \
  || die "seed envelope must describe disable as an envelope patch"
grep -q 'leave git' "${SEED}/envelope/work-runtime.md" \
  || die "seed envelope must leave git"
grep -q 'disable' "${AIROOTFS}/usr/lib/aios/bin/enact" \
  || die "enact must grow a disable verb"

p814_drive_installer
p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: envelope$' \
  || die "disable envelope view missing: ${P814_TUI_OUT}"

p814_wrap_p8_required disable
p814_finish
