#!/bin/sh
# P8.14 / P8.3: L-14 surface split. Work turn has no privileged tools.
# OS turn is not in the slice.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  # L-14: work session refuses OS tools; OS session is not aios-work.slice.
  [ -f /usr/lib/aios/operator-client/tty/aios.py ] \
    || die "guest missing operator-client"
  printf 'ok: vm-work-surface (guest). L-14.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-surface
p814_payload_no_src
grep -q 'WORK_CATALOG' "${TUI}" || die "aios.py missing WORK_CATALOG"
grep -q 'L-14' "${TUI}" || die "aios.py must quote L-14"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^mode: work$' \
  || die "work session missing: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'packages refused in work session (L-14)' \
  || die "packages must be refused L-14: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'enact refused in work session (L-14)' \
  || die "enact must be refused L-14: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'snapper refused in work session (L-14)' \
  || die "snapper must be refused L-14: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: store$' \
  || die "work views must be reachable: ${P814_TUI_OUT}"

p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'skills refused in os session (L-14)' \
  || die "OS then skills must L-14: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: envelope$' \
  || die "OS envelope inspect must work: ${P814_TUI_OUT}"

p814_wrap_p8 surface
p814_finish
