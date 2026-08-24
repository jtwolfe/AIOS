#!/bin/sh
# P8.14 / P8.13: job is path+slice+skill; virsh from the slice fails;
# VM start is an intent. Live tree only when the second bit is on.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  git -C /srv/aios/src/work-runtime-bots rev-parse --is-inside-work-tree \
    >/dev/null || die "guest missing bots git (second bit on)"
  [ ! -f /etc/systemd/system/aios-work-runtime-bots.service ] \
    || die "guest grew a system bots unit (L-23)"
  printf 'ok: vm-bots-job (guest). HI-13 HI-15.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin bots-job
p814_payload_no_src
JOB="${P814_ROOT}/seed/work-runtime-bots/jobs/build-guests.md"
[ -f "${JOB}" ] || die "missing bots job file"
grep -q 'path:' "${JOB}" || die "job file missing path"
grep -q 'slice:' "${JOB}" || die "job file missing slice"
grep -q 'skill:' "${JOB}" || die "job file missing skill"
grep -q 'intent' "${JOB}" || die "job file must name intent.sock"
grep -q 'virsh' "${JOB}" || die "job file must refuse virsh"

p814_drive_installer
p814_answers_python <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is not True:
    raise SystemExit("work_runtime must be JSON true")
if data.get("bots") is True:
    raise SystemExit("answers.json bots must never be a yes")
PY

p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'bots yes requested' \
  || die "OS envelope bots yes must write a request: ${P814_TUI_OUT}"
grep -qx yes "${P814_DEST}/run/aios/bots-request" \
  || die "bots yes must write destroot bots-request"
[ ! -f "${P814_DEST}/srv/aios/envelope/work-runtime-bots.md" ] \
  || die "TUI must not write the envelope clause"

p814_wrap_p8_required bots-job
p814_finish
