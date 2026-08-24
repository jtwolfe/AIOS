#!/bin/sh
# P7.4: OS vs work summon split. L-14. HI-15 refuse when bit off.
# Envelope: P7.4, L-14, L-18, HI-15, L-09, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/aios"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${ISO_OC}/tty/aios.py" ] || fail "missing ISO operator-client aios.py"
[ -x "${ISO_BIN}" ] || fail "ISO bin/aios must be executable"

grep -q 'P7.4' "${MAIN}" || fail "aios.py must quote P7.4"
grep -q 'L-14' "${MAIN}" || fail "aios.py must quote L-14"
grep -q 'HI-15' "${MAIN}" || fail "aios.py must quote HI-15"
grep -q 'L-18' "${MAIN}" || fail "aios.py must quote L-18"
grep -q 'WORK_CATALOG' "${MAIN}" || fail "aios.py missing WORK_CATALOG"
grep -q 'work_runtime_on' "${MAIN}" || fail "aios.py missing work_runtime_on"
grep -q 'AIOS_ANSWERS' "${MAIN}" || fail "aios.py must read AIOS_ANSWERS"
grep -q 'bootstrap-in-progress/answers.json' "${MAIN}" \
  || fail "aios.py must read bootstrap-in-progress/answers.json"

if grep -n -E 'systemctl|Slice=' \
  "${MAIN}" "${ISO_OC}/tty/aios.py" "${ISO_BIN}" 2>/dev/null
then
  fail "operator-client must not set a systemd slice on itself (L-14)"
fi

python3 - "${MAIN}" <<'PY' || fail "VIEWS must stay the OS catalog (L-18)"
import ast
import sys

src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
views = None
work = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            name = getattr(t, "id", None)
            if name == "VIEWS":
                views = ast.literal_eval(node.value)
            elif name == "WORK_CATALOG":
                work = ast.literal_eval(node.value)
if views is None:
    raise SystemExit("VIEWS missing")
if work is None:
    raise SystemExit("WORK_CATALOG missing")
if "brake" in views or "brake" in work:
    raise SystemExit("brake is a view id (L-18)")
for need in ("chrome", "conversation", "envelope", "packages", "snapper", "login"):
    if need not in views:
        raise SystemExit("OS catalog missing %s" % need)
for need in ("chrome", "conversation", "skills", "connectors", "bridge", "store"):
    if need not in work:
        raise SystemExit("work catalog missing %s" % need)
for forbidden in ("envelope", "packages", "snapper", "intents", "notify", "accept", "enact"):
    if forbidden in work:
        raise SystemExit("work catalog has OS tool %s" % forbidden)
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" || fail "py_compile aios.py failed"
cp -a "${ISO_OC}/tty/aios.py" "${_pyct}/iso-aios.py" \
  || fail "copy ISO aios.py for py_compile"
python3 -m py_compile "${_pyct}/iso-aios.py" || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${ISO_BIN}" || fail "sh -n bin/aios"
sh -n "${0}" || fail "sh -n p7-surface-split.sh"

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  cmp -s "${ROOT}/operator-client/${rel}" "${ISO_OC}/${rel}" \
    || fail "ISO operator-client ${rel} bytes differ"
done <<EOF
$(cd "${ROOT}/operator-client" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  [ -f "${ROOT}/operator-client/${rel}" ] \
    || fail "ISO extra file ${rel} not in operator-client source"
done <<EOF
$(cd "${ISO_OC}" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF

if grep -R -q -- '-Syu' \
  "${ROOT}/operator-client" \
  "${ISO_BIN}" \
  "${ISO_OC}" 2>/dev/null
then
  fail "operator-client contains -Syu (L-20)"
fi

if grep -REin -- 'hyprland|gnome|kwin|keybind|key.?chord|bindsym' \
  "${ROOT}/operator-client" "${ISO_BIN}" "${ISO_OC}" 2>/dev/null
then
  fail "key chord / DE bind in operator-client or bin/aios"
fi

grep -E '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin operator-client/tty/aios.py"
grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/operator-client/tty/aios.py$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin ISO operator-client aios.py"
grep -Eq '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin operator-client/tty/aios.py"

TMP=$(mktemp -d)
WR_BEFORE=0
[ -e /srv/aios/src ] && WR_BEFORE=1
LIVE_ANS="/srv/aios/state/bootstrap-in-progress/answers.json"
LIVE_BRAKE="/srv/aios/state/brake.d/stamp"
_live_ans=0
_live_brake=0
[ -e "${LIVE_ANS}" ] && _live_ans=1
[ -e "${LIVE_BRAKE}" ] && _live_brake=1

cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

drive() {
  printf '%s\n' "$@" | AIOS_BRAKE="${TMP}/unused-brake" python3 -u "${MAIN}"
}

drive_ans() {
  _ans=$1
  shift
  printf '%s\n' "$@" | AIOS_ANSWERS="${_ans}" AIOS_BRAKE="${TMP}/unused-brake" \
    python3 -u "${MAIN}"
}

drive_work() {
  _ans=$1
  shift
  printf '%s\n' "$@" | AIOS_ANSWERS="${_ans}" AIOS_BRAKE="${TMP}/unused-brake" \
    python3 -u "${MAIN}" work
}

# Bit off (no answers, missing file, false, 1, "true"): refuse HI-15.
_work=$(AIOS_BRAKE="${TMP}/unused-brake" python3 -u "${MAIN}" work) && _wrc=0 || _wrc=$?
[ "${_wrc}" != 0 ] || fail "aios work must be refused with bit off: ${_work}"
printf '%s\n' "${_work}" | grep -q 'HI-15' \
  || fail "aios work must quote HI-15: ${_work}"
printf '%s\n' "${_work}" | grep -q '^mode: work$' \
  && fail "aios work opened a work session with bit off: ${_work}" || true
printf '%s\n' "${_work}" | grep -q 'view: chrome' \
  && fail "aios work must not open the TUI with bit off: ${_work}" || true

printf '%s\n' '{"work_runtime": false}' > "${TMP}/off.json"
_off=$(AIOS_ANSWERS="${TMP}/off.json" AIOS_BRAKE="${TMP}/unused-brake" \
  python3 -u "${MAIN}" work) && _offrc=0 || _offrc=$?
[ "${_offrc}" != 0 ] || fail "work_runtime false must refuse: ${_off}"
printf '%s\n' "${_off}" | grep -q 'HI-15' || fail "false must quote HI-15: ${_off}"

printf '%s\n' '{"work_runtime": 1}' > "${TMP}/one.json"
_one=$(AIOS_ANSWERS="${TMP}/one.json" AIOS_BRAKE="${TMP}/unused-brake" \
  python3 -u "${MAIN}" work) && _onerc=0 || _onerc=$?
[ "${_onerc}" != 0 ] || fail "work_runtime 1 must refuse: ${_one}"
printf '%s\n' "${_one}" | grep -q 'HI-15' || fail "1 must quote HI-15: ${_one}"

printf '%s\n' '{"work_runtime": "true"}' > "${TMP}/str.json"
_str=$(AIOS_ANSWERS="${TMP}/str.json" AIOS_BRAKE="${TMP}/unused-brake" \
  python3 -u "${MAIN}" work) && _strrc=0 || _strrc=$?
[ "${_strrc}" != 0 ] || fail 'work_runtime "true" must refuse: '"${_str}"
printf '%s\n' "${_str}" | grep -q 'HI-15' || fail '"true" must quote HI-15: '"${_str}"

_mw=$(drive 'mode work' 'quit') || true
printf '%s\n' "${_mw}" | grep -q 'HI-15' \
  || fail "mode work with bit off must quote HI-15: ${_mw}"
printf '%s\n' "${_mw}" | grep -q '^mode: os$' \
  || fail "mode work with bit off must stay os: ${_mw}"
printf '%s\n' "${_mw}" | grep -q '^mode: work$' \
  && fail "mode work with bit off switched surface: ${_mw}" || true

# Bit on via isolated temp answers.json: work chrome, no privileged tools.
printf '%s\n' '{"work_runtime": true}' > "${TMP}/on.json"
_won=$(
  printf 'quit\n' | AIOS_ANSWERS="${TMP}/on.json" AIOS_BRAKE="${TMP}/unused-brake" \
    python3 -u "${MAIN}" work
) && _wonrc=0 || _wonrc=$?
[ "${_wonrc}" = 0 ] || fail "aios work with explicit yes must open: ${_won}"
printf '%s\n' "${_won}" | grep -q '^mode: work$' \
  || fail "aios work with yes must be mode work: ${_won}"
printf '%s\n' "${_won}" | grep -q '^view: chrome$' \
  || fail "aios work with yes must open chrome: ${_won}"
printf '%s\n' "${_won}" | grep -q '^surface: work$' \
  || fail "aios work chrome must name surface work: ${_won}"
printf '%s\n' "${_won}" | grep -q '^catalog: chrome conversation skills connectors bridge store$' \
  || fail "work catalog mismatch: ${_won}"
printf '%s\n' "${_won}" | grep -q '^work-views:' \
  || fail "work chrome must list work-views: ${_won}"
printf '%s\n' "${_won}" | grep -q 'L-14' \
  || fail "work chrome must quote L-14: ${_won}"
printf '%s\n' "${_won}" | grep -q '^os-views:' \
  && fail "work session listed os-views: ${_won}" || true
for _bad in envelope packages snapper intents notify accept enact rollback; do
  printf '%s\n' "${_won}" | grep -q "^catalog:.* ${_bad}" \
    && fail "work catalog exposes ${_bad}: ${_won}" || true
done
printf '%s\n' "${_won}" | grep -q 'os.token' \
  && fail "work session names os.token: ${_won}" || true
printf '%s\n' "${_won}" | grep -q '/srv/aios/src/work-runtime' \
  && fail "work session names synthesis path: ${_won}" || true

_priv=$(drive_work "${TMP}/on.json" \
  'view packages' 'view snapper' 'view envelope' 'view accept' \
  'enact' 'rollback' 'quit') || true
printf '%s\n' "${_priv}" | grep -q '^mode: work$' \
  || fail "privileged probes must stay work: ${_priv}"
printf '%s\n' "${_priv}" | grep -q '^view: packages$' \
  && fail "work session opened packages: ${_priv}" || true
printf '%s\n' "${_priv}" | grep -q '^view: snapper$' \
  && fail "work session opened snapper: ${_priv}" || true
printf '%s\n' "${_priv}" | grep -q '^view: envelope$' \
  && fail "work session opened envelope: ${_priv}" || true
printf '%s\n' "${_priv}" | grep -q '^view: accept$' \
  && fail "work session opened accept: ${_priv}" || true
printf '%s\n' "${_priv}" | grep -q 'L-14' \
  || fail "privileged probes must quote L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'packages refused in work session (L-14)' \
  || fail "packages must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'snapper refused in work session (L-14)' \
  || fail "snapper must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'envelope refused in work session (L-14)' \
  || fail "envelope must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'enact refused in work session (L-14)' \
  || fail "enact must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'rollback refused in work session (L-14)' \
  || fail "rollback must be refused L-14: ${_priv}"

_wview=$(drive_work "${TMP}/on.json" 'view skills' 'view connectors' \
  'view bridge' 'view store' 'quit') || true
printf '%s\n' "${_wview}" | grep -q '^view: store$' \
  || fail "work views must be reachable: ${_wview}"
printf '%s\n' "${_wview}" | grep -q '^surface: work$' \
  || fail "work stubs must be labeled work: ${_wview}"
printf '%s\n' "${_wview}" | grep -q 'work stub' \
  || fail "work stubs must say work stub: ${_wview}"

# OS session still has brake and envelope inspect.
_os=$(drive_ans "${TMP}/on.json" 'view envelope' 'quit') || true
printf '%s\n' "${_os}" | grep -q '^mode: os$' \
  || fail "aios with bit on must stay os until switched: ${_os}"
printf '%s\n' "${_os}" | grep -q '^view: envelope$' \
  || fail "OS session must reach envelope inspect: ${_os}"
printf '%s\n' "${_os}" | grep -q '^catalog:.* envelope' \
  || fail "OS catalog must include envelope: ${_os}"
printf '%s\n' "${_os}" | grep -q '^os-views:' \
  || fail "OS chrome must list os-views: ${_os}"
printf '%s\n' "${_os}" | grep -q 'inspect' \
  || fail "OS envelope must offer inspect: ${_os}"

_br=$(
  AIOS_ANSWERS="${TMP}/on.json" AIOS_BRAKE="${TMP}/os-brake" python3 -u "${MAIN}" <<'EOF'
brake
view chrome
quit
EOF
) || true
[ -f "${TMP}/os-brake" ] || fail "OS brake must write AIOS_BRAKE"
printf '%s\n' "${_br}" | grep -q '^brake: on$' \
  || fail "OS session must still brake: ${_br}"
printf '%s\n' "${_br}" | grep -q 'L-12' \
  || fail "OS brake must quote L-12: ${_br}"

# Session switch is allowed; mixing tools in one session is a fail.
_sw=$(drive_ans "${TMP}/on.json" 'mode work' 'view packages' 'mode os' \
  'view skills' 'view envelope' 'quit') || true
printf '%s\n' "${_sw}" | grep -q 'packages refused in work session (L-14)' \
  || fail "mode work then packages must L-14: ${_sw}"
printf '%s\n' "${_sw}" | grep -q 'skills refused in os session (L-14)' \
  || fail "mode os then skills must L-14: ${_sw}"
printf '%s\n' "${_sw}" | grep -q '^view: envelope$' \
  || fail "after mode os, envelope inspect must work: ${_sw}"

_fromw=$(
  printf '%s\n' 'mode os' 'quit' \
    | AIOS_ANSWERS="${TMP}/on.json" AIOS_BRAKE="${TMP}/unused-brake" \
      python3 -u "${MAIN}" work
) || true
printf '%s\n' "${_fromw}" | grep -q '^mode: os$' \
  || fail "mode os from work must switch: ${_fromw}"
printf '%s\n' "${_fromw}" | grep -q '^os-views:' \
  || fail "mode os from work must show os catalog: ${_fromw}"

_ww=$(
  AIOS_CLIENT="${MAIN}" AIOS_ANSWERS="${TMP}/on.json" \
    AIOS_BRAKE="${TMP}/wrap-unused" "${ISO_BIN}" work <<'EOF'
quit
EOF
) && _wwrc=0 || _wwrc=$?
[ "${_wwrc}" = 0 ] || fail "ISO bin/aios work with yes must open: ${_ww}"
printf '%s\n' "${_ww}" | grep -q '^mode: work$' \
  || fail "ISO bin/aios work with yes must be mode work: ${_ww}"

_wwoff=$(AIOS_CLIENT="${MAIN}" AIOS_ANSWERS="${TMP}/off.json" \
  AIOS_BRAKE="${TMP}/wrap-unused" "${ISO_BIN}" work) && _wwoffrc=0 || _wwoffrc=$?
[ "${_wwoffrc}" != 0 ] || fail "ISO bin/aios work with bit off must refuse: ${_wwoff}"
printf '%s\n' "${_wwoff}" | grep -q 'HI-15' \
  || fail "ISO bin/aios work with bit off must quote HI-15: ${_wwoff}"

if [ -e /srv/aios/src/work-runtime ]; then
  [ "${WR_BEFORE}" -eq 1 ] || fail "created /srv/aios/src/work-runtime (no P8)"
fi
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15; no P8 synthesis)"
fi
if [ "${_live_ans}" -eq 0 ] && [ -e "${LIVE_ANS}" ]; then
  rm -f "${LIVE_ANS}"
  fail "oracle created ${LIVE_ANS}"
fi
if [ "${_live_brake}" -eq 0 ] && [ -e "${LIVE_BRAKE}" ]; then
  rm -f "${LIVE_BRAKE}"
  fail "oracle created ${LIVE_BRAKE}"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-surface-split failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-surface-split\n'
exit 0
