#!/bin/sh
# P6.1: intent.sock schema + agent consumer. Not a shell (HI-13, L-05).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/agent/aios_agent/main.py"
CONSUME="${ROOT}/agent/aios_agent/intent_consume.py"
SCHEMA_PY="${ROOT}/checker/aios_checker/schema.py"
SCHEMA_JSON="${ROOT}/intent/schema.json"
UNIT="${ROOT}/payload/profile/airootfs/etc/systemd/system/aios-intent.socket"
AGENT_UNIT="${ROOT}/payload/profile/airootfs/etc/systemd/system/aios-agent.service"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
ISO_INTENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/intent"
ISO_CHECKER="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
AIROOTFS="${ROOT}/payload/profile/airootfs"
failed=0
CONSUMER_PID=

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

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

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${CONSUME}" ] || fail "missing ${CONSUME}"
[ -f "${SCHEMA_PY}" ] || fail "missing ${SCHEMA_PY}"
[ -f "${SCHEMA_JSON}" ] || fail "missing ${SCHEMA_JSON}"
[ -f "${UNIT}" ] || fail "missing aios-intent.socket"
[ -f "${AGENT_UNIT}" ] || fail "missing aios-agent.service"
[ -f "${ISO_INTENT}/schema.json" ] || fail "missing ISO intent schema.json"
[ -f "${ISO_AGENT}/aios_agent/intent_consume.py" ] || fail "missing ISO intent_consume.py"

grep -q 'HI-13' "${CONSUME}" || fail "intent_consume.py must quote HI-13"
grep -q 'L-05' "${SCHEMA_PY}" || fail "schema.py must note L-05 work-intent"
grep -q 'validate_work_intent' "${SCHEMA_PY}" || fail "schema.py missing validate_work_intent"
grep -q 'WORK_INTENT_SOURCES' "${SCHEMA_PY}" || fail "schema.py missing WORK_INTENT_SOURCES"
grep -q 'work-runtime-bots' "${SCHEMA_PY}" || fail "schema.py missing work-runtime-bots"
# Proposal sources stay a different document.
grep -q 'INTENT_SOURCES = ("human", "envelope-clause", "machine-goal", "work-intent")' \
  "${SCHEMA_PY}" || fail "proposal INTENT_SOURCES must keep work-intent"
grep -q 'time.sleep(POLL_S)' "${MAIN}" \
  || fail "no-arg serve() must still idle (L-21)"
grep -q 'Sockets=aios-intent.socket' "${AGENT_UNIT}" \
  || fail "aios-agent.service missing Sockets=aios-intent.socket"
grep -qx 'ListenStream=/run/aios/intent.sock' "${UNIT}" \
  || fail "socket ListenStream mismatch (L-05)"
grep -qx 'SocketUser=aios-agent' "${UNIT}" || fail "socket SocketUser mismatch"
grep -qx 'SocketGroup=aios-work' "${UNIT}" || fail "socket SocketGroup mismatch"
grep -qx 'SocketMode=0660' "${UNIT}" || fail "socket SocketMode mismatch"
grep -qx 'Accept=no' "${UNIT}" || fail "socket Accept mismatch"
grep -qx 'WantedBy=sockets.target' "${UNIT}" || fail "socket WantedBy mismatch"

if [ -e "${AIROOTFS}/etc/systemd/system/sockets.target.wants/aios-intent.socket" ]; then
  fail "aios-intent.socket must not be enabled on the live ISO"
fi
grep -q 'aios-intent.socket' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-intent.socket"
grep -q 'enable aios-intent.socket' "${FIRSTBOOT}" \
  || fail "firstboot must enable aios-intent.socket on the installed disk"
grep -q 'enable aios-agent.service' "${FIRSTBOOT}" \
  && fail "firstboot must not enable aios-agent.service (L-20)" || true
grep -q 'aios-intent.socket missing on target' "${FIRSTBOOT}" \
  || fail "firstboot must fail closed if the socket unit is missing"

if grep -E 'subprocess|os\.system|eval\(|exec\(|Popen' "${CONSUME}" >/dev/null; then
  fail "intent_consume.py must not execute asked (HI-13)"
fi
if grep -R -q -- '-Syu' "${ROOT}/intent" "${CONSUME}" "${UNIT}"; then
  fail "intent transport added -Syu (L-20)"
fi
if grep -q -- '-Syu' "${FIRSTBOOT}"; then
  fail "firstboot contains -Syu (L-20)"
fi

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

python3 -m py_compile \
  "${CONSUME}" \
  "${MAIN}" \
  "${SCHEMA_PY}" \
  || fail "py_compile failed"

_pyct=$(mktemp -d)
cp -a "${ISO_AGENT}/aios_agent/intent_consume.py" "${_pyct}/"
cp -a "${ISO_AGENT}/aios_agent/main.py" "${_pyct}/"
cp -a "${ISO_CHECKER}/aios_checker/schema.py" "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/intent_consume.py" \
  "${_pyct}/main.py" \
  "${_pyct}/schema.py" \
  || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${0}" || fail "sh -n p6-intent-sock.sh"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"

cmp -s "${SCHEMA_JSON}" "${ISO_INTENT}/schema.json" \
  || fail "ISO intent/schema.json bytes differ"
cmp -s "${ROOT}/intent/README.md" "${ISO_INTENT}/README.md" \
  || fail "ISO intent/README.md bytes differ"
while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  cmp -s "${ROOT}/agent/${rel}" "${ISO_AGENT}/${rel}" \
    || fail "ISO agent ${rel} bytes differ"
done <<EOF
$(cd "${ROOT}/agent" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF
cmp -s "${SCHEMA_PY}" "${ISO_CHECKER}/aios_checker/schema.py" \
  || fail "ISO checker schema.py bytes differ"

python3 - "${SCHEMA_JSON}" <<'PY' || fail "schema.json must reject shell / missing id / bad source"
import json
import sys

schema = json.load(open(sys.argv[1], encoding="utf-8"))
if schema.get("type") != "object":
    raise SystemExit("schema type must be object")
if schema.get("additionalProperties") is not False:
    raise SystemExit("schema must set additionalProperties false")
required = set(schema.get("required") or [])
if "id" not in required or "source" not in required or "asked" not in required:
    raise SystemExit("schema required must include id, source, asked")
enum = (schema.get("properties") or {}).get("source", {}).get("enum") or []
if set(enum) != {"work-runtime", "work-runtime-bots"}:
    raise SystemExit("schema source enum mismatch")


def check(instance):
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


try:
    check("pacman -S neovim")
except ValueError:
    pass
else:
    raise SystemExit("shell string must fail schema")
try:
    check({"source": "work-runtime", "asked": "x"})
except ValueError:
    pass
else:
    raise SystemExit("missing id must fail schema")
try:
    check({"id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8", "source": "human", "asked": "x"})
except ValueError:
    pass
else:
    raise SystemExit("bad source must fail schema")
PY

python3 - "${ROOT}/checker/aios_checker" "${ROOT}/agent/aios_agent" <<'PY' || fail "schema.py / consume reject fixtures"
import json
import sys

sys.path.insert(0, sys.argv[1])
from schema import WorkIntentSchemaError, validate_proposal, validate_work_intent

sys.path.insert(0, sys.argv[2])
from intent_consume import consume_bytes

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

def must_fail(obj, label):
    try:
        validate_work_intent(obj)
    except WorkIntentSchemaError:
        return
    raise SystemExit("schema.py accepted %s" % label)

must_fail("pacman -S neovim", "shell string")
must_fail({"source": "work-runtime", "asked": "x"}, "missing id")
must_fail(
    {
        "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
        "source": "human",
        "asked": "x",
    },
    "bad source",
)
must_fail(
    {
        "id": "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
        "source": "work-runtime",
        "asked": "x",
        "shell": "true",
    },
    "extra keys",
)

# Proposal validator must not accept a work-intent record as a proposal.
try:
    validate_proposal(good)
except Exception:
    pass
else:
    raise SystemExit("proposal schema accepted a work-intent record")

ack = consume_bytes(json.dumps(good).encode("utf-8"))
if not ack or ack.get("accepted") is not True or ack.get("id") != good["id"]:
    raise SystemExit("consume valid: %s" % ack)
if ack.get("surface") != "definition":
    raise SystemExit("valid ACK missing surface")

bad = consume_bytes(b"pacman -S neovim")
if not bad or bad.get("accepted") is not False:
    raise SystemExit("shell string ACK: %s" % bad)
bad = consume_bytes(b"\xff\xfe")
if not bad or bad.get("accepted") is not False:
    raise SystemExit("malformed UTF-8 ACK: %s" % bad)
if consume_bytes(b"") is not None:
    raise SystemExit("empty payload must be hangup")
if consume_bytes(b"   \n") is not None:
    raise SystemExit("whitespace payload must be hangup")
PY

TMP=$(mktemp -d)
SOCK="${TMP}/intent.sock"
PROD_BEFORE=0
if [ -S /run/aios/intent.sock ]; then
  PROD_BEFORE=1
fi

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

printf '\xff\xfe' > "${TMP}/badutf"
_utf=$(exchange_file "${TMP}/badutf" || true)
printf '%s\n' "${_utf}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("accepted") is False' \
  || fail "bad UTF-8 ACK: ${_utf}"
kill -0 "${CONSUMER_PID}" 2>/dev/null || fail "consumer traceback-exited on bad UTF-8"

python3 -c '
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(3)
sock.connect(sys.argv[1])
sock.shutdown(socket.SHUT_WR)
sock.close()
' "${SOCK}" || fail "empty hangup"
kill -0 "${CONSUMER_PID}" 2>/dev/null || fail "consumer exited on empty hangup"

if [ "${PROD_BEFORE}" = 0 ] && [ -S /run/aios/intent.sock ]; then
  fail "oracle bound /run/aios/intent.sock after traffic"
fi
if [ "${PROD_BEFORE}" = 0 ] && grep -F ' /run/aios/intent.sock' /proc/net/unix >/dev/null 2>&1; then
  fail "LISTEN on /run/aios/intent.sock after traffic"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

while IFS= read -r line || [ -n "${line}" ]; do
  [ -n "${line}" ] || continue
  case "${line}" in
    \#*) continue ;;
  esac
  hash=${line%% *}
  path=${line#* }
  path=${path# }
  case "${path}" in
    /*) f="${AIROOTFS}${path}" ;;
    *) f="${AIROOTFS}/usr/lib/aios/${path}" ;;
  esac
  [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
  printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
    || fail "ISO hash mismatch: ${path}"
done < "${ISO_HASHES}"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p6-intent-sock failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p6-intent-sock\n'
exit 0
