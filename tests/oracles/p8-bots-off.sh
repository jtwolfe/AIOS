#!/bin/sh
# P8.13: work-runtime yes does not start bots. Second bit default off.
# Host-only. Isolation destroot is required; never write live /srv/aios/src.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
DENY="${ROOT}/agent/aios_agent/deny.py"
GATE="${ROOT}/agent/aios_agent/bots_gate.py"
LOGIN="${ROOT}/installer/aios_installer/login.py"
TUI="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_LOGIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer/aios_installer/login.py"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker/policy"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
AIROOTFS="${ROOT}/payload/profile/airootfs"
BOTS_UNIT="${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime-bots.service"
SEED="${ROOT}/seed/work-runtime"
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
if [ -e /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service ]; then
  LIVE_WANTS_BEFORE=1
fi
LIVE_SYS_BEFORE=0
if [ -e /etc/systemd/system/aios-work-runtime-bots.service ]; then
  LIVE_SYS_BEFORE=1
fi
LIVE_BOTS_UNIT_BEFORE=0
if [ -e /usr/lib/systemd/user/aios-work-runtime-bots.service ]; then
  LIVE_BOTS_UNIT_BEFORE=1
fi

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${GOALS}" ] || fail "missing goals.py"
[ -f "${GATE}" ] || fail "missing bots_gate.py"
[ -f "${TUI}" ] || fail "missing aios.py"
[ -f "${BOTS_UNIT}" ] || fail "missing bots user unit (L-23; vendor file may exist when bit is off)"
[ -x "${POLICY}/work-runtime-bots-git.sh" ] || fail "missing work-runtime-bots-git.sh"
[ -x "${ISO_POLICY}/work-runtime-bots-git.sh" ] || fail "missing ISO work-runtime-bots-git.sh"

cmp -s "${GOALS}" "${ISO_AGENT}/aios_agent/goals.py" \
  || fail "goals.py dual-tree mismatch"
cmp -s "${DENY}" "${ISO_AGENT}/aios_agent/deny.py" \
  || fail "deny.py dual-tree mismatch"
cmp -s "${TUI}" "${ISO_OC}/tty/aios.py" \
  || fail "aios.py dual-tree mismatch"
cmp -s "${GATE}" "${ISO_AGENT}/aios_agent/bots_gate.py" \
  || fail "bots_gate.py dual-tree mismatch"
cmp -s "${LOGIN}" "${ISO_LOGIN}" \
  || fail "login.py dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-bots-git.sh" "${ISO_POLICY}/work-runtime-bots-git.sh" \
  || fail "work-runtime-bots-git.sh dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-bit.sh" "${ISO_POLICY}/work-runtime-bit.sh" \
  || fail "work-runtime-bit.sh dual-tree mismatch"

if [ -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime-bots.service" ] \
  || [ -e "${AIROOTFS}/usr/lib/systemd/system/aios-work-runtime-bots.service" ]; then
  fail "aios-work-runtime-bots.service must not be a system unit (L-23)"
fi
if [ -e "${AIROOTFS}/usr/lib/systemd/user/default.target.wants/aios-work-runtime-bots.service" ]; then
  fail "bots user unit must not be enabled on the payload (HI-15)"
fi

grep -q 'bots_yes' "${GOALS}" || fail "goals.py must gate bots on bots_yes (HI-15)"
grep -q 'bots_compute_yes' "${POLICY}/work-runtime-bit.sh" \
  || fail "work-runtime-bit.sh must compute bots_yes"
grep -q 'aios-work-runtime-bots.service' "${FIRSTBOOT}" \
  || fail "firstboot must copy bots user unit"
grep -q 'aios-work-runtime-bots user unit missing on target' "${FIRSTBOOT}" \
  || fail "firstboot must fail closed if the bots user unit is missing"
if grep -q 'enable aios-work' "${FIRSTBOOT}"; then
  fail "firstboot must not enable work units"
fi
grep -q 'bots-request' "${LOGIN}" \
  || fail "accept must create /run/aios/bots-request"
grep -q 'tick_bots' "${ROOT}/agent/aios_agent/main.py" \
  || fail "agent serve must tick_bots"
grep -q '"enable", "work-runtime-bots"' "${GATE}" \
  || fail "bots_gate must enact enable work-runtime-bots"
if grep -E '^\s*"bots"' "${ROOT}/installer/aios_installer/questions.py"; then
  fail "installer questions must not ask bots"
fi
grep -q 'policy/work-runtime-bots-git.sh' "${GOALS}" \
  || fail "work-runtime oracles must include work-runtime-bots-git.sh"

python3 -m py_compile "${GOALS}" "${DENY}" "${MAIN}" "${GATE}" "${TUI}" \
  || fail "py_compile failed"
sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${POLICY}/work-runtime-bots-git.sh" || fail "sh -n work-runtime-bots-git.sh"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"
sh -n "${0}" || fail "sh -n p8-bots-off.sh"

DEST="${TMP}/root"
mkdir -p \
  "${DEST}/etc/aios" \
  "${DEST}/srv/aios/state/bootstrap-in-progress" \
  "${DEST}/srv/aios/seeds" \
  "${DEST}/srv/aios/envelope" \
  "${DEST}/run/aios"
: > "${DEST}/etc/aios/envelope-accepted"
chmod 0644 "${DEST}/etc/aios/envelope-accepted"
: > "${DEST}/run/aios/bots-request"
chmod 0660 "${DEST}/run/aios/bots-request"
cp -a "${SEED}" "${DEST}/srv/aios/seeds/work-runtime"
cp -a "${ROOT}/seed/work-runtime-bots" "${DEST}/srv/aios/seeds/work-runtime-bots"
printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"

BIN="${TMP}/bin"
mkdir -p "${BIN}"
for _n in systemctl snapper bootctl curl wget pacman virsh
do
  cat > "${BIN}/${_n}" <<EOF
#!/bin/sh
printf 'error: ${_n} invoked on destroot\n' >&2
exit 1
EOF
  chmod +x "${BIN}/${_n}"
done
ORACLE_PATH="${BIN}:${PATH}"

if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime \
  >"${TMP}/syn.out" 2>"${TMP}/syn.err"; then
  fail "destroot synthesise work-runtime failed: $(cat "${TMP}/syn.err")"
fi
[ -d "${DEST}/srv/aios/src/work-runtime/.git" ] \
  || fail "destroot missing work-runtime git"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "work-runtime yes synthesised bots tree (HI-15)"
[ ! -e "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime-bots.service" ] \
  || fail "work-runtime yes enabled bots wants"

PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime-bots \
  >"${TMP}/bots.out" 2>"${TMP}/bots.err" || true
grep -q 'HI-15' "${TMP}/bots.err" \
  || fail "synthesise bots with work-runtime only must quote HI-15: $(cat "${TMP}/bots.err")"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "synthesise bots created destroot bots tree with bit off"

printf '%s\n' '{"accepted":true,"work_runtime":true,"bots":true}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"
PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime-bots \
  >"${TMP}/json.out" 2>"${TMP}/json.err" || true
grep -q 'HI-15' "${TMP}/json.err" \
  || fail "answers.json bots true must not enable bots: $(cat "${TMP}/json.err")"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "JSON bots true synthesised bots tree"

if ! AIOS_POLICY_ROOT="${DEST}" "${POLICY}/work-runtime-bots-git.sh"; then
  fail "work-runtime-bots-git.sh failed with bit off"
fi
if ! AIOS_POLICY_ROOT="${DEST}" "${ISO_POLICY}/work-runtime-bots-git.sh"; then
  fail "ISO work-runtime-bots-git.sh failed with bit off"
fi

_d_bots=$(
  AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/missing.md" \
    python3 "${MAIN}" deny synthesise work-runtime-bots 2>&1 || true
)
printf '%s\n' "${_d_bots}" | grep -q 'HI-15' \
  || fail "deny synthesise bots with JSON bots true must HI-15: ${_d_bots}"

printf '%s\n' '{"work_runtime":false}' > "${TMP}/off.json"
: > "${DEST}/run/aios/bots-request"
_env=$(
  printf '%s\n' 'view envelope' 'bots yes' 'quit' \
    | AIOS_ANSWERS="${TMP}/off.json" AIOS_BRAKE="${TMP}/unused-brake" \
      AIOS_ROOT="${DEST}" python3 -u "${TUI}"
) || true
printf '%s\n' "${_env}" | grep -q 'HI-15' \
  || fail "envelope bots yes without work-runtime must quote HI-15: ${_env}"
_req0=$(cat "${DEST}/run/aios/bots-request")
[ -z "${_req0}" ] || fail "bots yes without work-runtime must not write request"
[ ! -f "${DEST}/srv/aios/envelope/work-runtime-bots.md" ] \
  || fail "bots yes without work-runtime wrote a clause"

printf '%s\n' '{"work_runtime":true}' > "${TMP}/on.json"
_rost=$(
  printf '%s\n' 'view roster' 'view job' 'quit' \
    | AIOS_ANSWERS="${TMP}/on.json" AIOS_BRAKE="${TMP}/unused-brake" \
      AIOS_ROOT="${DEST}" python3 -u "${TUI}" work
) || true
printf '%s\n' "${_rost}" | grep -q 'HI-15' \
  || fail "roster with bots bit off must quote HI-15: ${_rost}"
printf '%s\n' "${_rost}" | grep -q '^view: roster$' \
  && fail "roster opened with bots bit off: ${_rost}" || true

_req=$(
  printf '%s\n' 'view envelope' 'bots yes' 'quit' \
    | AIOS_ANSWERS="${TMP}/on.json" AIOS_BRAKE="${TMP}/unused-brake" \
      AIOS_ROOT="${DEST}" python3 -u "${TUI}"
) || true
grep -qx yes "${DEST}/run/aios/bots-request" \
  || fail "bots yes with work-runtime must write destroot request: ${_req}"
[ ! -f "${DEST}/srv/aios/envelope/work-runtime-bots.md" ] \
  || fail "TUI must not write the envelope clause"

grep -Fq 'agent/aios_agent/bots_gate.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin bots_gate.py"
grep -Fq 'checker/policy/work-runtime-bots-git.sh' "${HASHES}" \
  || fail "payload/hashes.txt must pin work-runtime-bots-git.sh"
grep -Fq 'aios-work-runtime-bots.service' "${HASHES}" \
  || fail "payload/hashes.txt must pin bots user unit"
grep -Fq 'checker/policy/work-runtime-bots-git.sh' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin work-runtime-bots-git.sh"
grep -Fq '/usr/lib/systemd/user/aios-work-runtime-bots.service' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin bots user unit"

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15)"
fi
if [ "${LIVE_WANTS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service ]; then
  fail "oracle wrote live bots wants"
fi
if [ "${LIVE_SYS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/system/aios-work-runtime-bots.service ]; then
  fail "oracle wrote live system bots unit"
fi
if [ "${LIVE_BOTS_UNIT_BEFORE}" -eq 0 ] \
  && [ -e /usr/lib/systemd/user/aios-work-runtime-bots.service ]; then
  fail "oracle wrote live bots user unit"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-bots-off failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-bots-off\n'
exit 0
