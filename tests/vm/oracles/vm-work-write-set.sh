#!/bin/sh
# P8.14 / P8.2: L-15 write set. Write in set succeeds; outside without
# approval fails. Slice and user-unit ReadWritePaths match.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  UNIT=/usr/lib/systemd/user/aios-work-runtime.service
  [ -f "${UNIT}" ] || die "guest missing user unit (L-23)"
  grep -qx 'ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime' "${UNIT}" \
    || die "guest user unit ReadWritePaths is not the L-15 set"
  if grep '^ReadWritePaths=' "${UNIT}" | grep -Eq '/home|~/src'; then
    die "guest ReadWritePaths includes home"
  fi
  printf 'ok: vm-work-write-set (guest). L-15.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-write-set
p814_payload_no_src
UNIT="${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime.service"
FLOOR="${AIROOTFS}/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
[ -f "${UNIT}" ] || die "missing user unit (L-23)"
[ -f "${FLOOR}" ] || die "missing floor drop-in"
grep -qx 'ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime' "${UNIT}" \
  || die "user unit ReadWritePaths is not the L-15 set"
_rw_u=$(grep '^ReadWritePaths=' "${UNIT}")
_rw_f=$(grep '^ReadWritePaths=' "${FLOOR}")
[ "${_rw_u}" = "${_rw_f}" ] || die "user unit and floor ReadWritePaths disagree"
if grep '^ReadWritePaths=' "${UNIT}" | grep -Eq '/home|~/src'; then
  die "user unit ReadWritePaths includes home"
fi
grep -q '~/src' "${SEED}/envelope/work-runtime.md" \
  || die "seed envelope must name ~/src as the bridge"

p814_drive_installer
p814_wrap_p8_required writeset
p814_finish
