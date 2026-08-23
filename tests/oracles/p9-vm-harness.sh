#!/bin/sh
# P9.1/P9.2 host oracle: VM harness structure. Does not boot the ISO.
# qemu.sh probe fail-closed without KVM/OVMF. run.sh minisign before boot.
# Envelope: P9.1, P9.2, L-10, L-20, HI-08, HI-15.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
QEMU="${ROOT}/tests/vm/qemu.sh"
RUN="${ROOT}/tests/vm/run.sh"
SMOKE="${ROOT}/tests/vm/fixtures/smoke.json"
RECOVER="${ROOT}/tests/vm/fixtures/recover.json"
MAIN="${ROOT}/installer/aios_installer/main.py"
HI="${ROOT}/docs/envelope/hard-invariants.md"
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${QEMU}" ] || fail "missing ${QEMU}"
[ -x "${QEMU}" ] || fail "qemu.sh must be executable"
[ -f "${RUN}" ] || fail "missing ${RUN}"
[ -x "${RUN}" ] || fail "run.sh must be executable"
[ -f "${SMOKE}" ] || fail "missing ${SMOKE}"
[ -f "${RECOVER}" ] || fail "missing ${RECOVER}"
[ -f "${MAIN}" ] || fail "missing ${MAIN}"

sh -n "${QEMU}" || fail "sh -n qemu.sh"
sh -n "${RUN}" || fail "sh -n run.sh"
sh -n "${0}" || fail "sh -n p9-vm-harness.sh"

grep -q '/dev/kvm' "${QEMU}" \
  || fail "qemu.sh must fail closed without KVM (/dev/kvm)"
grep -q 'KVM missing' "${QEMU}" \
  || fail "qemu.sh must name KVM missing"
grep -q 'fail closed' "${QEMU}" \
  || fail "qemu.sh must document fail-closed KVM"
grep -q 'if=pflash' "${QEMU}" \
  || fail "qemu.sh must use OVMF pflash"
grep -q -- '-serial stdio' "${QEMU}" \
  || fail "qemu.sh must use serial stdio"
grep -q 'qemu-img snapshot' "${QEMU}" \
  || fail "qemu.sh must snapshot the qcow2"

qemu_arm() {
  awk -v lab="$1" '
    $0 == "  " lab ")" {p=1}
    p {print}
    p && $0 ~ /^[[:space:]]*;;$/ {exit}
  ' "${QEMU}"
}

_iso_arm=$(qemu_arm iso) || _iso_arm=
_disk_arm=$(qemu_arm disk) || _disk_arm=
[ -n "${_iso_arm}" ] || fail "qemu.sh missing iso stanza"
[ -n "${_disk_arm}" ] || fail "qemu.sh missing disk stanza"
printf '%s\n' "${_iso_arm}" | grep -q 'opt/org.aios/firstboot,string=auto' \
  || fail "iso exec must pass firstboot fw_cfg auto"
printf '%s\n' "${_iso_arm}" | grep -q 'opt/org.aios/console,string=serial' \
  || fail "iso exec must pass console fw_cfg serial"
printf '%s\n' "${_disk_arm}" | grep -q 'opt/org.aios/firstboot' \
  && fail "disk exec must omit firstboot fw_cfg" || true
printf '%s\n' "${_disk_arm}" | grep -q 'opt/org.aios/console' \
  && fail "disk exec must omit console fw_cfg" || true
printf '%s\n' "${_disk_arm}" | grep -q -- '-cdrom' \
  && fail "disk exec must omit -cdrom" || true

grep -q 'minisign before boot' "${RUN}" \
  || fail "run.sh must mention minisign before boot"
grep -q 'minisign -Vm' "${RUN}" \
  || fail "run.sh must minisign -Vm the ISO before qemu"
grep -q 'AIOS_ROOT' "${RUN}" \
  || fail "run.sh host drive must set AIOS_ROOT (HI-09)"
grep -q 'AIOS_BOOTSTRAP' "${RUN}" \
  || fail "run.sh host drive must set AIOS_BOOTSTRAP (HI-09)"
grep -q 'AIOS_VM_BOOT' "${RUN}" \
  || fail "run.sh must gate qemu boot on AIOS_VM_BOOT (HI-08)"
grep -q 'do not skip green' "${RUN}" \
  || fail "run.sh must fail closed without ISO"
grep -q 'Full ISO boot not claimed' "${RUN}" \
  || fail "run.sh must not claim a green ISO boot (HI-08)"
if grep -q 'qemu-system-x86_64' "${RUN}"; then
  fail "run.sh must use qemu.sh, not a second wrapper"
fi

# p9 green is not vm-smoke green (HI-08). Without an ISO, the named entrypoint
# must fail closed — not skip-green, not a host-only ok.
_iso_n=0
for _f in "${ROOT}/dist"/aios-*.iso; do
  [ -f "${_f}" ] || continue
  _iso_n=$((_iso_n + 1))
done
if [ "${_iso_n}" -eq 0 ]; then
  _smoke_run=$("${RUN}" smoke 2>&1) && _smoke_rc=0 || _smoke_rc=$?
  [ "${_smoke_rc}" -ne 0 ] \
    || fail "run.sh smoke must fail closed without ISO (do not skip green)"
  printf '%s\n' "${_smoke_run}" | grep -q 'fail closed (do not skip green)' \
    || fail "run.sh smoke missing fail-closed ISO error: ${_smoke_run}"
fi

if grep -R -q -- '-Syu' "${ROOT}/tests/vm" 2>/dev/null; then
  fail "vm harness contains -Syu (L-20)"
fi
if grep -R -E -q 'curl[ ]*\|[ ]*sh' "${ROOT}/tests/vm" 2>/dev/null; then
  fail "vm harness contains curl|sh (HI-04)"
fi

python3 - "${SMOKE}" "${RECOVER}" <<'PY' || fail "fixture schema"
import json
import sys

ALLOWED = (
    "view",
    "answer",
    "skip",
    "accept",
    "reject",
    "resume",
    "quit",
    "brake",
    "send",
)


def load(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit("%s is not an object" % path)
    return data


def check_answers(path, data):
    if data.get("work_runtime") is True:
        raise SystemExit("%s work_runtime must not be yes (HI-15)" % path)
    if data.get("work_runtime") is not False:
        raise SystemExit("%s work_runtime must be JSON false" % path)
    operator = data.get("operator")
    if not isinstance(operator, str) or not operator.strip():
        raise SystemExit("%s operator must be asked (L-13)" % path)
    if "bots" in data and data.get("bots") is not False:
        raise SystemExit("%s bots must be absent or false" % path)
    if data.get("bots") is True:
        raise SystemExit("%s bots must not be true" % path)
    vetoes = data.get("vetoes")
    if not isinstance(vetoes, dict):
        raise SystemExit("%s vetoes must be an object" % path)
    if vetoes.get("remotes") is True:
        raise SystemExit("%s remotes must not be yes" % path)


def check_commands(path, commands, require_skip=True, require_operator=False):
    if not isinstance(commands, list) or not commands:
        raise SystemExit("%s commands must be a non-empty list" % path)
    joined = "\n".join(commands)
    if "work-runtime yes" in joined:
        raise SystemExit("%s skip is not a yes (HI-15)" % path)
    if require_skip and "skip work-runtime" not in joined:
        raise SystemExit("%s must skip work-runtime (HI-15)" % path)
    if require_operator and "answer operator" not in joined:
        raise SystemExit("%s must answer operator (L-13)" % path)
    for item in commands:
        if not isinstance(item, str) or not item.strip():
            raise SystemExit("%s command must be a non-empty string" % path)
        cmd = item.split(None, 1)[0].lower()
        if cmd not in ALLOWED:
            raise SystemExit("%s unknown command %s" % (path, cmd))


smoke = load(sys.argv[1])
check_answers(sys.argv[1], smoke)
check_commands(
    sys.argv[1],
    smoke.get("commands"),
    require_skip=True,
    require_operator=True,
)
if "accept" not in "\n".join(smoke.get("commands") or []):
    raise SystemExit("%s must accept" % sys.argv[1])

recover = load(sys.argv[2])
check_answers(sys.argv[2], recover)
check_commands(sys.argv[2], recover.get("kill_after"), require_skip=True)
check_commands(
    sys.argv[2],
    recover.get("resume"),
    require_skip=False,
    require_operator=True,
)
PY

_probe=$("${QEMU}" probe 2>&1) && _probe_rc=0 || _probe_rc=$?
if [ "${_probe_rc}" -eq 0 ]; then
  printf '%s\n' "${_probe}" | grep -q -- '-serial stdio' \
    || fail "qemu.sh probe missing serial"
  printf '%s\n' "${_probe}" | grep -q -- 'if=pflash' \
    || fail "qemu.sh probe missing OVMF pflash"
  printf '%s\n' "${_probe}" | grep -q 'qemu-img snapshot' \
    || fail "qemu.sh probe missing snapshot"
else
  printf '%s\n' "${_probe}" | grep -Eq 'KVM missing|/dev/kvm|OVMF firmware missing' \
    || fail "qemu.sh probe must fail closed on KVM/OVMF: ${_probe}"
fi

json_list() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
val = data.get(key)
if not isinstance(val, list):
    raise SystemExit("%s must be a list" % key)
for item in val:
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

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
_live_existed=0
[ -e "${LIVE_BIP}" ] && _live_existed=1

_smoke_out=$(
  drive_json "${TMP}/smoke-boot" "${TMP}/smoke-root" "${SMOKE}" commands
) || true
if printf '%s\n' "${_smoke_out}" | grep -q Traceback; then
  fail "smoke fixture traceback: ${_smoke_out}"
fi
printf '%s\n' "${_smoke_out}" | grep -q 'skip: not-yes' \
  || fail "smoke skip work-runtime must be not-yes: ${_smoke_out}"
printf '%s\n' "${_smoke_out}" | grep -q 'work-runtime: true' \
  && fail "smoke must not set work-runtime true: ${_smoke_out}" || true
printf '%s\n' "${_smoke_out}" | grep -q 'work-runtime: false' \
  || fail "smoke work-runtime must stay false: ${_smoke_out}"
printf '%s\n' "${_smoke_out}" | grep -q 'operator: alice' \
  || fail "smoke must ask operator: ${_smoke_out}"
printf '%s\n' "${_smoke_out}" | grep -q 'envelope-decision: accepted' \
  || fail "smoke accept missing: ${_smoke_out}"
printf '%s\n' "${_smoke_out}" | grep -q '"bots"' \
  && fail "smoke TUI must not print a bots JSON key: ${_smoke_out}" || true

_kill_out=$(
  drive_json "${TMP}/recover-boot" "${TMP}/recover-root" "${RECOVER}" kill_after
) || true
if printf '%s\n' "${_kill_out}" | grep -q Traceback; then
  fail "recover kill traceback: ${_kill_out}"
fi
printf '%s\n' "${_kill_out}" | grep -q 'purpose: a lab vm' \
  || fail "recover kill missing purpose: ${_kill_out}"
printf '%s\n' "${_kill_out}" | grep -q 'work-runtime: false' \
  || fail "recover kill work-runtime must stay false: ${_kill_out}"
[ -f "${TMP}/recover-boot/answers.json" ] \
  || fail "recover missing answers.json after kill"

_resume_out=$(
  drive_json "${TMP}/recover-boot" "${TMP}/recover-root" "${RECOVER}" resume
) || true
if printf '%s\n' "${_resume_out}" | grep -q Traceback; then
  fail "recover resume traceback: ${_resume_out}"
fi
printf '%s\n' "${_resume_out}" | grep -q 'view: recovery' \
  || fail "recover resume missing recovery view: ${_resume_out}"
printf '%s\n' "${_resume_out}" | grep -q 'purpose: a lab vm' \
  || fail "recover resume lost purpose: ${_resume_out}"
printf '%s\n' "${_resume_out}" | grep -q 'work-runtime: true' \
  && fail "recover resume must not turn skip into yes: ${_resume_out}" || true
printf '%s\n' "${_resume_out}" | grep -q 'work-runtime: false' \
  || fail "recover resume work-runtime must stay false: ${_resume_out}"

if [ "${_live_existed}" -eq 0 ] && [ -e "${LIVE_BIP}" ]; then
  fail "oracle created ${LIVE_BIP} (HI-09)"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p9-vm-harness failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p9-vm-harness\n'
exit 0
