#!/bin/sh
# P8.15: L-18 work catalog. Keyboard-complete. HI-15 refuse when bit off.
# Envelope: P8.15, P7.4, L-18, L-14, HI-15, L-09, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/aios"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
SEED_SKILLS="${ROOT}/seed/work-runtime/skills"
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
[ -d "${SEED_SKILLS}" ] || fail "missing seed work-runtime skills"

grep -q 'P8.15' "${MAIN}" || fail "aios.py must quote P8.15"
grep -q 'P7.4' "${MAIN}" || fail "aios.py must quote P7.4"
grep -q 'L-14' "${MAIN}" || fail "aios.py must quote L-14"
grep -q 'L-18' "${MAIN}" || fail "aios.py must quote L-18"
grep -q 'HI-15' "${MAIN}" || fail "aios.py must quote HI-15"
grep -q 'WORK_CATALOG' "${MAIN}" || fail "aios.py missing WORK_CATALOG"
grep -q 'work_runtime_on' "${MAIN}" || fail "aios.py missing work_runtime_on"
grep -q 'AIOS_ANSWERS' "${MAIN}" || fail "aios.py must read AIOS_ANSWERS"
grep -q 'AIOS_WORK_SRC' "${MAIN}" || fail "aios.py must read AIOS_WORK_SRC"
grep -q 'AIOS_ENVELOPE_WORK' "${MAIN}" || fail "aios.py must name AIOS_ENVELOPE_WORK"
grep -q 'bots view refused' "${MAIN}" || fail "aios.py must refuse roster/job (HI-15)"
grep -q '_WORK_PRIVILEGED' "${MAIN}" || fail "aios.py missing _WORK_PRIVILEGED"
grep -q 'sidebar:' "${MAIN}" || fail "aios.py missing sidebar structure"
grep -q 'read the skill body this turn' "${MAIN}" \
  || fail "skills follow must require reading the body this turn"

if grep -n -E 'systemctl|Slice=' \
  "${MAIN}" "${ISO_OC}/tty/aios.py" "${ISO_BIN}" 2>/dev/null
then
  fail "operator-client must not set a systemd slice on itself (L-14)"
fi

python3 - "${MAIN}" <<'PY' || fail "WORK_CATALOG drifted (L-18)"
import ast
import sys

src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
work = None
views = None
bots = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            name = getattr(t, "id", None)
            if name == "WORK_CATALOG":
                work = ast.literal_eval(node.value)
            elif name == "VIEWS":
                views = ast.literal_eval(node.value)
            elif name == "BOTS_VIEWS":
                bots = ast.literal_eval(node.value)
if work is None:
    raise SystemExit("WORK_CATALOG missing")
need = (
    "chrome",
    "conversation",
    "skills",
    "connectors",
    "bridge",
    "store",
    "login",
)
if tuple(work) != need:
    raise SystemExit("WORK_CATALOG %s" % (work,))
if "brake" in work:
    raise SystemExit("brake is a view id")
if "roster" in work or "job" in work:
    raise SystemExit("bots views in WORK_CATALOG")
if bots is not None and tuple(bots) != ("roster", "job"):
    raise SystemExit("BOTS_VIEWS %s" % (bots,))
for forbidden in ("envelope", "packages", "snapper", "intents", "notify", "accept", "enact"):
    if forbidden in work:
        raise SystemExit("work catalog has OS tool %s" % forbidden)
if views is None:
    raise SystemExit("VIEWS missing")
if "login" not in views:
    raise SystemExit("OS catalog missing login")
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" || fail "py_compile aios.py failed"
cp -a "${ISO_OC}/tty/aios.py" "${_pyct}/iso-aios.py" \
  || fail "copy ISO aios.py for py_compile"
python3 -m py_compile "${_pyct}/iso-aios.py" || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${ISO_BIN}" || fail "sh -n bin/aios"
sh -n "${0}" || fail "sh -n p8-work-views.sh"

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  cmp -s "${ROOT}/operator-client/${rel}" "${ISO_OC}/${rel}" \
    || fail "ISO operator-client ${rel} bytes differ"
done <<EOF
$(cd "${ROOT}/operator-client" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
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
LIVE_TOKEN="/srv/aios/state/provider/os.token"
LIVE_LOGIN_REQ="/run/aios/login-request"
_live_ans=0
_live_brake=0
_live_token=0
_live_login=0
[ -e "${LIVE_ANS}" ] && _live_ans=1
[ -e "${LIVE_BRAKE}" ] && _live_brake=1
[ -e "${LIVE_TOKEN}" ] && _live_token=1
[ -e "${LIVE_LOGIN_REQ}" ] && _live_login=1

cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

mkdir -p \
  "${TMP}/root/etc/aios" \
  "${TMP}/root/run/aios" \
  "${TMP}/work-src/skills" \
  "${TMP}/work-src/notes" \
  "${TMP}/work-src/routines" \
  "${TMP}/work-src/connectors" \
  "${TMP}/work-src/bridge" \
  "${TMP}/notify-empty"
cp -a "${SEED_SKILLS}/." "${TMP}/work-src/skills/" \
  || fail "copy seed skills into isolated work src"
printf '%s\n' '{"work_runtime": false}' > "${TMP}/off.json"
printf '%s\n' '{"work_runtime": true}' > "${TMP}/on.json"
printf '%s\n' 'a note' > "${TMP}/work-src/notes/hello.md"

drive_off() {
  printf '%s\n' "$@" | \
    AIOS_ANSWERS="${TMP}/off.json" \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    AIOS_ENVELOPE_WORK="${TMP}/missing-envelope.md" \
    AIOS_NOTIFY="${TMP}/notify-empty" \
    python3 -u "${MAIN}"
}

drive_work() {
  printf '%s\n' "$@" | \
    AIOS_ANSWERS="${TMP}/on.json" \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    AIOS_SKILLS="${TMP}/work-src/skills" \
    AIOS_ENVELOPE_WORK="${TMP}/missing-envelope.md" \
    AIOS_NOTIFY="${TMP}/notify-empty" \
    python3 -u "${MAIN}" work
}

# Bit off: summon and work views refused (HI-15).
_work=$(AIOS_ANSWERS="${TMP}/off.json" \
  AIOS_BRAKE="${TMP}/unused-brake" \
  AIOS_ROOT="${TMP}/root" \
  AIOS_WORK_SRC="${TMP}/work-src" \
  AIOS_ENVELOPE_WORK="${TMP}/missing-envelope.md" \
  python3 -u "${MAIN}" work) && _wrc=0 || _wrc=$?
[ "${_wrc}" != 0 ] || fail "aios work must be refused with bit off: ${_work}"
printf '%s\n' "${_work}" | grep -q 'HI-15' \
  || fail "aios work must quote HI-15: ${_work}"
printf '%s\n' "${_work}" | grep -q '^mode: work$' \
  && fail "aios work opened a work session with bit off: ${_work}" || true

_oskill=$(drive_off 'view skills' 'quit') || true
printf '%s\n' "${_oskill}" | grep -q 'work view refused (HI-15)' \
  || fail "skills with bit off must quote HI-15: ${_oskill}"
printf '%s\n' "${_oskill}" | grep -q '^view: skills$' \
  && fail "skills opened with bit off: ${_oskill}" || true

_mw=$(drive_off 'mode work' 'quit') || true
printf '%s\n' "${_mw}" | grep -q 'HI-15' \
  || fail "mode work with bit off must quote HI-15: ${_mw}"
printf '%s\n' "${_mw}" | grep -q '^mode: os$' \
  || fail "mode work with bit off must stay os: ${_mw}"

# Bit on: work catalog, keyboard paths, no privileged tools.
_won=$(drive_work 'quit') && _wonrc=0 || _wonrc=$?
[ "${_wonrc}" = 0 ] || fail "aios work with explicit yes must open: ${_won}"
printf '%s\n' "${_won}" | grep -q '^mode: work$' \
  || fail "aios work with yes must be mode work: ${_won}"
printf '%s\n' "${_won}" | grep -q '^view: chrome$' \
  || fail "aios work with yes must open chrome: ${_won}"
printf '%s\n' "${_won}" | grep -q '^catalog: chrome conversation skills connectors bridge store login$' \
  || fail "work catalog mismatch: ${_won}"
printf '%s\n' "${_won}" | grep -q '^sidebar:' \
  || fail "work chrome missing sidebar: ${_won}"
printf '%s\n' "${_won}" | grep -q 'P8.15' \
  || fail "work chrome must quote P8.15: ${_won}"
printf '%s\n' "${_won}" | grep -q 'L-14' \
  || fail "work chrome must quote L-14: ${_won}"
printf '%s\n' "${_won}" | grep -q '^os-views:' \
  && fail "work session listed os-views: ${_won}" || true

_keys=$(drive_work 'h' 'c' 's' 'n' 'g' 't' 'l' 'quit') || true
printf '%s\n' "${_keys}" | grep -q '^view: chrome$' \
  || fail "letter h missing chrome: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: conversation$' \
  || fail "letter c missing conversation: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: skills$' \
  || fail "letter s missing skills: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: connectors$' \
  || fail "letter n missing connectors: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: bridge$' \
  || fail "letter g missing bridge: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: store$' \
  || fail "letter t missing store: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: login$' \
  || fail "letter l missing login: ${_keys}"

_vs=$(drive_work 'v s' 'quit') || true
printf '%s\n' "${_vs}" | grep -q '^view: skills$' \
  || fail "v s must open skills: ${_vs}"
_vn=$(drive_work 'v n' 'quit') || true
printf '%s\n' "${_vn}" | grep -q '^view: connectors$' \
  || fail "v n must open connectors: ${_vn}"
_vg=$(drive_work 'v g' 'quit') || true
printf '%s\n' "${_vg}" | grep -q '^view: bridge$' \
  || fail "v g must open bridge: ${_vg}"
_vt=$(drive_work 'v t' 'quit') || true
printf '%s\n' "${_vt}" | grep -q '^view: store$' \
  || fail "v t must open store: ${_vt}"
_vl=$(drive_work 'v l' 'quit') || true
printf '%s\n' "${_vl}" | grep -q '^view: login$' \
  || fail "v l must open login: ${_vl}"

_sk=$(drive_work 'view skills' 'inspect' 'open wake' 'follow wake' 'quit') || true
printf '%s\n' "${_sk}" | grep -q '^view: skills$' \
  || fail "skills view missing: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'actions: open follow inspect view brake mode' \
  || fail "skills actions missing: ${_sk}"
printf '%s\n' "${_sk}" | grep -q '  wake' \
  || fail "skills catalog missing wake: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'note: open: wake (read this turn)' \
  || fail "open wake missing: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'note: follow: wake' \
  || fail "follow wake missing: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'note: inspect: skills' \
  || fail "skills inspect missing: ${_sk}"
printf '%s\n' "${_sk}" | grep -q 'Inject, in order' \
  || fail "open wake must show the skill body: ${_sk}"

_nofollow=$(drive_work 'view skills' 'follow handoff' 'quit') || true
printf '%s\n' "${_nofollow}" | grep -q 'follow refused: read the skill body this turn' \
  || fail "follow without open must refuse: ${_nofollow}"

_co=$(drive_work 'view connectors' 'inspect' 'connect github' 'disconnect github' 'quit') || true
printf '%s\n' "${_co}" | grep -q '^view: connectors$' \
  || fail "connectors view missing: ${_co}"
printf '%s\n' "${_co}" | grep -q 'actions: connect disconnect inspect view brake mode' \
  || fail "connectors actions missing: ${_co}"
printf '%s\n' "${_co}" | grep -q 'connect is a card, not chat' \
  || fail "connectors must say connect is a card: ${_co}"
printf '%s\n' "${_co}" | grep -q 'note: connect: card github (not chat)' \
  || fail "connect keyboard path missing: ${_co}"
printf '%s\n' "${_co}" | grep -q 'note: disconnect: github' \
  || fail "disconnect keyboard path missing: ${_co}"

_br=$(drive_work 'view bridge' 'inspect' 'approve shell' 'deny shell' 'quit') || true
printf '%s\n' "${_br}" | grep -q '^view: bridge$' \
  || fail "bridge view missing: ${_br}"
printf '%s\n' "${_br}" | grep -q 'actions: approve deny inspect view brake mode' \
  || fail "bridge actions missing: ${_br}"
printf '%s\n' "${_br}" | grep -q 'copy is verbatim, not a mount' \
  || fail "bridge must say copy is verbatim: ${_br}"
printf '%s\n' "${_br}" | grep -q 'note: approve: shell (not run)' \
  || fail "approve keyboard path missing: ${_br}"
printf '%s\n' "${_br}" | grep -q 'note: deny: shell' \
  || fail "deny keyboard path missing: ${_br}"

_st=$(drive_work 'view store' 'inspect' 'quit') || true
printf '%s\n' "${_st}" | grep -q '^view: store$' \
  || fail "store view missing: ${_st}"
printf '%s\n' "${_st}" | grep -q 'actions: inspect view brake mode' \
  || fail "store actions missing: ${_st}"
printf '%s\n' "${_st}" | grep -q 'not /srv/aios/memory' \
  || fail "store must not be OS memory: ${_st}"
printf '%s\n' "${_st}" | grep -q 'notes: hello.md' \
  || fail "store inspect missing notes: ${_st}"
printf '%s\n' "${_st}" | grep -q 'note: inspect: store' \
  || fail "store inspect action missing: ${_st}"

_cv=$(drive_work 'view conversation' 'send hello work' 'attach' 'quit') || true
printf '%s\n' "${_cv}" | grep -q '^view: conversation$' \
  || fail "conversation view missing: ${_cv}"
printf '%s\n' "${_cv}" | grep -q 'operator: hello work' \
  || fail "work conversation send missing: ${_cv}"
printf '%s\n' "${_cv}" | grep -q 'attach: work path' \
  || fail "work attach keyboard path missing: ${_cv}"

_lg=$(drive_work 'view login' 'quit') || true
printf '%s\n' "${_lg}" | grep -q '^view: login$' \
  || fail "login view missing in work: ${_lg}"
printf '%s\n' "${_lg}" | grep -q 'actions: start cancel poll view brake' \
  || fail "login actions missing in work: ${_lg}"
printf '%s\n' "${_lg}" | grep -q 'L-17' \
  || fail "work login must quote L-17: ${_lg}"
printf '%s\n' "${_lg}" | grep -q '^surface: work$' \
  || fail "work login must be labeled work: ${_lg}"

_bots=$(drive_work 'view roster' 'view job' 'quit') || true
printf '%s\n' "${_bots}" | grep -q 'bots view refused (HI-15)' \
  || fail "roster/job must be refused HI-15: ${_bots}"
printf '%s\n' "${_bots}" | grep -q '^view: roster$' \
  && fail "roster opened as product: ${_bots}" || true
printf '%s\n' "${_bots}" | grep -q '^view: job$' \
  && fail "job opened as product: ${_bots}" || true

_priv=$(drive_work \
  'view packages' 'view snapper' 'view envelope' 'view notify' \
  'enact' 'accept' 'reject' 'rollback' 'quit') || true
printf '%s\n' "${_priv}" | grep -q '^mode: work$' \
  || fail "privileged probes must stay work: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'packages refused in work session (L-14)' \
  || fail "packages must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'snapper refused in work session (L-14)' \
  || fail "snapper must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'envelope refused in work session (L-14)' \
  || fail "envelope must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'notify refused in work session (L-14)' \
  || fail "notify must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'enact refused in work session (L-14)' \
  || fail "enact must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'accept refused in work session (L-14)' \
  || fail "accept must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'reject refused in work session (L-14)' \
  || fail "reject must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q 'rollback refused in work session (L-14)' \
  || fail "rollback must be refused L-14: ${_priv}"
printf '%s\n' "${_priv}" | grep -q '^view: packages$' \
  && fail "work session opened packages: ${_priv}" || true

_sw=$(
  printf '%s\n' 'mode work' 'view packages' 'mode os' 'view skills' 'view envelope' 'quit' | \
    AIOS_ANSWERS="${TMP}/on.json" \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    AIOS_ENVELOPE_WORK="${TMP}/missing-envelope.md" \
    python3 -u "${MAIN}"
) || true
printf '%s\n' "${_sw}" | grep -q 'packages refused in work session (L-14)' \
  || fail "mode work then packages must L-14: ${_sw}"
printf '%s\n' "${_sw}" | grep -q 'skills refused in os session (L-14)' \
  || fail "mode os then skills must L-14: ${_sw}"
printf '%s\n' "${_sw}" | grep -q '^view: envelope$' \
  || fail "after mode os, envelope inspect must work: ${_sw}"

_iso=$(
  AIOS_CLIENT="${MAIN}" AIOS_ANSWERS="${TMP}/on.json" \
    AIOS_BRAKE="${TMP}/wrap-unused" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    AIOS_SKILLS="${TMP}/work-src/skills" \
    AIOS_ENVELOPE_WORK="${TMP}/missing-envelope.md" \
    "${ISO_BIN}" work <<'EOF'
s
quit
EOF
) && _isorc=0 || _isorc=$?
[ "${_isorc}" = 0 ] || fail "ISO bin/aios work with yes must open: ${_iso}"
printf '%s\n' "${_iso}" | grep -q '^mode: work$' \
  || fail "ISO bin/aios work with yes must be mode work: ${_iso}"
printf '%s\n' "${_iso}" | grep -q '^view: skills$' \
  || fail "ISO bin/aios letter s must open skills: ${_iso}"

if [ -e /srv/aios/src/work-runtime ]; then
  [ "${WR_BEFORE}" -eq 1 ] || fail "created /srv/aios/src/work-runtime (no synthesis)"
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
if [ "${_live_token}" -eq 0 ] && [ -e "${LIVE_TOKEN}" ]; then
  rm -f "${LIVE_TOKEN}"
  fail "oracle created ${LIVE_TOKEN}"
fi
if [ "${_live_login}" -eq 0 ] && [ -e "${LIVE_LOGIN_REQ}" ]; then
  rm -f "${LIVE_LOGIN_REQ}"
  fail "oracle created ${LIVE_LOGIN_REQ}"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-work-views failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-work-views\n'
exit 0
