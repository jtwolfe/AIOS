#!/bin/sh
# P7.6: L-17 device-code login view. Token never in transcript. No auth.x.ai.
# Envelope: P7.6, L-17, L-16, L-18.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
LIVE="${ROOT}/agent/aios_agent/provider/live.py"
GATE="${ROOT}/agent/aios_agent/login_gate.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_LIVE="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent/aios_agent/provider/live.py"
ISO_GATE="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent/aios_agent/login_gate.py"
HASHES="${ROOT}/payload/hashes.txt"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${LIVE}" ] || fail "missing ${LIVE}"
[ -f "${GATE}" ] || fail "missing ${GATE}"
[ -f "${ISO_OC}/tty/aios.py" ] || fail "missing ISO aios.py"
[ -f "${ISO_LIVE}" ] || fail "missing ISO live.py"
[ -f "${ISO_GATE}" ] || fail "missing ISO login_gate.py"

grep -q 'P7.6' "${MAIN}" || fail "aios.py must quote P7.6"
grep -q 'L-17' "${MAIN}" || fail "aios.py must quote L-17"
grep -q 'L-16' "${MAIN}" || fail "aios.py must quote L-16"
grep -q 'never a pasted API key' "${MAIN}" \
  || fail "aios.py must refuse a pasted API key (L-17)"
grep -q 'http_from_fixture' "${LIVE}" \
  || fail "live.py must offer an injected http fixture (L-17)"
grep -q 'login-request' "${MAIN}" \
  || fail "aios.py must file login-request (L-16)"
grep -q 'tick_login' "${GATE}" \
  || fail "login_gate.py must tick live login for the unit"
grep -q 'os.replace(' "${GATE}" \
  && fail "login_gate must not os.replace rendezvous inodes" || true
grep -q '_write_inplace' "${GATE}" \
  || fail "login_gate must write rendezvous in place"
python3 - "${MAIN}" <<'PY' || fail "production start must not construct LiveProvider"
import ast
import sys

tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if not isinstance(node, ast.ClassDef) or node.name != "Session":
        continue
    for item in node.body:
        if not isinstance(item, ast.FunctionDef):
            continue
        if item.name != "_login_start_rendezvous":
            continue
        names = [n.id for n in ast.walk(item) if isinstance(n, ast.Name)]
        if "LiveProvider" in names:
            raise SystemExit("rendezvous constructs LiveProvider")
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
cp -a "${LIVE}" "${_pyct}/live.py" || fail "copy live.py for py_compile"
cp -a "${GATE}" "${_pyct}/login_gate.py" || fail "copy login_gate.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" "${_pyct}/live.py" "${_pyct}/login_gate.py" \
  || fail "py_compile failed"
rm -rf "${_pyct}"

sh -n "${0}" || fail "sh -n p7-login.sh"

cmp -s "${MAIN}" "${ISO_OC}/tty/aios.py" \
  || fail "ISO aios.py bytes differ"
cmp -s "${LIVE}" "${ISO_LIVE}" \
  || fail "ISO live.py bytes differ"
cmp -s "${GATE}" "${ISO_GATE}" \
  || fail "ISO login_gate.py bytes differ"

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -En -- '[[:space:]]sudo[[:space:]]|sudo$|NOPASSWD' "${MAIN}" 2>/dev/null
then
  fail "login view must not sudo (L-17)"
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_TOKEN="/srv/aios/state/provider/os.token"
LIVE_BRAKE="/srv/aios/state/brake.d/stamp"
_live_token=0
_live_brake=0
[ -e "${LIVE_TOKEN}" ] && _live_token=1
[ -e "${LIVE_BRAKE}" ] && _live_brake=1

mkdir -p \
  "${TMP}/root/etc/aios" \
  "${TMP}/root/srv/aios/state/bootstrap-in-progress" \
  "${TMP}/root/srv/aios/state/provider" \
  "${TMP}/root/run/aios" \
  "${TMP}/nowrite-parent"
: > "${TMP}/root/run/aios/login-request"
: > "${TMP}/root/run/aios/login-status"
chmod 0660 "${TMP}/root/run/aios/login-request"
chmod 0640 "${TMP}/root/run/aios/login-status"

TOKEN="${TMP}/root/srv/aios/state/provider/os.token"
STAMP="${TMP}/root/etc/aios/envelope-accepted"
ANSWERS="${TMP}/root/srv/aios/state/bootstrap-in-progress/answers.json"
HTTP="${TMP}/http.json"
PENDING="${TMP}/pending.json"

printf '%s\n' '{"vetoes":{"remotes":false}}' > "${ANSWERS}"
: > "${STAMP}"

python3 - "${HTTP}" "${PENDING}" <<'PY' || fail "write http fixtures"
import json
import sys

http_path, pending_path = sys.argv[1], sys.argv[2]
doc = {
    "user_code": "WDJB-MJHT",
    "verification_uri": "https://auth.x.ai/device",
    "device_code": "hidden-device",
    "interval": 0,
    "expires_in": 60,
    "access_token": "test-access-token",
    "refresh_token": "test-refresh-token",
}
with open(http_path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh)
    fh.write("\n")
pending = dict(doc)
pending.pop("access_token")
pending.pop("refresh_token")
with open(pending_path, "w", encoding="utf-8") as fh:
    json.dump(pending, fh)
    fh.write("\n")
PY

drive() {
  printf '%s\n' "$@" | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OS_TOKEN="${TOKEN}" \
    AIOS_ACCEPT_STAMP="${STAMP}" \
    AIOS_ANSWERS="${ANSWERS}" \
    AIOS_PROVIDER_HTTP="${HTTP}" \
    AIOS_AGENT="${ROOT}/agent/aios_agent" \
    python3 -u "${MAIN}" 2>&1
}

_before=$(drive 'view login' 'start' 'quit') || true
printf '%s\n' "${_before}" | grep -q 'live login is after envelope accept (L-17)' \
  && fail "login with stamp still quoted before-accept: ${_before}" || true
printf '%s\n' "${_before}" | grep -q 'https://auth.x.ai/device' \
  || fail "login must print verification URL: ${_before}"
printf '%s\n' "${_before}" | grep -q 'user_code: WDJB-MJHT' \
  || fail "login must print user_code: ${_before}"
printf '%s\n' "${_before}" | grep -q 'hidden-device' \
  && fail "device_code leaked into transcript: ${_before}" || true
printf '%s\n' "${_before}" | grep -q 'test-access-token' \
  && fail "access_token leaked into transcript: ${_before}" || true
printf '%s\n' "${_before}" | grep -q 'test-refresh-token' \
  && fail "refresh_token leaked into transcript: ${_before}" || true
printf '%s\n' "${_before}" | grep -q 'login ok (L-17)' \
  || fail "injected http login must complete: ${_before}"
[ -f "${TOKEN}" ] || fail "token file missing after login"
_mode=$(stat -c '%a' "${TOKEN}")
[ "${_mode}" = 600 ] || fail "token mode is ${_mode}, not 0600"
_dmode=$(stat -c '%a' "$(dirname "${TOKEN}")")
[ "${_dmode}" = 700 ] || fail "token dir mode is ${_dmode}, not 0700"
python3 - "${TOKEN}" <<'PY' || fail "token JSON"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("access_token") != "test-access-token":
    raise SystemExit("access_token missing")
if "id_token" in data:
    raise SystemExit("id_token persisted")
PY

# Remotes veto: refuse with L-17 and do not write a new token.
rm -f "${TOKEN}"
printf '%s\n' '{"vetoes":{"remotes":true}}' > "${ANSWERS}"
_veto=$(drive 'view login' 'start' 'quit') || true
printf '%s\n' "${_veto}" | grep -q 'remotes vetoed live login (L-17)' \
  || fail "remotes veto must quote L-17: ${_veto}"
printf '%s\n' "${_veto}" | grep -q 'https://auth.x.ai/device' \
  && fail "remotes veto must not print a URL: ${_veto}" || true
[ ! -f "${TOKEN}" ] || fail "remotes veto wrote a token"

# After envelope accept only.
printf '%s\n' '{"vetoes":{"remotes":false}}' > "${ANSWERS}"
rm -f "${STAMP}"
_noacc=$(drive 'l' 'start' 'quit') || true
printf '%s\n' "${_noacc}" | grep -q 'live login is after envelope accept (L-17)' \
  || fail "missing stamp must quote L-17: ${_noacc}"
printf '%s\n' "${_noacc}" | grep -q 'https://auth.x.ai/device' \
  && fail "missing stamp must not print a URL: ${_noacc}" || true
[ ! -f "${TOKEN}" ] || fail "missing stamp wrote a token"
: > "${STAMP}"

_paste=$(drive 'view login' 'start pasted-key' 'send xai-secret' 'quit') || true
printf '%s\n' "${_paste}" | grep -q 'never a pasted API key (L-17)' \
  || fail "pasted key must be refused with L-17: ${_paste}"
printf '%s\n' "${_paste}" | grep -q 'xai-secret' \
  && fail "pasted secret echoed: ${_paste}" || true

_fix=$(
  printf '%s\n' 'view login' 'start' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OS_TOKEN="${TOKEN}" \
    AIOS_ACCEPT_STAMP="${STAMP}" \
    AIOS_ANSWERS="${ANSWERS}" \
    AIOS_PROVIDER=fixture \
    AIOS_PROVIDER_HTTP="${HTTP}" \
    AIOS_AGENT="${ROOT}/agent/aios_agent" \
    python3 -u "${MAIN}" 2>&1
) || true
printf '%s\n' "${_fix}" | grep -q 'fixture has no live login (L-17)' \
  || fail "fixture must not login: ${_fix}"
printf '%s\n' "${_fix}" | grep -q 'https://auth.x.ai/device' \
  && fail "fixture login printed a URL: ${_fix}" || true

_cancel=$(
  printf '%s\n' 'view login' 'start' 'cancel' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OS_TOKEN="${TOKEN}" \
    AIOS_ACCEPT_STAMP="${STAMP}" \
    AIOS_ANSWERS="${ANSWERS}" \
    AIOS_PROVIDER_HTTP="${PENDING}" \
    AIOS_AGENT="${ROOT}/agent/aios_agent" \
    python3 -u "${MAIN}" 2>&1
) || true
printf '%s\n' "${_cancel}" | grep -q 'login-status: waiting' \
  || fail "pending start must wait: ${_cancel}"
printf '%s\n' "${_cancel}" | grep -q 'login-status: cancelled' \
  || fail "cancel must stop waiting: ${_cancel}"
printf '%s\n' "${_cancel}" | grep -q 'user_code: WDJB-MJHT' \
  || fail "cancel path must still show user_code: ${_cancel}"
printf '%s\n' "${_cancel}" | grep -q 'hidden-device' \
  && fail "cancel path leaked device_code: ${_cancel}" || true
[ ! -f "${TOKEN}" ] || fail "cancel wrote a token"

# Unwritable token path: fail with a reason, never sudo.
printf x > "${TMP}/nowrite-parent/notdir"
_nowrite=$(
  printf '%s\n' 'view login' 'start' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OS_TOKEN="${TMP}/nowrite-parent/notdir/os.token" \
    AIOS_ACCEPT_STAMP="${STAMP}" \
    AIOS_ANSWERS="${ANSWERS}" \
    AIOS_PROVIDER_HTTP="${HTTP}" \
    AIOS_AGENT="${ROOT}/agent/aios_agent" \
    python3 -u "${MAIN}" 2>&1
) || true
printf '%s\n' "${_nowrite}" | grep -q 'cannot write OS token' \
  || fail "unwritable token must explain L-16: ${_nowrite}"
printf '%s\n' "${_nowrite}" | grep -q 'L-16' \
  || fail "unwritable token must quote L-16: ${_nowrite}"
printf '%s\n' "${_nowrite}" | grep -Eqi 'sudo' \
  && fail "unwritable token must not sudo: ${_nowrite}" || true

REQ="${TMP}/root/run/aios/login-request"
STU="${TMP}/root/run/aios/login-status"
rm -f "${TOKEN}"
: > "${REQ}"
: > "${STU}"
chmod 0660 "${REQ}"
chmod 0640 "${STU}"
python3 - "${REQ}" "${STU}" <<'PY' || fail "could not set rendezvous mode/group"
import os
import sys

req, stu = sys.argv[1], sys.argv[2]
uid = os.getuid()
cur = os.stat(req).st_gid
alts = [g for g in os.getgroups() if g != cur]
want = alts[0] if alts else cur
try:
    os.chown(req, uid, want)
    os.chown(stu, uid, want)
except OSError:
    want = cur
os.chmod(req, 0o660)
os.chmod(stu, 0o640)
if (os.stat(req).st_mode & 0o777) != 0o660:
    raise SystemExit("request not 0660")
if (os.stat(stu).st_mode & 0o777) != 0o640:
    raise SystemExit("status not 0640")
PY

prod() {
  printf '%s\n' "$@" | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_ACCEPT_STAMP="${STAMP}" \
    AIOS_ANSWERS="${ANSWERS}" \
    AIOS_AGENT="${ROOT}/agent/aios_agent" \
    python3 -u "${MAIN}" 2>&1
}

agent_tick() {
  AIOS_ROOT="${TMP}/root" \
  AIOS_OS_TOKEN="${TOKEN}" \
  AIOS_ACCEPT_STAMP="${STAMP}" \
  AIOS_ANSWERS="${ANSWERS}" \
  AIOS_PROVIDER_HTTP="${1}" \
  AIOS_AGENT="${ROOT}/agent/aios_agent" \
  PYTHONPATH="${ROOT}/agent/aios_agent" \
  python3 -c 'from login_gate import reset_for_tests, tick_login
reset_for_tests()
tick_login()
tick_login()'
}

_prod=$(prod 'view login' 'start' 'quit') || true
printf '%s\n' "${_prod}" | grep -q 'login started (L-17)' \
  || fail "production start must file a request: ${_prod}"
printf '%s\n' "${_prod}" | grep -q 'https://auth.x.ai/device' \
  && fail "production start must not device-code in-process: ${_prod}" || true
grep -qx 'start' "${REQ}" \
  || fail "production start must write login-request"
[ ! -f "${TOKEN}" ] || fail "production TUI wrote os.token (L-16)"

_req_ino=$(stat -c '%i %g %a' "${REQ}")
_stu_ino=$(stat -c '%i %g %a' "${STU}")
agent_tick "${HTTP}" || fail "agent tick failed"
[ -f "${TOKEN}" ] || fail "agent tick did not write token"
_mode=$(stat -c '%a' "${TOKEN}")
[ "${_mode}" = 600 ] || fail "agent token mode is ${_mode}, not 0600"
_rmode=$(stat -c '%a' "${REQ}")
_smode=$(stat -c '%a' "${STU}")
[ "${_rmode}" = 660 ] \
  || fail "login-request mode after tick is ${_rmode}, not 0660"
[ "${_smode}" = 640 ] \
  || fail "login-status mode after tick is ${_smode}, not 0640"
[ "$(stat -c '%i %g %a' "${REQ}")" = "${_req_ino}" ] \
  || fail "login-request inode/group dropped after tick"
[ "$(stat -c '%i %g %a' "${STU}")" = "${_stu_ino}" ] \
  || fail "login-status inode/group dropped after tick"
if grep -E 'test-access-token|test-refresh-token|hidden-device' "${STU}"
then
  fail "login-status leaked a secret"
fi
_shown=$(prod 'view login' 'quit') || true
printf '%s\n' "${_shown}" | grep -q 'https://auth.x.ai/device' \
  || fail "TUI must read URL from login-status: ${_shown}"
printf '%s\n' "${_shown}" | grep -q 'user_code: WDJB-MJHT' \
  || fail "TUI must read user_code from login-status: ${_shown}"
printf '%s\n' "${_shown}" | grep -q 'test-access-token' \
  && fail "status path leaked access_token: ${_shown}" || true
printf '%s\n' "${_shown}" | grep -q 'login-status: ok' \
  || fail "agent tick must complete login: ${_shown}"

python3 - "${ROOT}" "${HTTP}" "${STAMP}" "${ANSWERS}" "${TMP}" <<'PY' || fail "agent write must chown aios-agent"
import io
import json
import os
import sys

root, http, stamp, answers, tmp = sys.argv[1:]
sys.path.insert(0, os.path.join(root, "agent", "aios_agent"))
os.environ["AIOS_ROOT"] = os.path.join(tmp, "chown-root")
os.environ["AIOS_OS_TOKEN"] = os.path.join(tmp, "chown-root", "srv", "aios", "state", "provider", "os.token")
os.environ["AIOS_ACCEPT_STAMP"] = stamp
os.environ["AIOS_ANSWERS"] = answers
os.environ["AIOS_PROVIDER_HTTP"] = http
os.makedirs(os.path.join(tmp, "chown-root", "run", "aios"), exist_ok=True)
os.makedirs(os.path.join(tmp, "chown-root", "srv", "aios", "state", "provider"), exist_ok=True)
req = os.path.join(tmp, "chown-root", "run", "aios", "login-request")
st = os.path.join(tmp, "chown-root", "run", "aios", "login-status")
open(req, "w").write("start\n")
open(st, "w").close()
import login_gate
import provider.live as live_mod

class FakePw(object):
    pw_uid = 4242
    pw_gid = 4243

class FakePwd(object):
    @staticmethod
    def getpwnam(name):
        if name != "aios-agent":
            raise KeyError(name)
        return FakePw()

chowned = []
saved_euid = live_mod.os.geteuid
saved_chown = live_mod.os.chown
saved_pwd = live_mod.pwd
live_mod.os.geteuid = lambda: 0
live_mod.os.chown = lambda path, uid, gid: chowned.append((path, uid, gid))
live_mod.pwd = FakePwd
login_gate.reset_for_tests()
try:
    login_gate.tick_login()
    login_gate.tick_login()
finally:
    live_mod.os.geteuid = saved_euid
    live_mod.os.chown = saved_chown
    live_mod.pwd = saved_pwd
tok = os.environ["AIOS_OS_TOKEN"]
if not any(t[0] == tok and t[1] == 4242 for t in chowned):
    raise SystemExit("token not chowned to aios-agent: %s" % (chowned,))
PY

if [ -f "${LIVE_TOKEN}" ]; then
  _owner=$(stat -c '%U' "${LIVE_TOKEN}")
  if id -u aios-agent >/dev/null 2>&1; then
    [ "${_owner}" = aios-agent ] \
      || fail "production os.token uid is ${_owner}, not aios-agent (L-16)"
  fi
fi

if [ "${_live_token}" -eq 0 ] && [ -e "${LIVE_TOKEN}" ]; then
  rm -f "${LIVE_TOKEN}"
  fail "oracle created ${LIVE_TOKEN}"
fi
if [ "${_live_brake}" -eq 0 ] && [ -e "${LIVE_BRAKE}" ]; then
  rm -f "${LIVE_BRAKE}"
  fail "oracle created ${LIVE_BRAKE}"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-login failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-login\n'
exit 0
