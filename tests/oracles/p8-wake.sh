#!/bin/sh
# P8.4: wake inject order, explicit send, question ends the turn.
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
LIVE_WANTS_BEFORE=0
if [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
  LIVE_WANTS_BEFORE=1
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

[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${SEED}/wake.py" ] || fail "missing seed/work-runtime/wake.py"
[ -f "${SEED}/skills.py" ] || fail "missing seed/work-runtime/skills.py"
[ -f "${SEED}/provider.py" ] || fail "missing seed/work-runtime/provider.py"
[ -f "${ISO_SEED}/main.py" ] || fail "missing ISO seed main.py"
[ -f "${ISO_SEED}/wake.py" ] || fail "missing ISO seed wake.py"
[ -f "${ISO_SEED}/skills.py" ] || fail "missing ISO seed skills.py"
[ -f "${ISO_SEED}/provider.py" ] || fail "missing ISO seed provider.py"

diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'time.sleep(POLL_S)' "${SEED}/main.py" \
  || fail "no-arg serve() must idle"
grep -q 'AIOS_WORK_SRC' "${SEED}/main.py" \
  || fail "main.py must honour AIOS_WORK_SRC"
grep -q 'Plain model text is not delivered' "${SEED}/main.py" \
  || fail "main.py must keep undelivered plain text off the surface"
grep -q 'following a skill without reading its body this turn fails' \
  "${SEED}/main.py" \
  || fail "main.py missing skill-follow refusal"
grep -q '"AGENTS.md"' "${SEED}/wake.py" \
  || fail "wake.py must name AGENTS.md in INJECTS"
grep -q 'INJECTS' "${SEED}/wake.py" || fail "wake.py missing INJECTS"
grep -q 'work-runtime enabled:' "${SEED}/wake.py" \
  || fail "wake.py must inject the envelope bit"
grep -q 'HI-15' "${SEED}/wake.py" || fail "wake.py must quote HI-15"
grep -q 'L-16' "${SEED}/provider.py" || fail "provider.py must quote L-16"
grep -q 'do not call live Grok' "${SEED}/provider.py" \
  || fail "provider.py must refuse live Grok"
grep -qx 'OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"' \
  "${SEED}/provider.py" \
  || fail "provider.py OS token path lock drifted"
if grep -nE '^(import|from)[[:space:]]+(urllib|aios_agent|http\.client)\b' \
  "${SEED}/main.py" "${SEED}/wake.py" "${SEED}/skills.py" "${SEED}/provider.py" \
  >/dev/null; then
  fail "work runtime must not import urllib/aios_agent/http.client"
fi
if grep -nE 'github\.com|auth\.x\.ai' \
  "${SEED}/main.py" "${SEED}/wake.py" "${SEED}/skills.py" "${SEED}/provider.py" \
  >/dev/null; then
  fail "work runtime must not call live Grok"
fi
if grep -q -- '-Syu' "${SEED}/main.py" "${SEED}/wake.py"; then
  fail "work runtime contains -Syu (L-20)"
fi

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}/seed" "${_pyct}/iso"
cp -a "${SEED}/main.py" "${SEED}/wake.py" "${SEED}/skills.py" \
  "${SEED}/provider.py" "${_pyct}/seed/"
cp -a "${ISO_SEED}/main.py" "${ISO_SEED}/wake.py" \
  "${ISO_SEED}/skills.py" "${ISO_SEED}/provider.py" "${_pyct}/iso/"
python3 -m py_compile \
  "${_pyct}/seed/main.py" "${_pyct}/seed/wake.py" \
  "${_pyct}/seed/skills.py" "${_pyct}/seed/provider.py" \
  || fail "py_compile seed work-runtime failed"
python3 -m py_compile \
  "${_pyct}/iso/main.py" "${_pyct}/iso/wake.py" \
  "${_pyct}/iso/skills.py" "${_pyct}/iso/provider.py" \
  || fail "py_compile ISO seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-wake.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/notes"
printf '%s\n' 'verbatim job note: widget-alpha' > "${SRC}/notes/job.md"
printf '%s\n' '{"accepted":true,"work_runtime":true,"vetoes":{"remotes":true}}' \
  > "${TMP}/answers.json"
printf '%s\n' '{"responses":[{"send":"visible-reply"}]}' > "${TMP}/send.json"
printf '%s\n' '{"responses":["plain-undelivered-text"]}' > "${TMP}/plain.json"
printf '%s\n' '{"responses":[{"actions":[{"tool":"question","text":"which-one?"},{"tool":"send","text":"too-late"}]}]}' \
  > "${TMP}/question.json"
printf '%s\n' '{"responses":["idle"]}' > "${TMP}/idlefix.json"

run_turn() {
  _fix=$1
  shift
  AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${_fix}" \
    python3 "${SRC}/main.py" turn "$@"
}

_idle=$(
  AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${TMP}/idlefix.json" \
    python3 "${SRC}/main.py" turn
) || true
printf '%s\n' "${_idle}" | grep -q '"outcome": "idle"' \
  || fail "empty turn must idle: ${_idle}"
printf '%s\n' "${_idle}" | grep -q '"delivered": ""' \
  || fail "empty turn must not deliver: ${_idle}"
printf '%s\n' "${_idle}" | grep -q '"prompt": ""' \
  || fail "empty turn must not inject a completed plan: ${_idle}"

_out=$(run_turn "${TMP}/send.json" "widget-alpha job") || true
printf '%s\n' "${_out}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
want = ["AGENTS.md", "skills catalog", "tools", "operational notes", "envelope bit"]
if d.get("injects") != want:
    raise SystemExit("injects %s" % d.get("injects"))
p = d.get("prompt") or ""
marks = [
    "[inject 1] AGENTS.md",
    "[inject 2] skills catalog",
    "[inject 3] tools",
    "[inject 4] operational notes",
    "[inject 5] envelope bit",
]
pos = [-1]
for m in marks:
    i = p.find(m)
    if i < 0:
        raise SystemExit("missing %s" % m)
    if i <= pos[-1]:
        raise SystemExit("order %s" % m)
    pos.append(i)
if "Contract for any agent working on the work runtime" not in p:
    raise SystemExit("AGENTS.md body missing")
if "- wake:" not in p:
    raise SystemExit("skills catalog missing wake")
if "Delivery is an explicit send" not in p:
    raise SystemExit("tools/interfaces missing")
if "verbatim job note: widget-alpha" not in p:
    raise SystemExit("operational notes missing verbatim excerpt")
if "work-runtime enabled: yes" not in p:
    raise SystemExit("envelope bit missing enabled yes")
if "vetoes.remotes: yes" not in p:
    raise SystemExit("envelope bit missing remotes veto")
if "You are the AIOS privileged proposer" in p:
    raise SystemExit("OS-agent privilege injected")
if d.get("delivered") != "visible-reply":
    raise SystemExit("delivered %s" % d.get("delivered"))
if d.get("surface") != "visible-reply":
    raise SystemExit("surface %s" % d.get("surface"))
' || fail "wake inject/send failed: ${_out}"

_plain=$(run_turn "${TMP}/plain.json" "plain job") || true
printf '%s\n' "${_plain}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "plain-undelivered-text" not in (d.get("model_text") or ""):
    raise SystemExit("model_text missing plain text")
if d.get("delivered"):
    raise SystemExit("plain text was delivered")
if "plain-undelivered-text" in (d.get("surface") or ""):
    raise SystemExit("plain text on definition surface")
if d.get("ended") != "idle":
    raise SystemExit("ended %s" % d.get("ended"))
' || fail "explicit send failed: ${_plain}"

_q=$(run_turn "${TMP}/question.json" "choose") || true
printf '%s\n' "${_q}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("question") != "which-one?":
    raise SystemExit("question %s" % d.get("question"))
if d.get("ended") != "question":
    raise SystemExit("ended %s" % d.get("ended"))
if d.get("outcome") != "wait":
    raise SystemExit("outcome %s" % d.get("outcome"))
if d.get("delivered"):
    raise SystemExit("send after question was delivered")
' || fail "question must end the turn: ${_q}"

_live=$(
  AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_PROVIDER=live \
    AIOS_FIXTURE="${TMP}/send.json" \
    python3 "${SRC}/main.py" turn ping 2>/dev/null || true
)
printf '%s\n' "${_live}" | grep -q 'live Grok' \
  || fail "live provider must be refused: ${_live}"

_tok=$(
  AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    python3 - "${SRC}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from provider import OS_TOKEN_PATH, ProviderError, refuse_os_token
print(OS_TOKEN_PATH)
try:
    refuse_os_token()
except ProviderError as exc:
    print(exc)
    sys.exit(0)
raise SystemExit("os token was readable")
PY
) || fail "OS token probe failed"
printf '%s\n' "${_tok}" | grep -qx '/srv/aios/state/provider/os.token' \
  || fail "OS token path drifted: ${_tok}"
printf '%s\n' "${_tok}" | grep -q 'L-16' \
  || fail "OS token refusal missing L-16: ${_tok}"

mkdir -p "${TMP}/empty"
_empty=$(
  AIOS_WORK_SRC= \
    AIOS_ROOT="${TMP}/empty" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${TMP}/send.json" \
    python3 "${SRC}/main.py" turn ping 2>/dev/null || true
)
printf '%s\n' "${_empty}" | grep -q 'AIOS_WORK_SRC empty' \
  || fail "empty AIOS_WORK_SRC must fail closed: ${_empty}"

env -u AIOS_WORK_SRC env -u AIOS_ROOT env -u AIOS_ANSWERS env -u AIOS_FIXTURE \
  python3 "${SRC}/main.py" turn ping >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/main.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed main.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/main.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed main.py"
grep -Fq '/srv/aios/seeds/work-runtime/main.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed main.py"
grep -Fq 'seed/work-runtime/wake.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed wake.py"
grep -Fq '/srv/aios/seeds/work-runtime/wake.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed wake.py"

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
if [ "${LIVE_WANTS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
  fail "oracle wrote live user-unit wants"
fi
if [ "${LIVE_SYS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  fail "oracle wrote live system aios-work-runtime.service"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-wake failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-wake\n'
exit 0
