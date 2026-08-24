#!/bin/sh
# P8.10: work provider own fixture/live. L-17 device-code. Not the OS token.
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

[ -f "${SEED}/provider.py" ] || fail "missing seed/work-runtime/provider.py"
[ -f "${SEED}/live.py" ] || fail "missing seed/work-runtime/live.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/provider.py" ] || fail "missing ISO seed provider.py"
[ -f "${ISO_SEED}/live.py" ] || fail "missing ISO seed live.py"
cmp -s "${SEED}/provider.py" "${ISO_SEED}/provider.py" \
  || fail "ISO provider.py != seed provider.py"
cmp -s "${SEED}/live.py" "${ISO_SEED}/live.py" \
  || fail "ISO live.py != seed live.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -qx 'OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"' \
  "${SEED}/provider.py" \
  || fail "provider.py OS token path lock drifted"
grep -qx 'WORK_TOKEN_PATH = "/srv/aios/src/work-runtime/.provider/work.token"' \
  "${SEED}/provider.py" \
  || fail "provider.py work token path lock drifted"
grep -q 'work uid cannot read the OS token (L-16)' "${SEED}/provider.py" \
  || fail "provider.py missing L-16 OS token refusal"
grep -q 'user_code:' "${SEED}/live.py" \
  || fail "live.py must print user_code"
grep -q 'aios-work' "${SEED}/live.py" \
  || fail "live.py must chown the work token to aios-work"
if grep -nE '^(import|from)[[:space:]]+aios_agent\b' \
  "${SEED}/provider.py" "${SEED}/live.py" >/dev/null; then
  fail "work provider must not import aios_agent (L-16)"
fi
if grep -nE 'XAI_API_KEY' "${SEED}/provider.py" "${SEED}/live.py" >/dev/null; then
  fail "work provider must not read XAI_API_KEY"
fi
grep -qx '**/work.token' "${ROOT}/.gitignore" \
  || fail ".gitignore missing **/work.token (L-16)"
grep -qx '**/.work.token.*' "${ROOT}/.gitignore" \
  || fail ".gitignore missing **/.work.token.* (L-16)"
grep -q 'work.token' "${SEED}/.gitignore" \
  || fail "seed work-runtime .gitignore must ignore work.token"

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}"
cp -a "${SEED}/main.py" "${SEED}/skills.py" "${SEED}/wake.py" \
  "${SEED}/provider.py" "${SEED}/live.py" "${SEED}/connectors.py" \
  "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/main.py" "${_pyct}/skills.py" "${_pyct}/wake.py" \
  "${_pyct}/provider.py" "${_pyct}/live.py" "${_pyct}/connectors.py" \
  || fail "py_compile seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-provider.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
printf '%s\n' '{"responses":["idle-fixture"]}' > "${TMP}/turn.json"

_path=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    python3 "${SRC}/main.py" provider path
)
[ "${_path}" = "/srv/aios/src/work-runtime/.provider/work.token" ] \
  || fail "provider path is ${_path}, not the P8.10 lock"

_ospath=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    python3 "${SRC}/main.py" provider os-path
)
[ "${_ospath}" = "/srv/aios/state/provider/os.token" ] \
  || fail "os-path is ${_ospath}, not the P4.2 lock"

_fix=$(
  env -u AIOS_PROVIDER -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_FIXTURE="${TMP}/turn.json" \
    python3 "${SRC}/main.py" provider fixture complete "${TMP}/turn.json" ping
)
[ "${_fix}" = "idle-fixture" ] || fail "fixture complete: ${_fix}"

_def=$(
  env -u AIOS_PROVIDER -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_FIXTURE="${TMP}/turn.json" \
    python3 - "${SRC}" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
from provider import load
p = load()
print(p.name)
PY
)
[ "${_def}" = "fixture" ] || fail "unset AIOS_PROVIDER must default to fixture: ${_def}"

_paste=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    python3 "${SRC}/main.py" provider live login PASTED 2>&1
) && _rc=0 || _rc=$?
[ "${_rc}" != 0 ] || fail "pasted-key live login must fail"
printf '%s\n' "${_paste}" | grep -q 'L-17' \
  || fail "pasted-key refusal missing L-17: ${_paste}"

python3 - "${SRC}" "${TMP}" <<'PY' || fail "live login write/redact"
import io, json, os, stat, sys
sys.path.insert(0, sys.argv[1])
from live import LiveProvider
from provider import OS_TOKEN_PATH, ProviderError, WORK_TOKEN_PATH

src = sys.argv[1]
tmp = sys.argv[2]
tok = os.path.join(tmp, "work.token")
os_tok = os.path.join(tmp, "root", "srv", "aios", "state", "provider", "os.token")
os.makedirs(os.path.dirname(os_tok), mode=0o700, exist_ok=True)
with open(os_tok, "w") as fh:
    fh.write("OS-SECRET-MUST-NOT-BE-READ\n")
os.chmod(os_tok, 0o600)

compiled = os.path.join(src, "envelope", "compiled.md")
with open(compiled, "w") as fh:
    fh.write("enabled: no\n")

def no_http(method, url, data=None, headers=None, timeout=30):
    raise AssertionError("http must not run")

p = LiveProvider(token_path=tok, http=no_http, sleep=lambda s: None, root=src)
try:
    p.login(err=io.StringIO())
except ProviderError as exc:
    if "accept" not in str(exc) and "L-17" not in str(exc):
        raise SystemExit("expected accept refusal, got %s" % exc)
else:
    raise SystemExit("disabled envelope did not refuse live login")

with open(compiled, "w") as fh:
    fh.write("enabled: yes\nvetoes.remotes: yes\n")

calls = []

def http(method, url, data=None, headers=None, timeout=30):
    calls.append(url)
    raise AssertionError("http must not run when remotes are vetoed")

p = LiveProvider(token_path=tok, http=http, sleep=lambda s: None, root=src)
try:
    p.login(err=io.StringIO())
except ProviderError as exc:
    if "remotes" not in str(exc):
        raise SystemExit("expected remotes veto, got %s" % exc)
else:
    raise SystemExit("remotes veto did not fire")
if calls:
    raise SystemExit("http ran under remotes veto")

with open(compiled, "w") as fh:
    fh.write("enabled: yes\nvetoes.remotes: no\n")
os.environ["AIOS_WORK_REMOTES"] = "yes"
calls_pin = []

def http_pin(method, url, data=None, headers=None, timeout=30):
    calls_pin.append(url)
    raise AssertionError("http must not run when remotes are pinned")

p = LiveProvider(token_path=tok, http=http_pin, sleep=lambda s: None, root=src)
try:
    p.login(err=io.StringIO())
except ProviderError as exc:
    if "remotes" not in str(exc):
        raise SystemExit("expected env remotes veto, got %s" % exc)
else:
    raise SystemExit("work-writable remotes no overrode AIOS_WORK_REMOTES")
if calls_pin:
    raise SystemExit("http ran under AIOS_WORK_REMOTES")
os.environ.pop("AIOS_WORK_REMOTES", None)

from provider import _guard_path, under_os_state
if not under_os_state("/srv/aios/state"):
    raise SystemExit("under_os_state missed /srv/aios/state")
try:
    _guard_path("/srv/aios/state")
except ProviderError as exc:
    if "L-16" not in str(exc):
        raise SystemExit("expected L-16 for /srv/aios/state, got %s" % exc)
else:
    raise SystemExit("/srv/aios/state accepted")

with open(compiled, "w") as fh:
    fh.write("enabled: yes\nvetoes.remotes: no\n")

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
p = LiveProvider(token_path=tok, http=http2, sleep=lambda s: None, root=src)
p.login(err=err)
shown = err.getvalue()
if "https://auth.x.ai/device" not in shown or "WDJB-MJHT" not in shown:
    raise SystemExit("login did not print URL and user_code: %s" % shown)
if "test-access" in shown or "test-refresh" in shown or "hidden-device" in shown:
    raise SystemExit("login leaked a secret: %s" % shown)
if "OS-SECRET-MUST-NOT-BE-READ" in shown:
    raise SystemExit("login leaked the OS token")
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
if WORK_TOKEN_PATH != "/srv/aios/src/work-runtime/.provider/work.token":
    raise SystemExit("work lock drifted")
if OS_TOKEN_PATH != "/srv/aios/state/provider/os.token":
    raise SystemExit("OS lock drifted")
if os.path.abspath(tok) == OS_TOKEN_PATH:
    raise SystemExit("work token path collapsed onto OS token")

try:
    LiveProvider(token_path="/home/operator/work.token", root=src)
except ProviderError:
    pass
else:
    raise SystemExit("/home token path accepted")
try:
    LiveProvider(token_path="/etc/aios/work.token", root=src)
except ProviderError:
    pass
else:
    raise SystemExit("/etc/aios token path accepted")
try:
    LiveProvider(token_path=OS_TOKEN_PATH, root=src)
except ProviderError as exc:
    if "L-16" not in str(exc):
        raise SystemExit("OS token path refusal missing L-16: %s" % exc)
else:
    raise SystemExit("OS token path accepted as work token")
try:
    LiveProvider(token_path=os_tok, root=src)
except ProviderError:
    pass
else:
    raise SystemExit("destroot OS token path accepted")

def http_http_uri(method, url, data=None, headers=None, timeout=30):
    if url.endswith("/device/code"):
        return 200, {
            "device_code": "hidden-device",
            "user_code": "WDJB-MJHT",
            "verification_uri": "http://evil.example/device",
            "interval": 0,
            "expires_in": 60,
        }
    raise AssertionError("token poll must not run for a bad URI")

err = io.StringIO()
p = LiveProvider(token_path=tok, http=http_http_uri, sleep=lambda s: None, root=src)
try:
    p.login(err=err)
except ProviderError as exc:
    if "https" not in str(exc):
        raise SystemExit("expected https refusal, got %s" % exc)
else:
    raise SystemExit("http URI accepted")
shown = err.getvalue()
if "evil.example" in shown or "http://" in shown:
    raise SystemExit("bad URI printed: %s" % shown)

def http_nl_uri(method, url, data=None, headers=None, timeout=30):
    if url.endswith("/device/code"):
        return 200, {
            "device_code": "hidden-device",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://auth.x.ai/device\nhttps://evil.example",
            "interval": 0,
            "expires_in": 60,
        }
    raise AssertionError("token poll must not run for a bad URI")

err = io.StringIO()
p = LiveProvider(token_path=tok, http=http_nl_uri, sleep=lambda s: None, root=src)
try:
    p.login(err=err)
except ProviderError as exc:
    if "whitespace" not in str(exc):
        raise SystemExit("expected whitespace refusal, got %s" % exc)
else:
    raise SystemExit("newline URI accepted")
if "evil.example" in err.getvalue():
    raise SystemExit("newline URI printed")

import live as live_mod

class FakePw(object):
    pw_uid = 4242
    pw_gid = 4243

class FakePwd(object):
    @staticmethod
    def getpwnam(name):
        if name != "aios-work":
            raise KeyError(name)
        return FakePw()

chowned = []
saved_euid = live_mod.os.geteuid
saved_chown = live_mod.os.chown
saved_pwd = live_mod.pwd
live_mod.os.geteuid = lambda: 0
live_mod.os.chown = lambda path, uid, gid: chowned.append((path, uid, gid))
live_mod.pwd = FakePwd
pending["n"] = 0
err = io.StringIO()
p = LiveProvider(token_path=tok, http=http2, sleep=lambda s: None, root=src)
try:
    p.login(err=err)
finally:
    live_mod.os.geteuid = saved_euid
    live_mod.os.chown = saved_chown
    live_mod.pwd = saved_pwd
if not chowned:
    raise SystemExit("root write did not chown")
if not any(t[1] == 4242 and t[2] == 4243 for t in chowned):
    raise SystemExit("chown ids %s" % (chowned,))
if not any(t[0] == tok for t in chowned):
    raise SystemExit("token path not chowned: %s" % (chowned,))

from provider import FixtureProvider
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
try:
    FixtureProvider(os_tok)
except ProviderError as exc:
    if "L-16" not in str(exc):
        raise SystemExit("fixture OS token path missing L-16: %s" % exc)
else:
    raise SystemExit("fixture accepted OS token path")

# Token file is not a git object in the work tree.
ignore = os.path.join(src, ".gitignore")
with open(ignore) as fh:
    gi = fh.read()
if "work.token" not in gi:
    raise SystemExit("work tree gitignore missing work.token")
PY

_http="${TMP}/login-http.json"
cat > "${_http}" <<'EOF'
{
  "device": {
    "device_code": "hidden-device",
    "user_code": "WDJB-MJHT",
    "verification_uri": "https://auth.x.ai/device",
    "interval": 0,
    "expires_in": 60
  },
  "polls": [
    {"error": "authorization_pending"},
    {
      "access_token": "test-access",
      "refresh_token": "test-refresh",
      "token_type": "Bearer",
      "expires_in": 3600
    }
  ]
}
EOF
_cli=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_TOKEN="${TMP}/cli.token" \
    AIOS_PROVIDER_HTTP="${_http}" \
    python3 "${SRC}/main.py" provider live login 2>"${TMP}/cli.err"
) || fail "cli live login failed: $(cat "${TMP}/cli.err")"
[ "${_cli}" = "ok: login" ] || fail "cli live login stdout: ${_cli}"
grep -q 'https://auth.x.ai/device' "${TMP}/cli.err" \
  || fail "cli login missing URL"
grep -q 'user_code: WDJB-MJHT' "${TMP}/cli.err" \
  || fail "cli login missing user_code"
if grep -q 'test-access' "${TMP}/cli.err"; then
  fail "cli login leaked token"
fi
printf '%s\n' "${_cli}" | grep -q 'test-access' \
  && fail "cli login leaked token on stdout" || true
[ "$(stat -c '%a' "${TMP}/cli.token")" = 600 ] \
  || fail "cli token mode $(stat -c '%a' "${TMP}/cli.token")"

env -u AIOS_WORK_SRC env -u AIOS_ROOT \
  python3 "${SRC}/main.py" provider path >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC provider path created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/provider.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed provider.py"
grep -Fq 'seed/work-runtime/live.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed live.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/live.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed live.py"
grep -Fq '/srv/aios/seeds/work-runtime/live.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed live.py"
grep -Fq 'seed/work-runtime/.gitignore' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed work-runtime .gitignore"

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
  printf 'error: p8-provider failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-provider\n'
exit 0
