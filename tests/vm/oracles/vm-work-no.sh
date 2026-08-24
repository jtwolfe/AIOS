#!/bin/sh
# P8.14 / P8.1: HI-15. Skip is not a yes. Work summon refused. No units.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  # HI-15: skip is not a yes; no work units; tree absent or inert.
  [ ! -f /etc/systemd/system/aios-work-runtime.service ] \
    || die "guest has system aios-work-runtime.service (L-23)"
  _en=$(systemctl --user -M aios-work@ is-enabled aios-work-runtime.service \
    2>/dev/null || true)
  _ac=$(systemctl --user -M aios-work@ is-active aios-work-runtime.service \
    2>/dev/null || true)
  [ "${_en}" != enabled ] || die "guest work-runtime is-enabled (HI-15)"
  [ "${_ac}" != active ] || die "guest work-runtime is-active (HI-15)"
  printf 'ok: vm-work-no (guest). HI-15.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-no
p814_payload_no_src

p814_drive_installer
printf '%s\n' "${P814_INSTALL_OUT}" | grep -q 'skip: not-yes' \
  || die "work-no skip work-runtime must be not-yes: ${P814_INSTALL_OUT}"
printf '%s\n' "${P814_INSTALL_OUT}" | grep -q 'work-runtime: true' \
  && die "work-no must not set work-runtime true (HI-15): ${P814_INSTALL_OUT}" \
  || true
printf '%s\n' "${P814_INSTALL_OUT}" | grep -q 'work-runtime: false' \
  || die "work-no work-runtime must stay false: ${P814_INSTALL_OUT}"
p814_answers_python <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime true")
if data.get("work_runtime") is not False:
    raise SystemExit("work_runtime must be JSON false")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots must be absent or false")
PY
[ ! -e "${P814_DEST}/srv/aios/src" ] \
  || die "work-no synthesised destroot /srv/aios/src"

_work=$(
  AIOS_ANSWERS="${P814_BOOT}/answers.json" AIOS_BRAKE="${P814_BRAKE}" \
    python3 -u "${TUI}" work
) && _wrc=0 || _wrc=$?
[ "${_wrc}" != 0 ] || die "aios work must be refused with bit off: ${_work}"
printf '%s\n' "${_work}" | grep -q 'HI-15' \
  || die "aios work must quote HI-15: ${_work}"
printf '%s\n' "${_work}" | grep -q '^mode: work$' \
  && die "aios work opened a work session with bit off: ${_work}" || true

p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT:-}" | grep -q 'HI-15' \
  || die "work_commands with bit off must quote HI-15: ${P814_TUI_OUT:-}"

mkdir -p "${P814_TMP}/empty"
AIOS_POLICY_ROOT="${P814_TMP}/empty" \
  "${P814_ROOT}/checker/policy/hi-15-work-default-off.sh" \
  || die "hi-15-work-default-off.sh failed against empty destroot"
p814_finish
