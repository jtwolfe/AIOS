#!/bin/sh
# P8.14 / P8.8: a routine is cron xor listeners, never both. Persisted in
# the work store. Disable leaves git.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  if [ -d /srv/aios/src/work-runtime ]; then
    git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null \
      || die "guest work tree is not git"
  fi
  printf 'ok: vm-work-routine (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-routine
p814_payload_no_src
[ -f "${SEED}/routines/README.md" ] || die "missing seed routines/README.md"
grep -q 'Cron or listeners, never both' "${SEED}/routines/README.md" \
  || die "routines README must lock cron xor listeners"
grep -q 'Cron or listeners, never both' "${SEED}/boundaries/interfaces.md" \
  || die "interfaces.md must lock cron xor listeners"
grep -q '/srv/aios/memory' "${SEED}/routines/README.md" \
  || die "routines must not live in /srv/aios/memory"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: store$' \
  || die "routine store view missing: ${P814_TUI_OUT}"

p814_wrap_p8 routine
p814_wrap_p8 routines
p814_finish
