#!/bin/sh
# P7.2: HI-14 notify view. Five-name payload into OS conversation. Not a coding CLI.
# Envelope: P7.2, HI-14, L-18. Host isolate via AIOS_NOTIFY / AIOS_BRAKE.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
NOTIFY="${ROOT}/operator-client/tty/notify.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/aios"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
POLICY="${ROOT}/checker/policy/hi-14-failure-handoff.sh"
VM_NOTIFY="${ROOT}/tests/vm/oracles/vm-notify.sh"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${NOTIFY}" ] || fail "missing ${NOTIFY}"
[ -f "${ISO_OC}/tty/aios.py" ] || fail "missing ISO aios.py"
[ -f "${ISO_OC}/tty/notify.py" ] || fail "missing ISO notify.py"
[ -x "${ISO_BIN}" ] || fail "ISO bin/aios must be executable"
[ -x "${FIRSTBOOT}" ] || fail "firstboot must be executable"
[ -f "${POLICY}" ] || fail "missing HI-14 policy"
[ -f "${VM_NOTIFY}" ] || fail "missing vm-notify.sh"

grep -q 'P7.2' "${NOTIFY}" || fail "notify.py must quote P7.2"
grep -q 'HI-14' "${NOTIFY}" || fail "notify.py must quote HI-14"
grep -q 'not a coding CLI' "${NOTIFY}" || fail "notify.py must say not a coding CLI"
grep -q 'hi-14-failure-handoff.sh' "${NOTIFY}" \
  || fail "notify.py must name the HI-14 policy"
grep -Fq '("unit", "executable")' "${NOTIFY}" \
  || fail "notify.py must name unit or executable"
grep -Fq '("journal", "journal_slice")' "${NOTIFY}" \
  || fail "notify.py must name journal slice"
grep -Fq '("commit", "state_commit")' "${NOTIFY}" \
  || fail "notify.py must name state commit"
grep -Fq '("snapper", "snapper_id")' "${NOTIFY}" \
  || fail "notify.py must name snapper id"
grep -Fq '("clause",)' "${NOTIFY}" || fail "notify.py must name clause"
if grep -Eiq 'four-field|four field' "${NOTIFY}" "${MAIN}" \
  "${ISO_OC}/tty/notify.py" "${ISO_OC}/tty/aios.py"
then
  fail "must not call HI-14 four-field"
fi

grep -q 'P7.2' "${MAIN}" || fail "aios.py must quote P7.2"
grep -q 'HI-14' "${MAIN}" || fail "aios.py must quote HI-14"
grep -q 'import notify' "${MAIN}" || fail "aios.py must import notify"
grep -q 'open_handoff' "${MAIN}" || fail "aios.py must open the payload into conversation"
grep -q '"notify": ("open", "view", "brake", "mode")' "${MAIN}" \
  || fail "notify actions must include open"

grep -q 'operator-client/tty/notify.py' "${FIRSTBOOT}" \
  || fail "firstboot must name notify.py"
grep -q 'payload operator-client notify.py missing' "${FIRSTBOOT}" \
  || fail "firstboot must require notify.py"

python3 - "${MAIN}" <<'PY' || fail "notify must remain an L-18 view id"
import ast
import sys

src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
views = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            if getattr(t, "id", None) == "VIEWS":
                views = ast.literal_eval(node.value)
if views is None:
    raise SystemExit("VIEWS missing")
if "notify" not in views:
    raise SystemExit("notify missing from VIEWS (L-18)")
if "brake" in views:
    raise SystemExit("brake is a view id")
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
cp -a "${NOTIFY}" "${_pyct}/notify.py" || fail "copy notify.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" "${_pyct}/notify.py" \
  || fail "py_compile aios.py/notify.py failed"
cp -a "${ISO_OC}/tty/aios.py" "${_pyct}/iso-aios.py" \
  || fail "copy ISO aios.py for py_compile"
cp -a "${ISO_OC}/tty/notify.py" "${_pyct}/iso-notify.py" \
  || fail "copy ISO notify.py for py_compile"
python3 -m py_compile "${_pyct}/iso-aios.py" "${_pyct}/iso-notify.py" \
  || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${ISO_BIN}" || fail "sh -n bin/aios"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"
sh -n "${0}" || fail "sh -n p7-notify.sh"
sh -n "${VM_NOTIFY}" || fail "sh -n vm-notify.sh"

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
  "${ISO_OC}" \
  "${FIRSTBOOT}" 2>/dev/null
then
  fail "operator-client/firstboot contains -Syu (L-20)"
fi

if grep -REin -- 'hyprland|gnome|kwin|keybind|key.?chord|bindsym' \
  "${ROOT}/operator-client" "${ISO_BIN}" "${ISO_OC}" 2>/dev/null
then
  fail "key chord / DE bind in operator-client or bin/aios"
fi

for _unit in aios-tui.service aios-operator.service aios-notify.service; do
  if [ -e "${ROOT}/payload/profile/airootfs/etc/systemd/system/${_unit}" ]; then
    fail "new TUI systemd unit ${_unit} (no daemon)"
  fi
done

grep -E '^[0-9a-f]{64}  operator-client/tty/notify.py$' "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin operator-client/tty/notify.py"
grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/operator-client/tty/notify.py$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin ISO notify.py"
grep -Eq '^[0-9a-f]{64}  operator-client/tty/notify.py$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin operator-client/tty/notify.py"

grep -q '"unit"|"executable"' "${POLICY}" \
  || fail "HI-14 policy must grep unit or executable"
grep -q '"journal"|"journal_slice"' "${POLICY}" \
  || fail "HI-14 policy must grep journal slice"
grep -q '"commit"|"state_commit"' "${POLICY}" \
  || fail "HI-14 policy must grep state commit"
grep -q '"snapper"|"snapper_id"' "${POLICY}" \
  || fail "HI-14 policy must grep snapper id"
grep -q '"clause"' "${POLICY}" || fail "HI-14 policy must grep clause"

LIVE_NOTIFY_STATE="/srv/aios/state/notify"
LIVE_NOTIFY_RUN="/run/aios/notify"
LIVE_NOTIFY_MEM="/srv/aios/memory/notify"
LIVE_BRAKE="/srv/aios/state/brake.d/stamp"
_live_state=0
_live_run=0
_live_mem=0
_live_brake=0
[ -e "${LIVE_NOTIFY_STATE}" ] && _live_state=1
[ -e "${LIVE_NOTIFY_RUN}" ] && _live_run=1
[ -e "${LIVE_NOTIFY_MEM}" ] && _live_mem=1
[ -e "${LIVE_BRAKE}" ] && _live_brake=1

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

drive() {
  printf '%s\n' "$@" | AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_NOTIFY="${TMP}/notify" python3 -u "${MAIN}"
}

mkdir -p "${TMP}/notify" "${TMP}/empty" "${TMP}/alt" "${TMP}/skill"

_empty=$(
  printf '%s\n' 'view notify' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/empty" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_empty}" | grep -q '^view: notify$' \
  || fail "view notify must set view id: ${_empty}"
printf '%s\n' "${_empty}" | grep -q '^actions: open view brake mode$' \
  || fail "notify actions missing open: ${_empty}"
printf '%s\n' "${_empty}" | grep -q '^handoff: none$' \
  || fail "empty notify dir must show handoff none: ${_empty}"
printf '%s\n' "${_empty}" | grep -q 'not a coding CLI' \
  || fail "empty notify must say not a coding CLI: ${_empty}"
printf '%s\n' "${_empty}" | grep -q 'HI-14' \
  || fail "empty notify must quote HI-14: ${_empty}"
printf '%s\n' "${_empty}" | grep -q 'not this PR' \
  && fail "notify view still stubbed: ${_empty}" || true

_vn=$(
  printf '%s\n' 'v n' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/empty" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_vn}" | grep -q '^view: notify$' \
  || fail "v n must open notify: ${_vn}"

_n=$(
  printf '%s\n' 'n' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/empty" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_n}" | grep -q '^view: notify$' \
  || fail "n must open notify: ${_n}"

cat > "${TMP}/notify/handoff.json" <<'EOF'
{
  "unit": "aios-dummy.service",
  "executable": "aios-dummy.service",
  "journal": "since last healthy dummy-fail",
  "journal_slice": "since last healthy dummy-fail",
  "commit": "6b1f9ba50972d03bd89f7c1e8c9e243f74939e14",
  "state_commit": "6b1f9ba50972d03bd89f7c1e8c9e243f74939e14",
  "snapper": 12,
  "snapper_id": 12,
  "clause": "HI-14"
}
EOF

_show=$(drive 'view notify' 'quit') || true
printf '%s\n' "${_show}" | grep -q '^view: notify$' \
  || fail "view notify missing view id: ${_show}"
printf '%s\n' "${_show}" | grep -q '^handoff: 1$' \
  || fail "complete payload must count as handoff: ${_show}"
printf '%s\n' "${_show}" | grep -q '^unit: aios-dummy.service$' \
  || fail "notify must render unit: ${_show}"
printf '%s\n' "${_show}" | grep -q '^journal: since last healthy dummy-fail$' \
  || fail "notify must render journal: ${_show}"
printf '%s\n' "${_show}" | grep -q '^commit: 6b1f9ba50972d03bd89f7c1e8c9e243f74939e14$' \
  || fail "notify must render commit: ${_show}"
printf '%s\n' "${_show}" | grep -q '^snapper: 12$' \
  || fail "notify must render snapper: ${_show}"
printf '%s\n' "${_show}" | grep -q '^clause: HI-14$' \
  || fail "notify must render clause: ${_show}"
printf '%s\n' "${_show}" | grep -q 'not a coding CLI' \
  || fail "notify must say not a coding CLI: ${_show}"
printf '%s\n' "${_show}" | grep -q 'not this PR' \
  && fail "notify still stubbed with payload: ${_show}" || true

_open=$(drive 'view notify' 'open' 'quit') || true
printf '%s\n' "${_open}" | grep -q '^view: conversation$' \
  || fail "open must switch to conversation: ${_open}"
printf '%s\n' "${_open}" | grep -q 'opened notify into conversation (HI-14)' \
  || fail "open must note HI-14 handoff: ${_open}"
printf '%s\n' "${_open}" | grep -q 'HI-14' \
  || fail "conversation missing HI-14: ${_open}"
printf '%s\n' "${_open}" | grep -q 'unit: aios-dummy.service' \
  || fail "conversation missing unit: ${_open}"
printf '%s\n' "${_open}" | grep -q 'journal: since last healthy dummy-fail' \
  || fail "conversation missing journal: ${_open}"
printf '%s\n' "${_open}" | grep -q 'commit: 6b1f9ba50972d03bd89f7c1e8c9e243f74939e14' \
  || fail "conversation missing commit: ${_open}"
printf '%s\n' "${_open}" | grep -q 'snapper: 12' \
  || fail "conversation missing snapper: ${_open}"
printf '%s\n' "${_open}" | grep -q 'clause: HI-14' \
  || fail "conversation missing clause: ${_open}"

_chrome_open=$(drive 'open' 'quit') || true
printf '%s\n' "${_chrome_open}" | grep -q 'open is a notify action' \
  || fail "open from chrome must stay a notify action: ${_chrome_open}"
printf '%s\n' "${_chrome_open}" | grep -q '^view: conversation$' \
  && fail "open from chrome must not switch view: ${_chrome_open}" || true

cat > "${TMP}/alt/alt.json" <<'EOF'
{
  "executable": "dummy-fail",
  "journal_slice": "journal since last healthy",
  "state_commit": "statecommitabc",
  "snapper_id": 7,
  "clause": "HI-14"
}
EOF
_alt=$(
  printf '%s\n' 'view notify' 'open' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/alt" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_alt}" | grep -q '^unit: dummy-fail$' \
  || fail "alias executable must render as unit: ${_alt}"
printf '%s\n' "${_alt}" | grep -q '^journal: journal since last healthy$' \
  || fail "alias journal_slice missing: ${_alt}"
printf '%s\n' "${_alt}" | grep -q '^commit: statecommitabc$' \
  || fail "alias state_commit missing: ${_alt}"
printf '%s\n' "${_alt}" | grep -q '^snapper: 7$' \
  || fail "alias snapper_id missing: ${_alt}"
printf '%s\n' "${_alt}" | grep -q 'unit: dummy-fail' \
  || fail "open alias payload missing unit: ${_alt}"

cat > "${TMP}/skill/skill.json" <<'EOF'
{
  "unit": "aios-dummy.service",
  "journal": "slice",
  "commit": "cafebabe",
  "snapper": 3,
  "clause": "HI-14",
  "skill_path": "skills/repair.md"
}
EOF
_sk=$(
  printf '%s\n' 'view notify' 'open' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/skill" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_sk}" | grep -q '^skill: skills/repair.md$' \
  || fail "skill path must render when present: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'skill: skills/repair.md' \
  || fail "conversation missing skill path: ${_sk}"

mkdir -p "${TMP}/bad"
printf '%s\n' '{"unit":"only-unit"}' > "${TMP}/bad/incomplete.json"
_bad=$(
  printf '%s\n' 'view notify' 'open' 'quit' \
    | AIOS_BRAKE="${TMP}/unused-brake" AIOS_NOTIFY="${TMP}/bad" \
      python3 -u "${MAIN}"
) || true
printf '%s\n' "${_bad}" | grep -q '^handoff: none$' \
  || fail "incomplete payload must not be a handoff: ${_bad}"
printf '%s\n' "${_bad}" | grep -q 'no HI-14 payload' \
  || fail "open incomplete must not invent fields: ${_bad}"
printf '%s\n' "${_bad}" | grep -q '^view: conversation$' \
  && fail "open incomplete must not switch to conversation: ${_bad}" || true
printf '%s\n' "${_bad}" | grep -q 'opened notify into conversation' \
  && fail "open incomplete must not claim a handoff: ${_bad}" || true
printf '%s\n' "${_bad}" | grep -q '^unit: only-unit$' \
  && fail "incomplete unit must not render as complete: ${_bad}" || true

_iso=$(
  printf '%s\n' 'view notify' 'open' 'quit' \
    | AIOS_CLIENT="${MAIN}" AIOS_BRAKE="${TMP}/wrap-brake" \
      AIOS_NOTIFY="${TMP}/notify" "${ISO_BIN}"
) || true
printf '%s\n' "${_iso}" | grep -q '^view: conversation$' \
  || fail "ISO bin/aios open must reach conversation: ${_iso}"
printf '%s\n' "${_iso}" | grep -q 'unit: aios-dummy.service' \
  || fail "ISO bin/aios missing unit in conversation: ${_iso}"

if [ "${_live_state}" -eq 0 ] && [ -e "${LIVE_NOTIFY_STATE}" ]; then
  fail "oracle created ${LIVE_NOTIFY_STATE}"
fi
if [ "${_live_run}" -eq 0 ] && [ -e "${LIVE_NOTIFY_RUN}" ]; then
  fail "oracle created ${LIVE_NOTIFY_RUN}"
fi
if [ "${_live_mem}" -eq 0 ] && [ -e "${LIVE_NOTIFY_MEM}" ]; then
  fail "oracle created ${LIVE_NOTIFY_MEM}"
fi
if [ "${_live_brake}" -eq 0 ] && [ -e "${LIVE_BRAKE}" ]; then
  rm -f "${LIVE_BRAKE}"
  fail "oracle created ${LIVE_BRAKE}"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-notify failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-notify\n'
exit 0
