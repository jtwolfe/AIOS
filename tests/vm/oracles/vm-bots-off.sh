#!/bin/sh
# P8.14 / P8.13: work-runtime yes does not start bots. Second bit default off.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ ! -f /etc/systemd/system/aios-work-runtime-bots.service ] \
    || die "guest has system bots unit (L-23)"
  _en=$(systemctl --user -M aios-work@ is-enabled \
    aios-work-runtime-bots.service 2>/dev/null || true)
  _ac=$(systemctl --user -M aios-work@ is-active \
    aios-work-runtime-bots.service 2>/dev/null || true)
  [ "${_en}" != enabled ] || die "guest bots is-enabled with bit off (HI-15)"
  [ "${_ac}" != active ] || die "guest bots is-active with bit off (HI-15)"
  [ ! -e /srv/aios/src/work-runtime-bots ] \
    || die "guest synthesised bots with second bit off"
  printf 'ok: vm-bots-off (guest). HI-15.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin bots-off
p814_payload_no_src
[ ! -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime-bots.service" ] \
  || die "bots must not be a system unit (L-23)"

p814_drive_installer
p814_answers_python <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is not True:
    raise SystemExit("work_runtime must be JSON true")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots must be absent or false")
if data.get("bots") is True:
    raise SystemExit("bots must never be a yes")
PY
[ ! -e "${P814_DEST}/srv/aios/src/work-runtime-bots" ] \
  || die "installer synthesised bots"

p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'bots-bit: off' \
  || die "envelope must show bots-bit off: ${P814_TUI_OUT}"

p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'HI-15' \
  || die "roster with bots bit off must quote HI-15: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: roster$' \
  && die "roster opened with bots bit off: ${P814_TUI_OUT}" || true

p814_wrap_p8_required bots-off
p814_finish
