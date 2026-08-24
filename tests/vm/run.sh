#!/bin/sh
# First useful loop harness (P9.1/P9.2). Still not the product (HI-08).
# Pre-boot minisign (L-10). Fail closed without KVM or ISO. Do not skip green.
# Full ISO boot is not claimed against a stale image.
#
# Usage: tests/vm/run.sh [probe|iso|disk|snap|smoke|recover|privilege-deny|boot-seatbelt|work-*|bots-*]
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
QEMU="${SCRIPT_DIR}/qemu.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"
PUB="${ROOT}/payload/minisign.pub"
DIST="${ROOT}/dist"
MAIN="${ROOT}/installer/aios_installer/main.py"
HI="${ROOT}/docs/envelope/hard-invariants.md"
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

find_iso() {
  _iso=
  _n=0
  for _f in "${DIST}"/aios-*.iso; do
    [ -f "${_f}" ] || continue
    _iso=${_f}
    _n=$((_n + 1))
  done
  [ "${_n}" -gt 0 ] || die "no dist/aios-*.iso; fail closed (do not skip green)"
  [ "${_n}" -eq 1 ] || die "multiple dist/aios-*.iso; leave one"
  printf '%s\n' "${_iso}"
}

# smoke/recover minisign before boot (L-10). Unsigned ISO must not reach qemu
# on those paths. iso|disk is a raw qemu.sh passthrough and does not minisign.
minisign_iso() {
  _iso=$(find_iso)
  command -v minisign >/dev/null 2>&1 || die "minisign missing; fail closed (L-10)"
  [ -f "${PUB}" ] || die "missing ${PUB}"
  minisign -Vm "${_iso}" -p "${PUB}" \
    || die "ISO unsigned or minisign failed (L-10); fail closed"
}

json_list() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
val = data.get(key)
if val is None:
    raise SystemExit("missing %s" % key)
if not isinstance(val, list):
    raise SystemExit("%s must be a list" % key)
for item in val:
    if not isinstance(item, str) or not item.strip():
        raise SystemExit("command must be a non-empty string")
    sys.stdout.write("%s\n" % item)
PY
}

drive_json() {
  _boot=$1
  _root=$2
  _file=$3
  _key=$4
  mkdir -p "${_boot}" "${_root}"
  _cmds="${TMP}/cmds.$$"
  json_list "${_file}" "${_key}" > "${_cmds}"
  AIOS_BOOTSTRAP="${_boot}" AIOS_ROOT="${_root}" \
    AIOS_HI="${HI}" python3 -u "${MAIN}" < "${_cmds}"
}

assert_no_live_bip() {
  if [ "${_LIVE_BIP_EXISTED}" -eq 0 ] && [ -e "${_LIVE_BIP}" ]; then
    die "harness created ${_LIVE_BIP} (HI-09)"
  fi
}

host_smoke() {
  _boot="${TMP}/smoke-boot"
  _root="${TMP}/smoke-root"
  _out=$(drive_json "${_boot}" "${_root}" "${FIXTURES}/smoke.json" commands) || true
  if printf '%s\n' "${_out}" | grep -q Traceback; then
    die "smoke fixture traceback: ${_out}"
  fi
  printf '%s\n' "${_out}" | grep -q 'skip: not-yes' \
    || die "smoke skip work-runtime must be not-yes: ${_out}"
  printf '%s\n' "${_out}" | grep -q 'work-runtime: true' \
    && die "smoke must not set work-runtime true (HI-15): ${_out}" || true
  printf '%s\n' "${_out}" | grep -q 'work-runtime: false' \
    || die "smoke work-runtime must stay false (HI-15): ${_out}"
  printf '%s\n' "${_out}" | grep -q 'operator: alice' \
    || die "smoke must ask operator login (L-13): ${_out}"
  printf '%s\n' "${_out}" | grep -q 'envelope-decision: accepted' \
    || die "smoke accept missing: ${_out}"
  [ -f "${_boot}/answers.json" ] || die "smoke missing answers.json"
  python3 - "${_boot}/answers.json" <<'PY' || die "smoke answers.json"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime true")
if data.get("work_runtime") is not False:
    raise SystemExit("work_runtime must be JSON false")
if data.get("operator") != "alice":
    raise SystemExit("operator not asked")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots must be absent or false")
if data.get("accepted") is not True:
    raise SystemExit("accepted must be true")
PY
}

host_recover() {
  _boot="${TMP}/recover-boot"
  _root="${TMP}/recover-root"
  _out1=$(drive_json "${_boot}" "${_root}" "${FIXTURES}/recover.json" kill_after) || true
  if printf '%s\n' "${_out1}" | grep -q Traceback; then
    die "recover kill traceback: ${_out1}"
  fi
  printf '%s\n' "${_out1}" | grep -q 'purpose: a lab vm' \
    || die "recover kill missing purpose: ${_out1}"
  printf '%s\n' "${_out1}" | grep -q 'skip: not-yes' \
    || die "recover skip work-runtime must be not-yes: ${_out1}"
  printf '%s\n' "${_out1}" | grep -q 'work-runtime: true' \
    && die "recover kill must not set work-runtime true (HI-15): ${_out1}" || true
  printf '%s\n' "${_out1}" | grep -q 'work-runtime: false' \
    || die "recover kill work-runtime must stay false: ${_out1}"
  [ -f "${_boot}/answers.json" ] || die "recover missing answers.json after kill"
  python3 - "${_boot}/answers.json" <<'PY' || die "recover answers.json after kill"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime true after kill")
if data.get("work_runtime") is not False:
    raise SystemExit("work_runtime must be JSON false after kill")
if data.get("purpose") != "a lab vm":
    raise SystemExit("purpose not persisted")
if data.get("accepted") is True:
    raise SystemExit("accepted true before resume")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots must be absent or false")
PY
  _out2=$(drive_json "${_boot}" "${_root}" "${FIXTURES}/recover.json" resume) || true
  if printf '%s\n' "${_out2}" | grep -q Traceback; then
    die "recover resume traceback: ${_out2}"
  fi
  printf '%s\n' "${_out2}" | grep -q 'view: recovery' \
    || die "recover resume missing recovery view: ${_out2}"
  printf '%s\n' "${_out2}" | grep -q 'purpose: a lab vm' \
    || die "recover resume lost purpose: ${_out2}"
  printf '%s\n' "${_out2}" | grep -q 'work-runtime: true' \
    && die "recover resume must not turn skip into yes (HI-15): ${_out2}" || true
  printf '%s\n' "${_out2}" | grep -q 'work-runtime: false' \
    || die "recover resume work-runtime must stay false: ${_out2}"
  printf '%s\n' "${_out2}" | grep -q 'resume: last-step=' \
    || die "recover resume action missing: ${_out2}"
}

require_boot_env() {
  minisign_iso
  "${QEMU}" probe >/dev/null
}

cmd_smoke() {
  require_boot_env
  host_smoke
  assert_no_live_bip
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    exec "${QEMU}" iso
  fi
  printf 'ok: vm-smoke harness (pre-boot minisign). Full ISO boot not claimed.\n'
}

cmd_recover() {
  require_boot_env
  host_recover
  assert_no_live_bip
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    exec "${QEMU}" disk
  fi
  printf 'ok: vm-recover harness (kill/resume). Disk reboot not claimed.\n'
}

# P6.3. Guest denials live in oracles/vm-privilege-deny.sh (AIOS_VM_GUEST=1).
cmd_privilege_deny() {
  require_boot_env
  assert_no_live_bip
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    exec "${QEMU}" disk
  fi
  printf 'ok: vm-privilege-deny harness (pre-boot minisign). Full ISO boot not claimed.\n'
}

# P7.7 / L-19: fixture upgrade rollback path. Fail closed without ISO (do not skip green).
cmd_boot_seatbelt() {
  require_boot_env
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    exec "${QEMU}" disk
  fi
  printf 'ok: vm-boot-seatbelt harness (pre-boot minisign). Rollback boot not claimed.\n'
}

cmd_album() {
  _name=$1
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    require_boot_env
    exec "${QEMU}" disk
  fi
  printf 'ok: vm-%s harness. Full ISO boot not claimed.\n' "${_name}"
}

mode=${1:-probe}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
_LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
_LIVE_BIP_EXISTED=0
[ -e "${_LIVE_BIP}" ] && _LIVE_BIP_EXISTED=1

case "${mode}" in
  probe)
    exec "${QEMU}" probe
    ;;
  iso|disk)
    exec "${QEMU}" "${mode}"
    ;;
  snap)
    exec "${QEMU}" snap "${2:-pre}"
    ;;
  smoke)
    cmd_smoke
    ;;
  recover)
    cmd_recover
    ;;
  privilege-deny)
    cmd_privilege_deny
    ;;
  boot-seatbelt)
    cmd_boot_seatbelt
    ;;
  work-yes|work-no|work-write-set|work-surface|work-wake|work-skill|work-connector|work-worker|work-routine|work-bridge|work-store|work-provider|work-disable|bots-off|bots-job)
    cmd_album "${mode}"
    ;;
  -h|--help)
    printf 'usage: %s [probe|iso|disk|snap|smoke|recover|privilege-deny|boot-seatbelt|work-*|bots-*]\n' "$0"
    ;;
  *)
    die "usage: $0 [probe|iso|disk|snap|smoke|recover|privilege-deny|boot-seatbelt|work-*|bots-*]"
    ;;
esac
