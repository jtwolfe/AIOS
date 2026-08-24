#!/bin/sh
# P8.12: disable is an envelope patch; stop units, leave git (HI-15).
# Host-only. Isolation destroot is required; never write live /srv/aios, /etc, /usr.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
DENY="${ROOT}/agent/aios_agent/deny.py"
LOOP="${ROOT}/agent/aios_agent/loop.py"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker/policy"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
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
if [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
  LIVE_WANTS_BEFORE=1
fi
LIVE_SYS_BEFORE=0
if [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  LIVE_SYS_BEFORE=1
fi
LIVE_CLAUSE_BEFORE=0
if [ -e /srv/aios/envelope/work-runtime.md ]; then
  LIVE_CLAUSE_BEFORE=1
fi

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${GOALS}" ] || fail "missing goals.py"
[ -f "${DENY}" ] || fail "missing deny.py"
[ -x "${POLICY}/hi-15-work-default-off.sh" ] || fail "missing hi-15-work-default-off.sh"
[ -x "${ISO_POLICY}/hi-15-work-default-off.sh" ] || fail "missing ISO hi-15"

cmp -s "${GOALS}" "${ISO_AGENT}/aios_agent/goals.py" \
  || fail "goals.py dual-tree mismatch"
cmp -s "${DENY}" "${ISO_AGENT}/aios_agent/deny.py" \
  || fail "deny.py dual-tree mismatch"
cmp -s "${LOOP}" "${ISO_AGENT}/aios_agent/loop.py" \
  || fail "loop.py dual-tree mismatch"
cmp -s "${POLICY}/hi-15-work-default-off.sh" "${ISO_POLICY}/hi-15-work-default-off.sh" \
  || fail "hi-15 dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-git.sh" "${ISO_POLICY}/work-runtime-git.sh" \
  || fail "work-runtime-git.sh dual-tree mismatch"
cmp -s "${POLICY}/work-slice.sh" "${ISO_POLICY}/work-slice.sh" \
  || fail "work-slice.sh dual-tree mismatch"

grep -q 'disable' "${ENACT}" || fail "enact must grow a disable verb"
grep -q 'systemctl --user -M aios-work@ stop' "${ENACT}" \
  || fail "enact live disable must use systemctl --user -M aios-work@ stop"
grep -q 'systemctl --user -M aios-work@ disable' "${ENACT}" \
  || fail "enact live disable must use systemctl --user -M aios-work@ disable"
grep -q 'default.target.wants' "${ENACT}" \
  || fail "enact destroot disable must name wants symlink"
grep -q '_DISABLED_LINE' "${GOALS}" \
  || fail "goals.py must match envelope enabled: false"
_dis=$(sed -n '/^cmd_disable()/,/^cmd_synthesise()/p' "${ENACT}")
printf '%s\n' "${_dis}" | grep -q -- '-Syu' \
  && fail "cmd_disable contains -Syu (L-20)" || true
printf '%s\n' "${_dis}" | grep -q snapper \
  && fail "cmd_disable must not snapper-rollback the work tree" || true
printf '%s\n' "${_dis}" | grep -E 'rm -rf .*work-runtime' >/dev/null \
  && fail "cmd_disable must not delete the work tree" || true
if grep -E 'curl[[:space:]]*\|' "${ENACT}" >/dev/null; then
  fail "enact contains curl| (HI-04)"
fi
if grep -nE 'shutil|copytree|systemctl' "${GOALS}" | grep -v '^[^:]*:[[:space:]]*#' >/dev/null; then
  fail "goals.py must not copy trees or call systemctl (L-20)"
fi

python3 -m py_compile "${GOALS}" "${DENY}" "${LOOP}" "${MAIN}" \
  || fail "py_compile failed"
sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${POLICY}/hi-15-work-default-off.sh" || fail "sh -n hi-15"
sh -n "${0}" || fail "sh -n p8-disable.sh"

_unit_out=$("${ENACT}" unit disable aios-work-runtime.service 2>&1 || true)
printf '%s\n' "${_unit_out}" | grep -q 'L-23' \
  || fail "enact unit disable aios-work-runtime.service must still die L-23: ${_unit_out}"
_d_unit=$(python3 "${MAIN}" deny unit disable aios-work-runtime.service 2>&1 || true)
printf '%s\n' "${_d_unit}" | grep -q 'L-23' \
  || fail "deny unit disable must stay L-23: ${_d_unit}"
_d_bots=$(python3 "${MAIN}" deny disable work-runtime-bots 2>&1 || true)
printf '%s\n' "${_d_bots}" | grep -q 'HI-15' \
  || fail "deny disable bots must HI-15: ${_d_bots}"
_e_bots=$("${ENACT}" disable work-runtime-bots 2>&1 || true)
printf '%s\n' "${_e_bots}" | grep -q 'HI-15' \
  || fail "enact disable bots must HI-15: ${_e_bots}"

DEST="${TMP}/root"
mkdir -p \
  "${DEST}/etc/aios" \
  "${DEST}/srv/aios/state/bootstrap-in-progress" \
  "${DEST}/srv/aios/seeds" \
  "${DEST}/srv/aios/envelope" \
  "${DEST}/run/aios"
: > "${DEST}/etc/aios/envelope-accepted"
chmod 0644 "${DEST}/etc/aios/envelope-accepted"
cp -a "${SEED}" "${DEST}/srv/aios/seeds/work-runtime"
cp -a "${ROOT}/seed/work-runtime-bots" "${DEST}/srv/aios/seeds/work-runtime-bots"
printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"

BIN="${TMP}/bin"
mkdir -p "${BIN}"
for _n in systemctl snapper bootctl curl wget pacman
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
  fail "destroot synthesise failed: $(cat "${TMP}/syn.err")"
fi
TREE="${DEST}/srv/aios/src/work-runtime"
[ -d "${TREE}/.git" ] || fail "destroot missing work-runtime git after synthesise"
[ -L "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime.service" ] \
  || fail "destroot missing user-unit wants symlink"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "synthesise created bots tree"
_rev=$(git -C "${TREE}" rev-parse HEAD)

if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" disable work-runtime \
  >"${TMP}/dis.out" 2>"${TMP}/dis.err"; then
  fail "destroot disable failed: $(cat "${TMP}/dis.err")"
fi
if grep -q 'invoked on destroot' "${TMP}/dis.err"; then
  fail "destroot disable invoked a live helper: $(cat "${TMP}/dis.err")"
fi
[ -d "${TREE}/.git" ] || fail "disable deleted work-runtime git"
git -C "${TREE}" rev-parse --is-inside-work-tree >/dev/null \
  || fail "disable left a non-git work tree"
_rev2=$(git -C "${TREE}" rev-parse HEAD)
[ "${_rev}" = "${_rev2}" ] || fail "disable rewrote work-runtime git history"
[ ! -e "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime.service" ] \
  || fail "disable left user-unit wants symlink"
[ ! -e "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime-bots.service" ] \
  || fail "disable enabled bots wants"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "disable created bots tree"
grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(false|no|0)[[:space:]]*$' \
  "${DEST}/srv/aios/envelope/work-runtime.md" \
  || fail "disable did not patch envelope enabled: false"

if PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime \
  >"${TMP}/re.out" 2>"${TMP}/re.err"; then
  fail "synthesise after disable must refuse"
fi
grep -q 'HI-15' "${TMP}/re.err" \
  || fail "synthesise after disable must quote HI-15: $(cat "${TMP}/re.err")"
[ -d "${TREE}/.git" ] || fail "refused synthesise deleted git"

if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" disable work-runtime \
  >"${TMP}/dis2.out" 2>"${TMP}/dis2.err"; then
  fail "idempotent disable failed: $(cat "${TMP}/dis2.err")"
fi
[ -d "${TREE}/.git" ] || fail "idempotent disable deleted git"

if ! AIOS_POLICY_ROOT="${DEST}" "${POLICY}/hi-15-work-default-off.sh"; then
  fail "hi-15 failed against disabled destroot"
fi
if ! AIOS_POLICY_ROOT="${DEST}" "${ISO_POLICY}/hi-15-work-default-off.sh"; then
  fail "ISO hi-15 failed against disabled destroot"
fi
if ! AIOS_POLICY_ROOT="${DEST}" "${POLICY}/work-runtime-git.sh"; then
  fail "work-runtime-git.sh failed against disabled destroot"
fi

MEM="${TMP}/memory"
mkdir -p "${MEM}" "${TMP}/notify"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null

_idle=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/work-runtime.md" \
    AIOS_WORK_SRC="${TREE}" \
    python3 "${MAIN}" goals
) || true
printf '%s\n' "${_idle}" | grep -q '"status": "idle"' \
  || fail "empty tick after disable must idle: ${_idle}"
printf '%s\n' "${_idle}" | grep -q '"proposal": null' \
  || fail "empty tick after disable must not propose: ${_idle}"

_evt=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/work-runtime.md" \
    AIOS_WORK_SRC="${TREE}" \
    python3 "${MAIN}" goals '{"kind":"work-runtime"}'
) || true
printf '%s\n' "${_evt}" | grep -q 'HI-15' \
  || fail "work-runtime event after disable must quote HI-15: ${_evt}"
printf '%s\n' "${_evt}" | grep -q '"proposal": null' \
  || fail "work-runtime event after disable must not propose: ${_evt}"

_d_off=$(
  AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/work-runtime.md" \
    python3 "${MAIN}" deny synthesise work-runtime 2>&1 || true
)
printf '%s\n' "${_d_off}" | grep -q 'HI-15' \
  || fail "deny synthesise after disable must HI-15: ${_d_off}"
_d_ok=$(
  python3 "${MAIN}" deny disable work-runtime 2>&1
) || fail "deny disable work-runtime failed: ${_d_ok}"

# Disable never-synthesised destroot must not create src.
NEVER="${TMP}/never"
mkdir -p \
  "${NEVER}/etc/aios" \
  "${NEVER}/srv/aios/state/bootstrap-in-progress" \
  "${NEVER}/srv/aios/envelope" \
  "${NEVER}/run/aios"
: > "${NEVER}/etc/aios/envelope-accepted"
printf '%s\n' '{"accepted":true,"work_runtime":false}' \
  > "${NEVER}/srv/aios/state/bootstrap-in-progress/answers.json"
if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${NEVER}" "${ENACT}" disable work-runtime \
  >"${TMP}/never.out" 2>"${TMP}/never.err"; then
  fail "disable with bit off failed: $(cat "${TMP}/never.err")"
fi
[ ! -e "${NEVER}/srv/aios/src" ] \
  || fail "disable with bit off created /srv/aios/src"
[ ! -e "${NEVER}/etc/systemd/user/default.target.wants/aios-work-runtime-bots.service" ] \
  || fail "disable with bit off enabled bots"
grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(false|no|0)[[:space:]]*$' \
  "${NEVER}/srv/aios/envelope/work-runtime.md" \
  || fail "disable with bit off did not write enabled: false"

# Isolation: unset must not mutate live paths.
env -u AIOS_ROOT env -u AIOS_POLICY_ROOT env -u AIOS_WORK_SRC \
  "${ENACT}" disable work-runtime >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_ROOT disable created /srv/aios/src"
fi
if [ "${LIVE_CLAUSE_BEFORE}" -eq 0 ] && [ -e /srv/aios/envelope/work-runtime.md ]; then
  fail "unset AIOS_ROOT disable wrote live envelope"
fi
env -u AIOS_POLICY_ROOT "${POLICY}/hi-15-work-default-off.sh" >/dev/null 2>&1 || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_POLICY_ROOT hi-15 created /srv/aios/src"
fi

grep -Fq 'payload/profile/airootfs/usr/lib/aios/bin/enact' "${HASHES}" \
  || fail "payload/hashes.txt must pin enact"
grep -Fq 'agent/aios_agent/goals.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin goals.py"
grep -Fq 'checker/policy/hi-15-work-default-off.sh' "${HASHES}" \
  || fail "payload/hashes.txt must pin hi-15"
grep -Fq 'bin/enact' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin bin/enact"
grep -Fq 'agent/aios_agent/goals.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin goals.py"

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
if [ "${LIVE_CLAUSE_BEFORE}" -eq 0 ] && [ -e /srv/aios/envelope/work-runtime.md ]; then
  fail "oracle wrote live envelope/work-runtime.md"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-disable failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-disable\n'
exit 0
