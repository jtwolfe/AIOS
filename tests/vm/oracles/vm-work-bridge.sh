#!/bin/sh
# P8.14 / P8.9: private path blocked until approval. Verbatim copy, not a mount.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  UNIT=/usr/lib/systemd/user/aios-work-runtime.service
  [ -f "${UNIT}" ] || die "guest missing user unit (bridge write set)"
  if grep '^ReadWritePaths=' "${UNIT}" | grep -Eq '/home|~/src'; then
    die "guest write set includes the bridge path"
  fi
  printf 'ok: vm-work-bridge (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-bridge
p814_payload_no_src
p814_drive_installer
p814_drive_tui work work_commands
p814_must_close bridge
p814_finish
