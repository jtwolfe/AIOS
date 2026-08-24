#!/bin/sh
# P8.14 / P8.6: token-in-chat fails; OS key unreadable.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  command -v sudo >/dev/null 2>&1 || die "sudo missing; OS key isolation cannot fail closed"
  id -u aios-work >/dev/null 2>&1 || die "aios-work uid missing; OS key isolation cannot fail closed"
  _token=/srv/aios/state/provider/os.token
  if sudo -u aios-work test -r "${_token}"; then
    die "aios-work can read OS token (L-16)"
  fi
  printf 'ok: vm-work-connector (guest). L-16.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-connector
p814_payload_no_src
p814_drive_installer
p814_drive_tui work work_commands
p814_must_close connector connectors
p814_wrap_host_required "${P814_ROOT}/tests/oracles/p4-provider.sh"
p814_finish
