#!/bin/sh
# P8.6: MCP preferred; token-in-chat fails; OS key unreadable.
# Host-only. Isolation destroot is required; never write live /srv/aios/src.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
SEED="${ROOT}/seed/work-runtime"
ISO_SEED="${ROOT}/payload/profile/airootfs/srv/aios/seeds/work-runtime"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

WR_BEFORE=0
if [ -e /srv/aios/src ]; then
  WR_BEFORE=1
fi
LIVE_SYS_BEFORE=0
if [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  LIVE_SYS_BEFORE=1
fi

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -f "${SEED}/connectors.py" ] || fail "missing seed/work-runtime/connectors.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/connectors.py" ] || fail "missing ISO seed connectors.py"
cmp -s "${SEED}/connectors.py" "${ISO_SEED}/connectors.py" \
  || fail "ISO connectors.py != seed connectors.py"
cmp -s "${SEED}/main.py" "${ISO_SEED}/main.py" \
  || fail "ISO main.py != seed main.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'If a Connector exists for a service, use it' "${SEED}/connectors.py" \
  || fail "connectors.py missing MCP-preferred refusal"
grep -q 'newly installed connectors are available on the next message' \
  "${SEED}/connectors.py" \
  || fail "connectors.py missing next-message install rule"
grep -q 'token in chat fails' "${SEED}/connectors.py" \
  || fail "connectors.py missing token-in-chat refusal"
grep -q 'do not paste authorization links into chat' "${SEED}/connectors.py" \
  || fail "connectors.py missing auth-link refusal"
if grep -n 'AIOS_SKILLS' "${SEED}/connectors.py" >/dev/null; then
  fail "connectors must not honour AIOS_SKILLS"
fi
if grep -nE '^(import|from)[[:space:]]+aios_agent\b' "${SEED}/connectors.py" \
  >/dev/null; then
  fail "connectors.py must not import aios_agent"
fi

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}"
cp -a "${SEED}/main.py" "${SEED}/skills.py" "${SEED}/wake.py" \
  "${SEED}/provider.py" "${SEED}/live.py" "${SEED}/connectors.py" \
  "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/main.py" "${_pyct}/skills.py" "${_pyct}/wake.py" \
  "${_pyct}/provider.py" "${_pyct}/live.py" "${_pyct}/connectors.py" \
  || fail "py_compile seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-connector.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope" "${SRC}/connectors"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
cat > "${SRC}/connectors/example.json" <<'EOF'
{
  "name": "example",
  "service": "example.com",
  "status": "connected",
  "tools": [{"name": "echo", "description": "Echo a probe", "inputSchema": {"type": "object"}}],
  "calls": {"echo": "mcp-echo-ok"},
  "connect": {
    "verification_uri": "https://example.com/device",
    "user_code": "WDJB-MJHT"
  }
}
EOF
cat > "${SRC}/connectors/locked.json" <<'EOF'
{
  "name": "locked",
  "service": "locked.example",
  "status": "disconnected",
  "tools": [{"name": "ping", "description": "Ping"}],
  "connect": {
    "verification_uri": "https://locked.example/device",
    "user_code": "LOCK-CODE"
  }
}
EOF

printf '%s\n' '{"responses":[{"connector_discover":"example"},{"actions":[{"tool":"connector_call","connector":"example","call":"echo"},{"tool":"send","text":"used-mcp"}]}]}' \
  > "${TMP}/mcp.json"
printf '%s\n' '{"responses":[{"tool":"browser","service":"example.com","url":"https://example.com/search"}]}' \
  > "${TMP}/browser-hit.json"
printf '%s\n' '{"responses":[{"tool":"browser","service":"none.example","url":"https://none.example/x"},{"tool":"send","text":"used-browser"}]}' \
  > "${TMP}/browser-miss.json"
printf '%s\n' '{"responses":[{"connector_call":"example echo"}]}' \
  > "${TMP}/call-first.json"
printf '%s\n' '{"responses":[{"send":"ok"}]}' \
  > "${TMP}/send.json"
printf '%s\n' '{"responses":[{"connector_connect":"locked"}]}' \
  > "${TMP}/connect.json"
printf '%s\n' '{"responses":[{"actions":[{"tool":"connector_connect","name":"locked"},{"tool":"send","text":"https://auth.x.ai/device"}]}]}' \
  > "${TMP}/connect-paste.json"
printf '%s\n' '{"responses":[{"connector_install":{"name":"fresh","service":"fresh.example","status":"connected","tools":[{"name":"ping"}],"calls":{"ping":"fresh-ok"}},"connector_discover":"fresh"}]}' \
  > "${TMP}/install-same.json"
printf '%s\n' '{"responses":[{"connector_install":{"name":"fresh","service":"fresh.example","status":"connected","tools":[{"name":"ping"}],"calls":{"ping":"fresh-ok"}},"send":"installed"}]}' \
  > "${TMP}/install.json"
printf '%s\n' '{"responses":[{"connector_discover":"fresh"},{"actions":[{"tool":"connector_call","connector":"fresh","call":"ping"},{"tool":"send","text":"fresh-used"}]}]}' \
  > "${TMP}/fresh-next.json"

run_turn() {
  _fix=$1
  shift
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${_fix}" \
    python3 "${SRC}/main.py" turn "$@"
}

_mcp=$(run_turn "${TMP}/mcp.json" "use example") || true
printf '%s\n' "${_mcp}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if "example" not in (d.get("connectors_discovered") or []):
    raise SystemExit("discovered %s" % d.get("connectors_discovered"))
results = d.get("connector_results") or []
if not results or results[0].get("result") != "mcp-echo-ok":
    raise SystemExit("results %s" % results)
if d.get("delivered") != "used-mcp":
    raise SystemExit("delivered %s" % d.get("delivered"))
ctx = d.get("context") or ""
if "connector schema example:" not in ctx:
    raise SystemExit("discover schema missing from context")
if "mcp-echo-ok" not in ctx:
    raise SystemExit("call result missing from context")
' || fail "MCP discover-then-call failed: ${_mcp}"

_hit=$(run_turn "${TMP}/browser-hit.json" "browse example") || true
printf '%s\n' "${_hit}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "If a Connector exists for a service, use it" not in err:
    raise SystemExit("error %s" % err)
if d.get("delivered"):
    raise SystemExit("browser delivered around a connector")
' || fail "browser around a connector must fail: ${_hit}"

_miss=$(run_turn "${TMP}/browser-miss.json" "browse none") || true
printf '%s\n' "${_miss}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if "browser-fallback:" not in (d.get("context") or ""):
    raise SystemExit("browser fallback missing from context")
if d.get("delivered") != "used-browser":
    raise SystemExit("delivered %s" % d.get("delivered"))
' || fail "browser fallback without a connector failed: ${_miss}"

_first=$(run_turn "${TMP}/call-first.json" "call without discover") || true
printf '%s\n' "${_first}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
if "discover schema, then call" not in (d.get("error") or ""):
    raise SystemExit("error %s" % d.get("error"))
' || fail "call without discover must fail: ${_first}"

_tok=$(run_turn "${TMP}/send.json" "please store access_token=pasted-secret-value") || true
printf '%s\n' "${_tok}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
if "token in chat" not in (d.get("error") or ""):
    raise SystemExit("error %s" % d.get("error"))
if d.get("delivered"):
    raise SystemExit("delivered on token-in-chat")
' || fail "token-in-chat must fail: ${_tok}"

_auth=$(run_turn "${TMP}/send.json" "open https://auth.x.ai/device") || true
printf '%s\n' "${_auth}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
if "authorization links" not in (d.get("error") or ""):
    raise SystemExit("error %s" % d.get("error"))
' || fail "auth link in chat must fail: ${_auth}"

_card=$(run_turn "${TMP}/connect.json" "connect locked") || true
printf '%s\n' "${_card}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
card = d.get("connect_card") or {}
if card.get("kind") != "connect_card":
    raise SystemExit("card %s" % card)
if card.get("connector") != "locked":
    raise SystemExit("connector %s" % card.get("connector"))
if card.get("verification_uri") != "https://locked.example/device":
    raise SystemExit("uri %s" % card.get("verification_uri"))
if card.get("user_code") != "LOCK-CODE":
    raise SystemExit("user_code %s" % card.get("user_code"))
if d.get("delivered"):
    raise SystemExit("connect card leaked into chat send")
shown = json.dumps(d)
if "access_token" in shown.lower():
    raise SystemExit("token in transcript")
' || fail "connect card failed: ${_card}"

_paste=$(run_turn "${TMP}/connect-paste.json" "connect and paste") || true
printf '%s\n' "${_paste}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
if "authorization links" not in (d.get("error") or ""):
    raise SystemExit("error %s" % d.get("error"))
if d.get("delivered"):
    raise SystemExit("auth link was delivered")
' || fail "paste of authorization link must fail: ${_paste}"

_same=$(run_turn "${TMP}/install-same.json" "install and discover") || true
printf '%s\n' "${_same}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
if "next message" not in (d.get("error") or ""):
    raise SystemExit("error %s" % d.get("error"))
' || fail "newly installed connector same message must fail: ${_same}"

_ins=$(run_turn "${TMP}/install.json" "install fresh") || true
printf '%s\n' "${_ins}" | grep -q '"outcome": "sent"' \
  || fail "install without discover must send: ${_ins}"
_next=$(run_turn "${TMP}/fresh-next.json" "use fresh next") || true
printf '%s\n' "${_next}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if "fresh" not in (d.get("connectors_discovered") or []):
    raise SystemExit("discovered %s" % d.get("connectors_discovered"))
if d.get("delivered") != "fresh-used":
    raise SystemExit("delivered %s" % d.get("delivered"))
' || fail "newly installed connector next message failed: ${_next}"

_os=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_CONNECTORS="/srv/aios/state/provider/os.token" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${TMP}/mcp.json" \
    python3 "${SRC}/main.py" turn "os key" 2>/dev/null || true
)
printf '%s\n' "${_os}" | grep -q 'L-16' \
  || fail "OS token path as connectors dir must be unreadable: ${_os}"

env -u AIOS_WORK_SRC env -u AIOS_ROOT \
  python3 "${SRC}/main.py" turn connector >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC connector turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/connectors.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed connectors.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/connectors.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed connectors.py"
grep -Fq '/srv/aios/seeds/work-runtime/connectors.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed connectors.py"

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
    /*) f="${ROOT}/payload/profile/airootfs${path}" ;;
    *) f="${ROOT}/payload/profile/airootfs/usr/lib/aios/${path}" ;;
  esac
  [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
  printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
    || fail "ISO hash mismatch: ${path}"
done < "${ISO_HASHES}"

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15)"
fi
if [ "${LIVE_SYS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  fail "oracle wrote live system aios-work-runtime.service"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-connector failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-connector\n'
exit 0
