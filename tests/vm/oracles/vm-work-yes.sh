#!/bin/sh
# P8.14 / P8.1: synthesis from local seeds with nic down. HI-15 HI-17.
# Host: drive work-yes.json + wrap p8-synthesis.sh. Do not synthesise in the ISO.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree >/dev/null \
    || die "guest missing work-runtime git (HI-17)"
  [ -f /srv/aios/src/work-runtime/AGENTS.md ] \
    || die "guest work-runtime missing AGENTS.md"
  [ ! -f /etc/systemd/system/aios-work-runtime.service ] \
    || die "guest grew a system work unit (L-23)"
  printf 'ok: vm-work-yes (guest). HI-15 HI-17.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-yes
p814_payload_no_src
grep -q '/srv/aios/src must not exist' \
  "${AIROOTFS}/usr/lib/aios/bin/firstboot" \
  || die "firstboot must refuse /srv/aios/src (HI-15)"
if grep -q 'enable aios-work' "${AIROOTFS}/usr/lib/aios/bin/firstboot"; then
  die "firstboot must not enable work units"
fi

p814_drive_installer
printf '%s\n' "${P814_INSTALL_OUT}" | grep -q 'work-runtime: true' \
  || die "work-yes must set work-runtime true: ${P814_INSTALL_OUT}"
printf '%s\n' "${P814_INSTALL_OUT}" | grep -q 'envelope-decision: accepted' \
  || die "work-yes accept missing: ${P814_INSTALL_OUT}"
p814_answers_python <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is not True:
    raise SystemExit("work_runtime must be JSON true")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots must be absent or false")
if data.get("accepted") is not True:
    raise SystemExit("accepted must be true")
PY
[ ! -e "${P814_DEST}/srv/aios/src" ] \
  || die "installer synthesised destroot /srv/aios/src"

p814_wrap_p8_required synthesis
p814_finish
