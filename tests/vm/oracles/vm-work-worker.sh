#!/bin/sh
# P8.14 / P8.7: worker has no user-visible voice; result is sent; cannot enact.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ ! -x /usr/lib/aios/bin/enact ] || true
  printf 'ok: vm-work-worker (guest). HI-13.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-worker
p814_payload_no_src
grep -q 'Workers have no user-visible voice' "${SEED}/AGENTS.md" \
  || die "AGENTS.md must forbid worker voice"
grep -q 'No user voice' "${SEED}/boundaries/interfaces.md" \
  || die "interfaces.md must say workers have no user voice"
grep -q 'The work runtime does not enact privileged change' \
  "${SEED}/boundaries/interfaces.md" \
  || die "interfaces.md must forbid enact"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'enact refused in work session (L-14)' \
  || die "worker turn must not enact: ${P814_TUI_OUT}"

p814_wrap_p8 worker
p814_wrap_p8 workers
p814_finish
