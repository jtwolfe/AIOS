#!/bin/sh
# P8.14 / P8.11: work store is git in the work tree, not /srv/aios/memory.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null \
    || die "guest work-runtime is not git"
  if [ -d /srv/aios/memory/.git ]; then
    if git -C /srv/aios/memory ls-files | grep -E '(^|/)(routines|connectors)(/|$)'; then
      die "memory git tracks routines or connectors"
    fi
  fi
  printf 'ok: vm-work-store (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-store
p814_payload_no_src
[ -d "${SEED}/notes" ] || die "seed missing notes/"
[ -d "${SEED}/skills" ] || die "seed missing skills/"
[ -d "${SEED}/routines" ] || die "seed missing routines/"
[ -d "${SEED}/connectors" ] || die "seed missing connectors/"
grep -q 'not `/srv/aios/memory`' "${SEED}/notes/README.md" \
  || die "notes must name /srv/aios/memory as not-the-store"
grep -q 'Work store (notes, skills, routines, connectors) is git in this tree' \
  "${SEED}/AGENTS.md" \
  || die "AGENTS.md must lock the work store"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: store$' \
  || die "store view missing: ${P814_TUI_OUT}"

p814_wrap_p8_required store
p814_finish
