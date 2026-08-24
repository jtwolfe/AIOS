#!/bin/sh
# P8.8: a routine is cron or listeners, never both. Disable leaves git.
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

[ -f "${SEED}/routines.py" ] || fail "missing seed/work-runtime/routines.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/routines.py" ] || fail "missing ISO seed routines.py"
cmp -s "${SEED}/routines.py" "${ISO_SEED}/routines.py" \
  || fail "ISO routines.py != seed routines.py"
cmp -s "${SEED}/main.py" "${ISO_SEED}/main.py" \
  || fail "ISO main.py != seed main.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'cron or listeners, never both' "${SEED}/routines.py" \
  || fail "routines.py missing cron xor listeners"
grep -q 'disable leaves git' "${SEED}/routines.py" \
  || fail "routines.py missing disable-leaves-git"
if grep -nE '^(import|from)[[:space:]]+(urllib|aios_agent|http\.client)\b' \
  "${SEED}/routines.py" >/dev/null; then
  fail "routines must not import urllib/aios_agent/http.client"
fi
if grep -q -- '-Syu' "${SEED}/routines.py"; then
  fail "routines.py contains -Syu (L-20)"
fi

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}"
cp -a "${SEED}/main.py" "${SEED}/wake.py" "${SEED}/skills.py" \
  "${SEED}/provider.py" "${SEED}/workers.py" "${SEED}/routines.py" \
  "${SEED}/bridge.py" "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/main.py" "${_pyct}/wake.py" "${_pyct}/skills.py" \
  "${_pyct}/provider.py" "${_pyct}/workers.py" "${_pyct}/routines.py" \
  "${_pyct}/bridge.py" \
  || fail "py_compile seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-routine.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
printf '%s\n' '{"responses":[{"routine":{"id":"daily","cron":"0 9 * * *"}}]}' \
  > "${TMP}/cron.json"
printf '%s\n' '{"responses":[{"routine":{"id":"on-push","listeners":["push"]}}]}' \
  > "${TMP}/listen.json"
printf '%s\n' '{"responses":[{"routine":{"id":"both","cron":"0 * * * *","listeners":["push"]}}]}' \
  > "${TMP}/both.json"
printf '%s\n' '{"responses":[{"routine":{"id":"none"}}]}' \
  > "${TMP}/none.json"
printf '%s\n' '{"responses":[{"routine_disable":"daily"}]}' \
  > "${TMP}/disable.json"

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

git -C "${SRC}" init -b main >/dev/null
git -C "${SRC}" config user.name aios-work
git -C "${SRC}" config user.email aios-work@localhost
git -C "${SRC}" add AGENTS.md
git -C "${SRC}" commit -q -m "init"

_cron=$(run_turn "${TMP}/cron.json" "create cron") || true
printf '%s\n' "${_cron}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
r = (d.get("routines") or [None])[0]
if not r or r.get("kind") != "cron" or r.get("enabled") is not True:
    raise SystemExit("routine %s" % r)
if r.get("listeners"):
    raise SystemExit("cron grew listeners")
' || fail "cron routine failed: ${_cron}"
[ -f "${SRC}/routines/daily.json" ] || fail "cron routine not a work-store file"

git -C "${SRC}" add routines/daily.json
git -C "${SRC}" commit -q -m "routine daily"
git -C "${SRC}" ls-files --error-unmatch routines/daily.json >/dev/null \
  || fail "cron routine not in git"

_li=$(run_turn "${TMP}/listen.json" "create listener") || true
printf '%s\n' "${_li}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
r = (d.get("routines") or [None])[0]
if not r or r.get("kind") != "listeners":
    raise SystemExit("routine %s" % r)
if r.get("cron"):
    raise SystemExit("listeners grew cron")
' || fail "listener routine failed: ${_li}"
[ -f "${SRC}/routines/on-push.json" ] || fail "listener routine not a work-store file"

_both=$(run_turn "${TMP}/both.json" "both kinds") || true
printf '%s\n' "${_both}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "never both" not in err:
    raise SystemExit("error %s" % err)
' || fail "cron xor listeners must fail: ${_both}"
[ ! -e "${SRC}/routines/both.json" ] || fail "xor routine wrote a file"

_none=$(run_turn "${TMP}/none.json" "neither") || true
printf '%s\n' "${_none}" | grep -q 'cron or listeners' \
  || fail "empty routine must fail: ${_none}"

_dis=$(run_turn "${TMP}/disable.json" "disable daily") || true
printf '%s\n' "${_dis}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
r = (d.get("routines") or [None])[0]
if not r or r.get("enabled") is not False:
    raise SystemExit("disable %s" % r)
' || fail "disable failed: ${_dis}"
[ -f "${SRC}/routines/daily.json" ] || fail "disable deleted the work-store file"
git -C "${SRC}" ls-files --error-unmatch routines/daily.json >/dev/null \
  || fail "disable removed the file from git"
if git -C "${SRC}" status --porcelain -- routines/daily.json | grep -q '^D'; then
  fail "disable staged a git delete"
fi
python3 -c '
import json, sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as fh:
    d = json.load(fh)
if d.get("enabled") is not False:
    raise SystemExit("file still enabled")
if d.get("kind") != "cron":
    raise SystemExit("kind lost")
' "${SRC}/routines/daily.json" || fail "disabled file contents wrong"

env -u AIOS_WORK_SRC env -u AIOS_ROOT \
  python3 "${SRC}/main.py" turn routine >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC routine turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/routines.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed routines.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/routines.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed routines.py"
grep -Fq '/srv/aios/seeds/work-runtime/routines.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed routines.py"

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
  printf 'error: p8-routine failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-routine\n'
exit 0
