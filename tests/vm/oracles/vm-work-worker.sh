#!/bin/sh
# P8.14 / P8.7: worker has no user-visible voice; result is sent; cannot enact.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  command -v systemd-run >/dev/null 2>&1 \
    || die "systemd-run missing; worker cannot-enact must fail closed"
  id -u aios-work >/dev/null 2>&1 \
    || die "aios-work uid missing; worker cannot-enact must fail closed"
  [ -e /usr/lib/aios/bin/enact ] || die "missing /usr/lib/aios/bin/enact"
  [ -f /etc/systemd/system/aios-work.slice ] \
    || die "live aios-work.slice missing; worker cannot-enact must fail closed"
  [ -d /srv/aios/src/work-runtime ] \
    || die "guest missing work-runtime (worker surface)"
  _probe=aios-work-worker-probe.service
  systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
  if ! systemd-run --quiet --service-type=oneshot --remain-after-exit \
    --uid=aios-work --gid=aios-work \
    --slice=aios-work.slice \
    --unit="${_probe}" \
    /usr/bin/true; then
    systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
    die "could not start aios-work slice probe (worker)"
  fi
  systemctl stop "${_probe}" >/dev/null 2>&1 || true
  systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
  _xout=$(systemd-run --quiet --wait --pipe --collect \
    --uid=aios-work --gid=aios-work \
    --slice=aios-work.slice \
    --unit=aios-work-worker-x.service \
    /usr/bin/test -x /usr/lib/aios/bin/enact 2>&1) && _xrc=0 || _xrc=$?
  [ "${_xrc}" != 0 ] || die "worker slice can execute enact: ${_xout}"
  printf 'ok: vm-work-worker (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-worker
p814_payload_no_src
p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'enact refused in work session (L-14)' \
  || die "worker turn must not enact: ${P814_TUI_OUT}"
p814_must_close worker workers
p814_finish
