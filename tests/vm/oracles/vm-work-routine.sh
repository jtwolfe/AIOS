#!/bin/sh
# P8.14 / P8.8: a routine is cron xor listeners, never both.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ -d /srv/aios/src/work-runtime/routines ] \
    || die "guest missing work-runtime routines store"
  git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null \
    || die "guest work tree is not git"
  printf 'ok: vm-work-routine (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-routine
p814_payload_no_src
p814_drive_installer
p814_drive_tui work work_commands
p814_must_close routine routines
p814_finish
