#!/bin/sh
# P7.1 P7.3: one binary summon, chrome action brake. HI-15 work refused.
# Envelope: P7.1, P7.3, L-12, L-18, HI-15, L-09, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/aios"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
LOGIN="${ROOT}/installer/aios_installer/login.py"
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
UNIT="${ROOT}/payload/profile/airootfs/etc/systemd/system/aios-agent.service"
GOALS="${ROOT}/agent/aios_agent/goals.py"
INST_MAIN="${ROOT}/installer/aios_installer/main.py"
TMPFILES="${ROOT}/payload/profile/airootfs/usr/lib/tmpfiles.d/aios.conf"
DROP=/srv/aios/state/brake.d
STAMP=${DROP}/stamp
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
[ -x "${FIRSTBOOT}" ] || fail "firstboot must be executable"

grep -q 'exec /usr/bin/python3' "${ISO_BIN}" \
  || fail "bin/aios must exec python3"
grep -q 'operator-client/tty/aios.py' "${ISO_BIN}" \
  || fail "bin/aios must launch operator-client/tty/aios.py"
grep -q 'P7.1' "${ISO_BIN}" || fail "bin/aios must quote P7.1"
grep -q 'L-09' "${ISO_BIN}" || fail "bin/aios must quote L-09"

grep -q 'bin/aios' "${FIRSTBOOT}" \
  || fail "firstboot must copy bin/aios"
grep -q 'operator-client' "${FIRSTBOOT}" \
  || fail "firstboot must copy operator-client"
grep -q 'payload operator-client source missing' "${FIRSTBOOT}" \
  || fail "firstboot must require operator-client source"

grep -q 'L-18' "${MAIN}" || fail "aios.py must quote L-18"
grep -q 'L-12' "${MAIN}" || fail "aios.py must quote L-12"
grep -q 'HI-15' "${MAIN}" || fail "aios.py must quote HI-15"
grep -q 'P7.1' "${MAIN}" || fail "aios.py must quote P7.1"

grep -q "BRAKE_PATH = \"${STAMP}\"" "${MAIN}" \
  || fail "aios.py BRAKE_PATH must be ${STAMP}"
grep -q "BRAKE_PATH = \"${STAMP}\"" "${INST_MAIN}" \
  || fail "installer main.py BRAKE_PATH must be ${STAMP}"
grep -q "BRAKE_PATH = \"${STAMP}\"" "${LOGIN}" \
  || fail "login.py BRAKE_PATH must be ${STAMP}"
grep -q "BRAKE_PATH = \"${STAMP}\"" "${GOALS}" \
  || fail "goals.py BRAKE_PATH must be ${STAMP}"
grep -qx "BRAKE=${STAMP}" "${ENACT}" \
  || fail "enact BRAKE must be ${STAMP}"
grep -qx "ConditionPathExists=!${STAMP}" "${UNIT}" \
  || fail "aios-agent.service must ConditionPathExists !${STAMP}"
grep -Fq "${DROP}" "${TMPFILES}" \
  || fail "tmpfiles must name ${DROP} (L-12)"
grep -qx "d ${DROP} - - - -" "${TMPFILES}" \
  || fail "tmpfiles must not set mode/owner on brake.d (1731 must survive boot)"
if grep -F "${DROP}" "${TMPFILES}" | grep -Eq '0700|root root'
then
  fail "tmpfiles must not reset brake.d to 0700 root:root"
fi
grep -Fq "${DROP}" "${FIRSTBOOT}" \
  || fail "firstboot must restore ${DROP} after chown -R state"
grep -Fq "chmod 0700 \"\${TARGET}${DROP}\"" "${FIRSTBOOT}" \
  || fail "firstboot must chmod 0700 brake.d (not 0777 state)"
grep -q "'/brake.d/'" "${FIRSTBOOT}" \
  || fail "firstboot must gitignore /brake.d/ (HI-09)"
grep -Fq "${DROP}" "${LOGIN}" \
  || fail "login.py must grant ${DROP}"
grep -q '0o1731' "${LOGIN}" \
  || fail "login.py must chmod brake drop 1731"
grep -q '_grant_brake_drop' "${LOGIN}" \
  || fail "login.py must grant the brake drop at accept"
if grep -En 'chmod[[:space:]]+0777[[:space:]].*state|chmod\(.*0o777' \
  "${LOGIN}" "${FIRSTBOOT}" "${TMPFILES}" 2>/dev/null
then
  fail "must not chmod 0777 /srv/aios/state (HI-16)"
fi

python3 - "${MAIN}" <<'PY' || fail "brake must not be an L-18 view id"
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
if "brake" in views:
    raise SystemExit("brake is a view id (L-18); it must be a chrome action")
if "chrome" not in views:
    raise SystemExit("chrome missing from VIEWS")
if "conversation" not in views:
    raise SystemExit("conversation missing from VIEWS")
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" \
  || fail "copy aios.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" || fail "py_compile aios.py failed"
cp -a "${ISO_OC}/tty/aios.py" "${_pyct}/iso-aios.py" \
  || fail "copy ISO aios.py for py_compile"
python3 -m py_compile "${_pyct}/iso-aios.py" || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${ISO_BIN}" || fail "sh -n bin/aios"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"
sh -n "${0}" || fail "sh -n p7-summon-brake.sh"

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

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' \
  "${ROOT}/operator-client" \
  "${ISO_BIN}" \
  "${ISO_OC}" \
  "${ROOT}/installer" \
  "${FIRSTBOOT}" 2>/dev/null
then
  fail "operator-client/installer/firstboot contains -Syu (L-20)"
fi

if grep -REin -- 'hyprland|gnome|kwin|keybind|key.?chord|bindsym' \
  "${ROOT}/operator-client" "${ISO_BIN}" "${ISO_OC}" 2>/dev/null
then
  fail "key chord / DE bind in operator-client or bin/aios"
fi

for _unit in aios-tui.service aios-operator.service aios-aios.service; do
  if [ -e "${ROOT}/payload/profile/airootfs/etc/systemd/system/${_unit}" ]; then
    fail "new TUI systemd unit ${_unit} (P7.1: no daemon)"
  fi
done

grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/bin/aios$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin bin/aios"
grep -E '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin operator-client/tty/aios.py"
grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/operator-client/tty/aios.py$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin ISO operator-client aios.py"
grep -Eq '^[0-9a-f]{64}  bin/aios$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin bin/aios"
grep -Eq '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin operator-client/tty/aios.py"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_BRAKE="${STAMP}"
LIVE_OLD="/srv/aios/state/brake"
_live_existed=0
_live_old=0
[ -e "${LIVE_BRAKE}" ] && _live_existed=1
[ -e "${LIVE_OLD}" ] && _live_old=1

drive() {
  printf '%s\n' "$@" | AIOS_BRAKE="${TMP}/unused-brake" python3 -u "${MAIN}"
}

_os=$(drive 'quit') || true
printf '%s\n' "${_os}" | grep -q '^mode: os$' \
  || fail "aios must open mode os: ${_os}"
printf '%s\n' "${_os}" | grep -q '^view: chrome$' \
  || fail "aios must default to chrome: ${_os}"
printf '%s\n' "${_os}" | grep -q '^actions: view brake send mode$' \
  || fail "chrome actions missing: ${_os}"
printf '%s\n' "${_os}" | grep -q 'L-12' \
  || fail "chrome must quote L-12 on brake: ${_os}"
printf '%s\n' "${_os}" | grep -q '^brake: off$' \
  || fail "default brake must be off: ${_os}"
printf '%s\n' "${_os}" | grep -q '^catalog:.* brake' \
  && fail "catalog must not list brake as a view: ${_os}" || true

_os2=$(printf 'quit\n' | AIOS_BRAKE="${TMP}/unused-brake" python3 -u "${MAIN}" os) \
  || true
printf '%s\n' "${_os2}" | grep -q '^mode: os$' \
  || fail "aios os must open mode os: ${_os2}"
printf '%s\n' "${_os2}" | grep -q '^view: chrome$' \
  || fail "aios os must default to chrome: ${_os2}"

_work=$(AIOS_BRAKE="${TMP}/unused-brake" python3 -u "${MAIN}" work) && _wrc=0 || _wrc=$?
[ "${_wrc}" != 0 ] || fail "aios work must be refused: ${_work}"
printf '%s\n' "${_work}" | grep -q 'HI-15' \
  || fail "aios work must quote HI-15: ${_work}"
printf '%s\n' "${_work}" | grep -q '^mode: work$' \
  && fail "aios work opened a work session: ${_work}" || true
printf '%s\n' "${_work}" | grep -q 'view: chrome' \
  && fail "aios work must not open the TUI: ${_work}" || true

_mw=$(drive 'mode work' 'quit') || true
printf '%s\n' "${_mw}" | grep -q 'HI-15' \
  || fail "mode work must quote HI-15: ${_mw}"
printf '%s\n' "${_mw}" | grep -q '^mode: os$' \
  || fail "mode work must stay os: ${_mw}"
printf '%s\n' "${_mw}" | grep -q '^mode: work$' \
  && fail "mode work switched surface: ${_mw}" || true

_mi=$(drive 'mode installer' 'quit') || true
printf '%s\n' "${_mi}" | grep -q 'mode refused: installer' \
  || fail "mode installer must be refused: ${_mi}"

_brfile="${TMP}/brake"
_br=$(
  AIOS_BRAKE="${_brfile}" python3 -u "${MAIN}" brake
) && _brc=0 || _brc=$?
[ "${_brc}" = 0 ] || fail "aios brake must return 0: ${_br}"
[ -f "${_brfile}" ] || fail "aios brake must write AIOS_BRAKE"
printf '%s\n' "${_br}" | grep -q 'L-12' \
  || fail "aios brake must quote L-12: ${_br}"
printf '%s\n' "${_br}" | grep -q '^brake: on$' \
  || fail "aios brake must report on: ${_br}"

_stay=$(
  AIOS_BRAKE="${TMP}/brake-tui" python3 -u "${MAIN}" <<'EOF'
brake
view chrome
quit
EOF
) || true
[ -f "${TMP}/brake-tui" ] || fail "TUI brake must write AIOS_BRAKE"
printf '%s\n' "${_stay}" | grep -q 'L-12' \
  || fail "TUI brake must quote L-12: ${_stay}"
printf '%s\n' "${_stay}" | grep -q '^brake: on$' \
  || fail "TUI brake must show on: ${_stay}"
printf '%s\n' "${_stay}" | grep -q '^view: chrome$' \
  || fail "TUI must stay after brake (view chrome): ${_stay}"
printf '%s\n' "${_stay}" | grep -q 'TUI stays' \
  || fail "TUI brake must keep the client up: ${_stay}"

_vb=$(drive 'view brake' 'quit') || true
printf '%s\n' "${_vb}" | grep -q 'chrome action' \
  || fail "view brake must refuse as a view id: ${_vb}"
printf '%s\n' "${_vb}" | grep -q '^view: brake$' \
  && fail "view brake must not become the view: ${_vb}" || true

_stub=$(drive 'view envelope' 'quit') || true
printf '%s\n' "${_stub}" | grep -q 'not this PR' \
  || fail "unimplemented OS view must say not this PR: ${_stub}"
printf '%s\n' "${_stub}" | grep -q '^view: envelope$' \
  || fail "envelope view id must be reachable as a stub: ${_stub}"

_st=$(AIOS_BRAKE="${_brfile}" python3 -u "${MAIN}" status) || true
printf '%s\n' "${_st}" | grep -q '^mode: os$' \
  || fail "aios status must report mode os: ${_st}"
printf '%s\n' "${_st}" | grep -q '^brake: on$' \
  || fail "aios status must see the stamp: ${_st}"
printf '%s\n' "${_st}" | grep -q 'L-12' \
  || fail "aios status must quote L-12: ${_st}"

_wrap="${TMP}/wrap-brake"
_wout=$(
  AIOS_CLIENT="${MAIN}" AIOS_BRAKE="${_wrap}" "${ISO_BIN}" brake
) && _wrc=0 || _wrc=$?
[ "${_wrc}" = 0 ] || fail "ISO bin/aios brake must return 0: ${_wout}"
[ -f "${_wrap}" ] || fail "ISO bin/aios brake must write AIOS_BRAKE"
printf '%s\n' "${_wout}" | grep -q 'L-12' \
  || fail "ISO bin/aios brake must quote L-12: ${_wout}"

_ww=$(AIOS_CLIENT="${MAIN}" AIOS_BRAKE="${TMP}/wrap-unused" "${ISO_BIN}" work) \
  && _wwrc=0 || _wwrc=$?
[ "${_wwrc}" != 0 ] || fail "ISO bin/aios work must be refused: ${_ww}"
printf '%s\n' "${_ww}" | grep -q 'HI-15' \
  || fail "ISO bin/aios work must quote HI-15: ${_ww}"

if grep -n 'sleep(3600)' "${MAIN}" >/dev/null; then
  fail "TTY path must not sleep(3600) on EOF (L-09)"
fi
grep -q 'signal.SIG_IGN' "${MAIN}" \
  || fail "TTY must ignore SIGINT so readline is not interrupted (L-09)"

if [ "${_live_existed}" -eq 0 ] && [ -e "${LIVE_BRAKE}" ]; then
  rm -f "${LIVE_BRAKE}"
  fail "oracle created ${LIVE_BRAKE}"
fi
if [ "${_live_old}" -eq 0 ] && [ -e "${LIVE_OLD}" ]; then
  rm -f "${LIVE_OLD}"
  fail "oracle created ${LIVE_OLD}"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-summon-brake failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-summon-brake\n'
exit 0
