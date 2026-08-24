#!/bin/sh
# P6.3 host oracle: slice + schema + consumer ACK. HI-13 HI-16.
# Does not boot the ISO. Guest denials: tests/vm/oracles/vm-privilege-deny.sh.
# Isolation destroot is required; never write live /etc/systemd or /srv/aios.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
AIROOTFS="${ROOT}/payload/profile/airootfs"
SLICE="${AIROOTFS}/etc/systemd/system/aios-work.slice"
FLOOR="${AIROOTFS}/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
SOCKET="${AIROOTFS}/etc/systemd/system/aios-intent.socket"
AGENT_UNIT="${AIROOTFS}/etc/systemd/system/aios-agent.service"
FIRSTBOOT="${AIROOTFS}/usr/lib/aios/bin/firstboot"
INSTALLER="${AIROOTFS}/usr/lib/aios/bin/installer"
SCHEMA_JSON="${ROOT}/intent/schema.json"
SCHEMA_PY="${ROOT}/checker/aios_checker/schema.py"
MAIN="${ROOT}/agent/aios_agent/main.py"
CONSUME="${ROOT}/agent/aios_agent/intent_consume.py"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${AIROOTFS}/usr/lib/aios/checker/policy"
RUN="${ROOT}/tests/vm/run.sh"
VM_DENY="${ROOT}/tests/vm/oracles/vm-privilege-deny.sh"
QEMU="${ROOT}/tests/vm/qemu.sh"
failed=0
CONSUMER_PID=

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
# Only this oracle's writes count; sibling oracles may have left gitignored pyc.
_pyc_before=$(find "${ROOT}/agent" "${ROOT}/checker" "${ROOT}/intent" \
  "${ROOT}/tests" \( -name '__pycache__' -o -name '*.pyc' \) -print 2>/dev/null \
  | sort || true)

WR_BEFORE=0
if [ -e /srv/aios/src ]; then
  WR_BEFORE=1
fi
LIVE_SLICE_BEFORE=0
if [ -e /etc/systemd/system/aios-work.slice ]; then
  LIVE_SLICE_BEFORE=1
fi
LIVE_FLOOR_BEFORE=0
if [ -e /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf ]; then
  LIVE_FLOOR_BEFORE=1
fi
LIVE_ENVELOPE_BEFORE=0
if [ -e /srv/aios/envelope ]; then
  LIVE_ENVELOPE_BEFORE=1
fi
LIVE_RUN_BEFORE=0
if [ -e /run/aios ]; then
  LIVE_RUN_BEFORE=1
fi
PROD_BEFORE=0
if [ -S /run/aios/intent.sock ]; then
  PROD_BEFORE=1
fi
LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
LIVE_BIP_EXISTED=0
[ -e "${LIVE_BIP}" ] && LIVE_BIP_EXISTED=1

cleanup() {
  if [ -n "${CONSUMER_PID}" ]; then
    kill "${CONSUMER_PID}" 2>/dev/null || true
    wait "${CONSUMER_PID}" 2>/dev/null || true
    CONSUMER_PID=
  fi
  if [ -n "${TMP:-}" ]; then
    rm -rf "${TMP}"
  fi
}
trap cleanup EXIT

[ -f "${SLICE}" ] || fail "missing aios-work.slice"
[ -f "${FLOOR}" ] || fail "missing floor drop-in"
[ -f "${SOCKET}" ] || fail "missing aios-intent.socket"
[ -f "${AGENT_UNIT}" ] || fail "missing aios-agent.service"
[ -f "${SCHEMA_JSON}" ] || fail "missing intent/schema.json"
[ -f "${SCHEMA_PY}" ] || fail "missing schema.py"
[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${CONSUME}" ] || fail "missing ${CONSUME}"
[ -x "${POLICY}/work-slice.sh" ] || fail "missing work-slice.sh"
[ -x "${POLICY}/hi-16-os-privilege.sh" ] || fail "missing hi-16-os-privilege.sh"
[ -x "${RUN}" ] || fail "missing tests/vm/run.sh"
[ -x "${QEMU}" ] || fail "missing tests/vm/qemu.sh"
[ -f "${VM_DENY}" ] || fail "missing vm-privilege-deny.sh"
[ -x "${VM_DENY}" ] || fail "vm-privilege-deny.sh must be executable"
[ -f "${FIRSTBOOT}" ] || fail "missing firstboot"
[ -f "${INSTALLER}" ] || fail "missing installer"

# Payload units + schema + consumer wiring (HI-13, HI-16).
grep -qx 'MemoryMax=2G' "${SLICE}" || fail "aios-work.slice MemoryMax must be 2G"
grep -qx 'CPUQuota=200%' "${SLICE}" || fail "aios-work.slice CPUQuota must be 200%"
grep -qx 'NoNewPrivileges=yes' "${FLOOR}" \
  || fail "floor drop-in missing NoNewPrivileges=yes (HI-16)"
grep -qx 'ProtectSystem=strict' "${FLOOR}" \
  || fail "floor drop-in missing ProtectSystem=strict (HI-16)"
grep -qx 'CapabilityBoundingSet=' "${FLOOR}" \
  || fail "floor CapabilityBoundingSet must be empty (EPERM, HI-16)"
grep -q 'InaccessiblePaths=.*envelope' "${FLOOR}" \
  || fail "floor drop-in does not hide envelope (HI-13)"
grep -q 'InaccessiblePaths=.*enact' "${FLOOR}" \
  || fail "floor drop-in does not hide enact (HI-13)"
grep -q 'InaccessiblePaths=.*state' "${FLOOR}" \
  || fail "floor drop-in does not hide state/OS token (L-16)"
grep -qx 'ListenStream=/run/aios/intent.sock' "${SOCKET}" \
  || fail "socket ListenStream mismatch (L-05)"
grep -qx 'SocketGroup=aios-work' "${SOCKET}" \
  || fail "socket SocketGroup must be aios-work"
grep -qx 'Sockets=aios-intent.socket' "${AGENT_UNIT}" \
  || fail "aios-agent.service missing Sockets=aios-intent.socket"
grep -q 'Not a shell (HI-13)' "${SCHEMA_JSON}" \
  || fail "intent/schema.json must say intent is not a shell (HI-13)"
grep -q 'work-runtime-bots' "${SCHEMA_JSON}" \
  || fail "schema source enum missing work-runtime-bots"
grep -q 'HI-13' "${CONSUME}" || fail "intent_consume.py must quote HI-13"
grep -q 'PROD_SOCK = "/run/aios/intent.sock"' "${CONSUME}" \
  || fail "intent_consume.py must lock the prod socket path"
grep -q 'Never bind the prod path' "${CONSUME}" \
  || fail "listen_socket must refuse to bind the prod path"
grep -q 'HI-13' "${POLICY}/work-slice.sh" \
  || fail "work-slice.sh must quote HI-13"
grep -q 'HI-16' "${POLICY}/hi-16-os-privilege.sh" \
  || fail "hi-16-os-privilege.sh must quote HI-16"

if [ -e "${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime.service" ] \
  || [ -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime.service" ]; then
  fail "aios-work-runtime.service must not be added (L-23)"
fi
if grep -q 'enable aios-work' "${FIRSTBOOT}"; then
  fail "firstboot must not enable work units"
fi
if grep -E 'systemctl.*[[:space:]](enable|start)[[:space:]].*aios-work' \
  "${VM_DENY}" >/dev/null; then
  fail "vm-privilege-deny.sh must not enable/start work units"
fi

# Harness A: installer/firstboot must not gain a sysupgrade.
if grep -q -- '-Syu' "${FIRSTBOOT}" "${INSTALLER}" 2>/dev/null; then
  fail "firstboot/installer contains -Syu (L-20)"
fi
if grep -R -q -- '-Syu' "${AIROOTFS}/usr/lib/aios/installer" 2>/dev/null; then
  fail "installer TUI contains -Syu (L-20)"
fi
if grep -q -- '-Syu' "${SLICE}" "${FLOOR}" "${SOCKET}"; then
  fail "P6 units contain -Syu (L-20)"
fi

sh -n "${0}" || fail "sh -n p6-privilege-deny.sh"
sh -n "${VM_DENY}" || fail "sh -n vm-privilege-deny.sh"
sh -n "${RUN}" || fail "sh -n run.sh"
sh -n "${POLICY}/work-slice.sh" || fail "sh -n work-slice.sh"
sh -n "${POLICY}/hi-16-os-privilege.sh" || fail "sh -n hi-16-os-privilege.sh"

grep -q 'privilege-deny' "${RUN}" \
  || fail "run.sh missing privilege-deny target"
grep -q 'AIOS_VM_BOOT' "${RUN}" \
  || fail "run.sh must gate qemu boot on AIOS_VM_BOOT (HI-08)"
grep -q 'do not skip green' "${RUN}" \
  || fail "run.sh must fail closed without ISO"
if grep -q 'qemu-system-x86_64' "${RUN}" "${VM_DENY}"; then
  fail "run.sh/vm-privilege-deny.sh must use qemu.sh, not a second wrapper"
fi
grep -q 'sudo -u aios-work test -w /srv/aios/envelope' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh missing envelope write denial (HI-13)"
grep -q 'sudo -u aios-work test -x /usr/lib/aios/bin/enact' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh missing enact exec denial (HI-16)"
grep -q 'EPERM' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh must expect EPERM/capabilities (HI-16)"
grep -q 'the model declined' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh must reject a model-decline story (HI-13)"
grep -q 'HI-13' "${VM_DENY}" || fail "vm-privilege-deny.sh must quote HI-13"
grep -q 'HI-16' "${VM_DENY}" || fail "vm-privilege-deny.sh must quote HI-16"
grep -q 'AIOS_VM_GUEST' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh must gate live sudo on AIOS_VM_GUEST"
grep -q 'AIOS_VM_BOOT' "${VM_DENY}" \
  || fail "vm-privilege-deny.sh must mention AIOS_VM_BOOT (HI-08)"
if grep -q -- '-Syu' "${VM_DENY}"; then
  fail "vm-privilege-deny.sh contains -Syu (L-20)"
fi

TMP=$(mktemp -d)
mkdir -p "${TMP}/root/etc/systemd/system" \
  "${TMP}/root/usr/lib/systemd/system/aios-work-.service.d"
cp -a "${SLICE}" "${TMP}/root/etc/systemd/system/aios-work.slice"
cp -a "${FLOOR}" "${TMP}/root/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"

# Isolation is required; never probe the workstation's live /etc/systemd.
if ! AIOS_POLICY_ROOT="${TMP}/root" "${POLICY}/work-slice.sh"; then
  fail "work-slice.sh failed against payload copies"
fi
if ! AIOS_POLICY_ROOT="${TMP}/root" "${POLICY}/hi-16-os-privilege.sh"; then
  fail "hi-16-os-privilege.sh failed against payload copies"
fi
if ! AIOS_POLICY_ROOT="${TMP}/root" "${ISO_POLICY}/hi-16-os-privilege.sh"; then
  fail "ISO hi-16-os-privilege.sh failed against payload copies"
fi

mkdir -p "${TMP}/empty"
if AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/work-slice.sh" >/dev/null 2>&1; then
  fail "work-slice.sh passed with empty AIOS_POLICY_ROOT destroot"
fi
if AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/hi-16-os-privilege.sh" >/dev/null 2>&1; then
  fail "hi-16-os-privilege.sh passed with empty AIOS_POLICY_ROOT destroot"
fi

python3 - "${SCHEMA_JSON}" "${SCHEMA_PY}" "${CONSUME}" <<'PY' || fail "schema rejects shell / ACK valid work-intent"
import json
import sys

schema_path, schema_dir, consume_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, schema_dir.rsplit("/", 1)[0])
sys.path.insert(0, consume_path.rsplit("/", 1)[0])
from schema import WorkIntentSchemaError, validate_work_intent
from intent_consume import consume_bytes

schema = json.load(open(schema_path, encoding="utf-8"))
enum = (schema.get("properties") or {}).get("source", {}).get("enum") or []
if set(enum) != {"work-runtime", "work-runtime-bots"}:
    raise SystemExit("schema source enum mismatch")


def check_json_schema(instance):
    if schema.get("type") == "object" and not isinstance(instance, dict):
        raise ValueError("not an object")
    extra = set(instance) - set(schema.get("properties") or {})
    if extra and schema.get("additionalProperties") is False:
        raise ValueError("extra keys")
    for key in schema.get("required") or []:
        if key not in instance:
            raise ValueError("missing " + key)
    source = (schema.get("properties") or {}).get("source") or {}
    if "source" in instance and instance["source"] not in (source.get("enum") or []):
        raise ValueError("bad source")


def must_reject_schema(instance, label):
    try:
        check_json_schema(instance)
    except ValueError:
        return
    raise SystemExit("schema.json accepted %s" % label)


def must_reject_py(obj, label):
    try:
        validate_work_intent(obj)
    except WorkIntentSchemaError:
        return
    raise SystemExit("schema.py accepted %s" % label)


must_reject_schema("pacman -S neovim", "shell string")
must_reject_py("pacman -S neovim", "shell string")
must_reject_schema(
    {
        "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
        "source": "bash -c pacman -S neovim",
        "asked": "x",
    },
    "shell string as source",
)
must_reject_py(
    {
        "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
        "source": "bash -c pacman -S neovim",
        "asked": "x",
    },
    "shell string as source",
)
must_reject_schema(
    {
        "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
        "source": "human",
        "asked": "x",
    },
    "human source",
)

good = {
    "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
    "source": "work-runtime",
    "asked": "install neovim as the system editor",
    "clause": None,
    "suggested_oracles": ["pacman -Qi neovim"],
    "paths": ["/srv/aios/src/work-runtime"],
}
validate_work_intent(good)
bots = dict(good)
bots["source"] = "work-runtime-bots"
validate_work_intent(bots)

ack = consume_bytes(json.dumps(good).encode("utf-8"))
if not ack or ack.get("accepted") is not True or ack.get("id") != good["id"]:
    raise SystemExit("consume valid: %s" % ack)
if ack.get("surface") != "definition":
    raise SystemExit("valid ACK missing surface")
bad = consume_bytes(b"pacman -S neovim")
if not bad or bad.get("accepted") is not False:
    raise SystemExit("shell string ACK: %s" % bad)
PY

SOCK="${TMP}/intent.sock"
env -u LISTEN_FDS -u LISTEN_PID AIOS_INTENT_SOCK="${SOCK}" \
  python3 "${MAIN}" &
CONSUMER_PID=$!
_i=0
while [ "${_i}" -lt 50 ]; do
  if [ -S "${SOCK}" ]; then
    break
  fi
  if ! kill -0 "${CONSUMER_PID}" 2>/dev/null; then
    fail "consumer exited before bind"
    break
  fi
  sleep 0.1
  _i=$((_i + 1))
done
[ -S "${SOCK}" ] || fail "consumer did not bind AIOS_INTENT_SOCK"

# Lock the real entrypoint this oracle claims to test.
if [ -n "${CONSUMER_PID}" ] && [ -r "/proc/${CONSUMER_PID}/cmdline" ]; then
  _cmd=$(tr '\0' ' ' < "/proc/${CONSUMER_PID}/cmdline")
  printf '%s\n' "${_cmd}" | grep -F "${MAIN}" >/dev/null \
    || fail "consumer cmdline is not ${MAIN}: ${_cmd}"
fi

if [ "${PROD_BEFORE}" = 0 ] && [ -S /run/aios/intent.sock ]; then
  fail "oracle bound /run/aios/intent.sock"
fi
if [ "${PROD_BEFORE}" = 0 ] && grep -F ' /run/aios/intent.sock' /proc/net/unix >/dev/null 2>&1; then
  fail "LISTEN on /run/aios/intent.sock"
fi

exchange_file() {
  python3 -c '
import socket
import sys

path = sys.argv[1]
payload = open(sys.argv[2], "rb").read()
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(3)
sock.connect(path)
if payload:
    sock.sendall(payload)
sock.shutdown(socket.SHUT_WR)
data = b""
while True:
    try:
        chunk = sock.recv(4096)
    except socket.timeout:
        break
    if not chunk:
        break
    data += chunk
sock.close()
sys.stdout.buffer.write(data)
' "${SOCK}" "$1"
}

printf '%s' '{"id":"6ba7b810-9dad-41d1-80b4-00c04fd430c8","source":"work-runtime","asked":"install neovim as the system editor","clause":null,"suggested_oracles":["pacman -Qi neovim"],"paths":["/srv/aios/src/work-runtime"]}' > "${TMP}/valid.json"
_ack=$(exchange_file "${TMP}/valid.json" || true)
printf '%s\n' "${_ack}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("accepted") is True; assert d.get("id")=="6ba7b810-9dad-41d1-80b4-00c04fd430c8"; assert d.get("surface")=="definition"' \
  || fail "valid object ACK: ${_ack}"
kill -0 "${CONSUMER_PID}" 2>/dev/null || fail "consumer died after valid ACK"

printf '%s' 'pacman -S neovim; source /etc/profile' > "${TMP}/shell.txt"
_bad=$(exchange_file "${TMP}/shell.txt" || true)
printf '%s\n' "${_bad}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("accepted") is False' \
  || fail "malformed ACK: ${_bad}"
kill -0 "${CONSUMER_PID}" 2>/dev/null || fail "consumer traceback-exited on malformed input"

if [ "${PROD_BEFORE}" = 0 ] && [ -S /run/aios/intent.sock ]; then
  fail "oracle bound /run/aios/intent.sock after traffic"
fi
if [ "${PROD_BEFORE}" = 0 ] && grep -F ' /run/aios/intent.sock' /proc/net/unix >/dev/null 2>&1; then
  fail "LISTEN on /run/aios/intent.sock after traffic"
fi

# VM boot path must fail closed without ISO (do not skip green).
_iso_n=0
for _f in "${ROOT}/dist"/aios-*.iso; do
  [ -f "${_f}" ] || continue
  _iso_n=$((_iso_n + 1))
done
if [ "${_iso_n}" -eq 0 ]; then
  _pd_run=$("${RUN}" privilege-deny 2>&1) && _pd_rc=0 || _pd_rc=$?
  [ "${_pd_rc}" -ne 0 ] \
    || fail "run.sh privilege-deny must fail closed without ISO (do not skip green)"
  printf '%s\n' "${_pd_run}" | grep -q 'fail closed (do not skip green)' \
    || fail "run.sh privilege-deny missing fail-closed ISO error: ${_pd_run}"
  _or_run=$("${VM_DENY}" 2>&1) && _or_rc=0 || _or_rc=$?
  [ "${_or_rc}" -ne 0 ] \
    || fail "vm-privilege-deny.sh must fail closed without ISO (do not skip green)"
  printf '%s\n' "${_or_run}" | grep -q 'fail closed (do not skip green)' \
    || fail "vm-privilege-deny.sh missing fail-closed ISO error: ${_or_run}"
fi

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15)"
fi
if [ "${LIVE_SLICE_BEFORE}" -eq 0 ] && [ -e /etc/systemd/system/aios-work.slice ]; then
  fail "oracle wrote live aios-work.slice"
fi
if [ "${LIVE_FLOOR_BEFORE}" -eq 0 ] \
  && [ -e /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf ]; then
  fail "oracle wrote live floor drop-in"
fi
if [ "${LIVE_ENVELOPE_BEFORE}" -eq 0 ] && [ -e /srv/aios/envelope ]; then
  fail "oracle wrote live /srv/aios/envelope"
fi
if [ "${LIVE_RUN_BEFORE}" -eq 0 ] && [ -e /run/aios ]; then
  fail "oracle created /run/aios"
fi
if [ "${LIVE_BIP_EXISTED}" -eq 0 ] && [ -e "${LIVE_BIP}" ]; then
  fail "oracle created ${LIVE_BIP} (HI-09)"
fi

_pyc_after=$(find "${ROOT}/agent" "${ROOT}/checker" "${ROOT}/intent" \
  "${ROOT}/tests" \( -name '__pycache__' -o -name '*.pyc' \) -print 2>/dev/null \
  | sort || true)
if [ "${_pyc_after}" != "${_pyc_before}" ]; then
  fail "oracle wrote bytecode into the worktree"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p6-privilege-deny failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p6-privilege-deny\n'
exit 0
