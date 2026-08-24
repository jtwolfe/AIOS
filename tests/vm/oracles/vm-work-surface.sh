#!/bin/sh
# P8.14 / P8.3: work turn has no privileged tools; OS turn is not in the slice.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ -f /usr/lib/aios/operator-client/tty/aios.py ] \
    || die "guest missing operator-client"
  _ans=/srv/aios/state/bootstrap-in-progress/answers.json
  [ -f "${_ans}" ] || die "guest missing answers.json; L-14 cannot fail closed"
  _out=$(
    printf '%s\n' 'view packages' 'enact' 'quit' \
      | AIOS_ANSWERS="${_ans}" AIOS_BRAKE=/tmp/aios-vm-surface-brake \
        python3 -u /usr/lib/aios/operator-client/tty/aios.py work
  ) || true
  printf '%s\n' "${_out}" | grep -q 'packages refused in work session (L-14)' \
    || die "guest work session must refuse packages (L-14): ${_out}"
  printf '%s\n' "${_out}" | grep -q 'enact refused in work session (L-14)' \
    || die "guest work session must refuse enact (L-14): ${_out}"
  printf 'ok: vm-work-surface (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-surface
p814_payload_no_src
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

p814_finish
