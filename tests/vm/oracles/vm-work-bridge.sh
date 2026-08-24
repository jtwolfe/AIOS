#!/bin/sh
# P8.14 / P8.9: private path blocked until approval. Verbatim copy, not a mount.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  UNIT=/usr/lib/systemd/user/aios-work-runtime.service
  if [ -f "${UNIT}" ]; then
    if grep '^ReadWritePaths=' "${UNIT}" | grep -Eq '/home|~/src'; then
      die "guest write set includes the bridge path"
    fi
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
[ -f "${SEED}/skills/bridge.md" ] || die "missing skills/bridge.md"
grep -q 'Access is approval-gated' "${SEED}/skills/bridge.md" \
  || die "bridge.md must require approval"
grep -q 'Copy is verbatim' "${SEED}/skills/bridge.md" \
  || die "bridge.md must copy verbatim"
grep -q 'mount' "${SEED}/skills/bridge.md" \
  || die "bridge.md must refuse a mount"
grep -q 'The command does not run until the human approves' \
  "${SEED}/skills/bridge.md" \
  || die "bridge.md must block until approval"
grep -q '~/src' "${SEED}/envelope/work-runtime.md" \
  || die "seed envelope must name ~/src as the bridge"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: bridge$' \
  || die "bridge view missing: ${P814_TUI_OUT}"

p814_wrap_p8 bridge
p814_finish
