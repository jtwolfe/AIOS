#!/bin/sh
# P4.2: fixture completes offline; live refuses before accept / remotes veto;
# OS token path is the lock; checker has no provider import (L-08, L-16, L-17).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/agent/aios_agent/main.py"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${ROOT}/agent/aios_agent/provider/base.py" ] || fail "missing provider/base.py"
[ -f "${ROOT}/agent/aios_agent/provider/fixture.py" ] || fail "missing provider/fixture.py"
[ -f "${ROOT}/agent/aios_agent/provider/live.py" ] || fail "missing provider/live.py"

_hit=$(grep -R -n -- 'provider' "${ROOT}/checker" 2>/dev/null | head -n 1 || true)
[ -z "${_hit}" ] || fail "checker names provider (HI-02, L-08): ${_hit}"

_path=$(python3 "${MAIN}" provider path)
[ "${_path}" = "/srv/aios/state/provider/os.token" ] \
  || fail "provider path is ${_path}, not the P4.2 lock"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
printf '%s\n' '{"responses":["idle-fixture"]}' > "${TMP}/turn.json"

_out=$(python3 "${MAIN}" provider fixture complete "${TMP}/turn.json" ping)
[ "${_out}" = "idle-fixture" ] || fail "fixture complete: ${_out}"

_live=$(python3 "${MAIN}" provider live login PASTED 2>&1) && _rc=0 || _rc=$?
[ "${_rc}" != 0 ] || fail "pasted-key live login must fail"
printf '%s\n' "${_live}" | grep -q 'L-17' \
  || fail "pasted-key refusal missing L-17: ${_live}"

# Injected HTTP: login writes 0600, prints URL+code, never the token (L-16, L-17).
python3 - <<PY || fail "live login write/redact"
import io, json, os, stat, sys
sys.path.insert(0, "${ROOT}/agent/aios_agent")
from provider.live import LiveProvider
from provider.base import ProviderError, OS_TOKEN_PATH

tmp = "${TMP}"
stamp = os.path.join(tmp, "accepted")
missing = os.path.join(tmp, "no-stamp")
answers = os.path.join(tmp, "answers.json")
with open(answers, "w") as fh:
    json.dump({"vetoes": {"remotes": True}}, fh)
tok = os.path.join(tmp, "provider", "os.token")
calls = []

def no_http(method, url, data=None, headers=None, timeout=30):
    raise AssertionError("http must not run")

p = LiveProvider(token_path=tok, accept_stamp=missing, answers_path=answers, http=no_http, sleep=lambda s: None)
try:
    p.login(err=io.StringIO())
except ProviderError as exc:
    if "accept" not in str(exc):
        raise SystemExit("expected accept refusal, got %s" % exc)
else:
    raise SystemExit("missing accept stamp did not fire")

open(stamp, "w").close()

def http(method, url, data=None, headers=None, timeout=30):
    calls.append(url)
    raise AssertionError("http must not run when remotes are vetoed")

p = LiveProvider(token_path=tok, accept_stamp=stamp, answers_path=answers, http=http, sleep=lambda s: None)
try:
    p.login(err=io.StringIO())
except ProviderError as exc:
    if "remotes" not in str(exc):
        raise SystemExit("expected remotes veto, got %s" % exc)
else:
    raise SystemExit("remotes veto did not fire")
if calls:
    raise SystemExit("http ran under remotes veto")

with open(answers, "w") as fh:
    json.dump({"vetoes": {"remotes": False}}, fh)

pending = {"n": 0}

def http2(method, url, data=None, headers=None, timeout=30):
    if url.endswith("/device/code"):
        return 200, {
            "device_code": "hidden-device",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://auth.x.ai/device",
            "interval": 0,
            "expires_in": 60,
        }
    if url.endswith("/token"):
        pending["n"] += 1
        if pending["n"] == 1:
            return 400, {"error": "authorization_pending"}
        return 200, {
            "access_token": "test-access",
            "refresh_token": "test-refresh",
            "token_type": "Bearer",
            "expires_in": 3600,
            "id_token": "must-not-persist",
        }
    raise AssertionError("unexpected url %s" % url)

err = io.StringIO()
p = LiveProvider(token_path=tok, accept_stamp=stamp, answers_path=answers, http=http2, sleep=lambda s: None)
p.login(err=err)
shown = err.getvalue()
if "https://auth.x.ai/device" not in shown or "WDJB-MJHT" not in shown:
    raise SystemExit("login did not print URL and user_code: %s" % shown)
if "test-access" in shown or "test-refresh" in shown or "hidden-device" in shown:
    raise SystemExit("login leaked a secret: %s" % shown)
st = os.stat(tok)
if stat.S_IMODE(st.st_mode) != 0o600:
    raise SystemExit("token mode %o" % stat.S_IMODE(st.st_mode))
dst = os.stat(os.path.dirname(tok))
if stat.S_IMODE(dst.st_mode) != 0o700:
    raise SystemExit("token dir mode %o" % stat.S_IMODE(dst.st_mode))
with open(tok) as fh:
    saved = json.load(fh)
if saved.get("access_token") != "test-access":
    raise SystemExit("token missing access_token")
if "id_token" in saved:
    raise SystemExit("id_token persisted")
if OS_TOKEN_PATH != "/srv/aios/state/provider/os.token":
    raise SystemExit("lock drifted")

try:
    LiveProvider(token_path="/home/operator/os.token")
except ProviderError:
    pass
else:
    raise SystemExit("/home token path accepted")
try:
    LiveProvider(token_path="/etc/aios/os.token")
except ProviderError:
    pass
else:
    raise SystemExit("/etc/aios token path accepted")

# Fixture still has no network client.
from provider.fixture import FixtureProvider
fx = os.path.join(tmp, "turn.json")
fp = FixtureProvider(fx)
assert fp.complete("x") == "idle-fixture"
try:
    fp.complete("x")
except ProviderError as exc:
    if "exhausted" not in str(exc):
        raise SystemExit("expected exhausted fixture, got %s" % exc)
else:
    raise SystemExit("exhausted fixture did not fire")
PY

grep -q '/provider/' "${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot" \
  || fail "firstboot does not gitignore /provider/ (L-16)"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p4-provider failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p4-provider\n'
exit 0
