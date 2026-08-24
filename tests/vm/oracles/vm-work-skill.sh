#!/bin/sh
# P8.14 / P8.5: follow without reading the skill body this turn fails.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ -f /srv/aios/src/work-runtime/AGENTS.md ] \
    || [ -f /srv/aios/seeds/work-runtime/AGENTS.md ] \
    || die "guest missing work AGENTS.md"
  printf 'ok: vm-work-skill (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-skill
p814_payload_no_src
grep -q 'Read a skill body in the current turn before following it' \
  "${SEED}/AGENTS.md" \
  || die "AGENTS.md must require this-turn skill read"
grep -q 'Read a body before following it' "${SEED}/skills/wake.md" \
  || die "wake.md must require read-before-follow"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: skills$' \
  || die "skills view missing: ${P814_TUI_OUT}"

p814_wrap_p8 skill
p814_finish
