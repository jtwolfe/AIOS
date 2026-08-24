#!/bin/sh
# P8.14 / P8.5: follow without reading the skill body this turn fails.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ -f /srv/aios/src/work-runtime/skills.py ] \
    || [ -f /srv/aios/src/work-runtime/main.py ] \
    || die "guest missing work-runtime skill follow (P8.5)"
  printf 'ok: vm-work-skill (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-skill
p814_payload_no_src
p814_drive_installer
p814_drive_tui work work_commands
p814_must_close skill
p814_finish
