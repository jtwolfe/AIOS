#!/bin/sh
# P8.7: workers have no voice; results are sent; they cannot enact.
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

[ -f "${SEED}/workers.py" ] || fail "missing seed/work-runtime/workers.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/workers.py" ] || fail "missing ISO seed workers.py"
cmp -s "${SEED}/workers.py" "${ISO_SEED}/workers.py" \
  || fail "ISO workers.py != seed workers.py"
cmp -s "${SEED}/main.py" "${ISO_SEED}/main.py" \
  || fail "ISO main.py != seed main.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'workers have no user-visible voice' "${SEED}/workers.py" \
  || fail "workers.py missing no-voice rule"
grep -q 'workers cannot enact' "${SEED}/workers.py" \
  || fail "workers.py missing cannot-enact rule"
grep -q 'results are sent, not only acknowledged' "${SEED}/workers.py" \
  || fail "workers.py missing result-sent rule"
grep -q 'coding on a branch is a branch plus merge request' "${SEED}/workers.py" \
  || fail "workers.py missing branch+MR rule"
if grep -nE '^(import|from)[[:space:]]+(urllib|aios_agent|http\.client)\b' \
  "${SEED}/main.py" "${SEED}/workers.py" >/dev/null; then
  fail "workers must not import urllib/aios_agent/http.client"
fi
if grep -nE 'github\.com|auth\.x\.ai' "${SEED}/main.py" "${SEED}/workers.py" \
  >/dev/null; then
  fail "workers must not call live Grok"
fi
if grep -q -- '-Syu' "${SEED}/workers.py"; then
  fail "workers.py contains -Syu (L-20)"
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
sh -n "${0}" || fail "sh -n p8-worker.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
printf '%s\n' '{"responses":[{"dispatch":{"id":"w1","task":"sum","result":"worker-result-42"}}]}' \
  > "${TMP}/dispatch.json"
printf '%s\n' '{"responses":[{"dispatch":{"id":"evil","task":"enact -Syu","result":"nope"}}]}' \
  > "${TMP}/enact.json"
printf '%s\n' '{"responses":[{"dispatch":{"id":"talk","voice":"hello-human","result":"x"}}]}' \
  > "${TMP}/voice.json"
printf '%s\n' '{"responses":[{"dispatch":{"id":"ack","complete":true}}]}' \
  > "${TMP}/ack.json"
printf '%s\n' '{"responses":[{"dispatch":{"id":"bg","task":"long","complete":false}}]}' \
  > "${TMP}/running.json"
printf '%s\n' '{"responses":[{"check":"bg"}]}' > "${TMP}/check.json"
printf '%s\n' '{"responses":[{"stop":"bg"}]}' > "${TMP}/stop.json"
printf '%s\n' '{"responses":[{"coding":{"id":"code1","slug":"widget","result":"mr-open"}}]}' \
  > "${TMP}/coding.json"
printf '%s\n' '{"responses":[{"actions":[{"tool":"dispatch","id":"w2","result":"via-actions"}]}]}' \
  > "${TMP}/actions.json"

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

_out=$(run_turn "${TMP}/dispatch.json" "dispatch worker") || true
printf '%s\n' "${_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
workers = d.get("workers") or []
if not workers:
    raise SystemExit("no workers")
w = workers[0]
if w.get("voice"):
    raise SystemExit("worker voice %s" % w.get("voice"))
if w.get("status") != "done":
    raise SystemExit("status %s" % w.get("status"))
if w.get("result") != "worker-result-42":
    raise SystemExit("result %s" % w.get("result"))
if d.get("delivered") != "worker-result-42":
    raise SystemExit("delivered %s" % d.get("delivered"))
if d.get("surface") != "worker-result-42":
    raise SystemExit("surface %s" % d.get("surface"))
if d.get("ended") != "sent":
    raise SystemExit("ended %s" % d.get("ended"))
' || fail "dispatch must send result with no voice: ${_out}"

_en=$(run_turn "${TMP}/enact.json" "worker enact") || true
printf '%s\n' "${_en}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "cannot enact" not in err and "HI-13" not in err:
    raise SystemExit("error %s" % err)
if d.get("delivered"):
    raise SystemExit("delivered on enact")
' || fail "worker cannot enact: ${_en}"

_vo=$(run_turn "${TMP}/voice.json" "worker voice") || true
printf '%s\n' "${_vo}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "no user-visible voice" not in err:
    raise SystemExit("error %s" % err)
' || fail "worker voice must fail: ${_vo}"

_ack=$(run_turn "${TMP}/ack.json" "ack only") || true
printf '%s\n' "${_ack}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "results are sent" not in err:
    raise SystemExit("error %s" % err)
' || fail "ack-only worker must fail: ${_ack}"

_bg=$(run_turn "${TMP}/running.json" "background") || true
printf '%s\n' "${_bg}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
w = (d.get("workers") or [None])[0]
if not w or w.get("status") != "running":
    raise SystemExit("status %s" % (w or {}).get("status"))
if d.get("delivered"):
    raise SystemExit("running worker sent a result")
' || fail "running worker must not send: ${_bg}"

_ck=$(run_turn "${TMP}/check.json" "check bg") || true
printf '%s\n' "${_ck}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
w = (d.get("workers") or [None])[0]
if not w or w.get("id") != "bg":
    raise SystemExit("check %s" % w)
if w.get("status") != "running":
    raise SystemExit("status %s" % w.get("status"))
if w.get("voice"):
    raise SystemExit("check leaked voice")
if d.get("delivered"):
    raise SystemExit("check sent a voice")
' || fail "check must inspect without voice: ${_ck}"

_st=$(run_turn "${TMP}/stop.json" "stop bg") || true
printf '%s\n' "${_st}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
w = (d.get("workers") or [None])[0]
if not w or w.get("status") != "stopped":
    raise SystemExit("stop %s" % w)
' || fail "stop must halt: ${_st}"

git -C "${SRC}" init -b main >/dev/null
git -C "${SRC}" config user.name aios-work
git -C "${SRC}" config user.email aios-work@localhost
printf '%s\n' 'seed' > "${SRC}/tracked.txt"
git -C "${SRC}" add tracked.txt
git -C "${SRC}" commit -q -m "init"
MAIN_SHA=$(git -C "${SRC}" rev-parse main)

_co=$(run_turn "${TMP}/coding.json" "coding branch") || true
printf '%s\n' "${_co}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
w = (d.get("workers") or [None])[0]
if not w:
    raise SystemExit("no coding worker")
if w.get("kind") != "coding":
    raise SystemExit("kind %s" % w.get("kind"))
if w.get("voice"):
    raise SystemExit("coding voice")
mr = w.get("merge_request") or {}
if mr.get("status") != "open" or mr.get("target") != "main":
    raise SystemExit("mr %s" % mr)
if not w.get("branch") or w.get("branch") in ("main", "master"):
    raise SystemExit("branch %s" % w.get("branch"))
if d.get("delivered") != "mr-open":
    raise SystemExit("delivered %s" % d.get("delivered"))
' || fail "coding must be branch plus MR: ${_co}"

NOW_MAIN=$(git -C "${SRC}" rev-parse main)
if [ "${NOW_MAIN}" != "${MAIN_SHA}" ]; then
  fail "coding worker moved main"
fi
HEAD=$(git -C "${SRC}" rev-parse --abbrev-ref HEAD)
if [ "${HEAD}" = "main" ] || [ "${HEAD}" = "master" ]; then
  fail "coding worker left HEAD on main"
fi
git -C "${SRC}" show-ref --verify --quiet "refs/heads/${HEAD}" \
  || fail "coding branch missing"

_act=$(run_turn "${TMP}/actions.json" "actions dispatch") || true
printf '%s\n' "${_act}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if d.get("delivered") != "via-actions":
    raise SystemExit("delivered %s" % d.get("delivered"))
' || fail "actions dispatch must send: ${_act}"

env -u AIOS_WORK_SRC env -u AIOS_ROOT \
  python3 "${SRC}/main.py" turn worker >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC worker turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/workers.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed workers.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/workers.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed workers.py"
grep -Fq '/srv/aios/seeds/work-runtime/workers.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed workers.py"

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
  printf 'error: p8-worker failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-worker\n'
exit 0
