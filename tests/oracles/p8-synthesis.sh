#!/bin/sh
# P8.1: work-runtime synthesis from local seeds. Offline. HI-15 / HI-17.
# Host-only. Isolation destroot is required; never write live /srv/aios/src.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
DENY="${ROOT}/agent/aios_agent/deny.py"
TRIAGE="${ROOT}/agent/aios_agent/triage.py"
LOOP="${ROOT}/agent/aios_agent/loop.py"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker/policy"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
ISO_ENACT="${ENACT}"
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

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${GOALS}" ] || fail "missing goals.py"
[ -f "${DENY}" ] || fail "missing deny.py"
[ -f "${TRIAGE}" ] || fail "missing triage.py"
[ -x "${POLICY}/work-runtime-git.sh" ] || fail "missing work-runtime-git.sh"
[ -x "${ISO_POLICY}/work-runtime-git.sh" ] || fail "missing ISO work-runtime-git.sh"
[ -d "${SEED}" ] || fail "missing seed/work-runtime"
[ -x "${FIRSTBOOT}" ] || fail "missing firstboot"

cmp -s "${GOALS}" "${ISO_AGENT}/aios_agent/goals.py" \
  || fail "goals.py dual-tree mismatch"
cmp -s "${DENY}" "${ISO_AGENT}/aios_agent/deny.py" \
  || fail "deny.py dual-tree mismatch"
cmp -s "${TRIAGE}" "${ISO_AGENT}/aios_agent/triage.py" \
  || fail "triage.py dual-tree mismatch"
cmp -s "${LOOP}" "${ISO_AGENT}/aios_agent/loop.py" \
  || fail "loop.py dual-tree mismatch"
cmp -s "${ROOT}/agent/AGENTS.md" "${ISO_AGENT}/AGENTS.md" \
  || fail "agent AGENTS.md dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-git.sh" "${ISO_POLICY}/work-runtime-git.sh" \
  || fail "work-runtime-git.sh dual-tree mismatch"

grep -q 'not-while-planning' "${GOALS}" \
  || fail "goals.py must not enact while planning (L-20)"
if grep -nE 'shutil|copytree|systemctl' "${GOALS}" | grep -v '^[^:]*:[[:space:]]*#' >/dev/null; then
  fail "goals.py must not copy trees or call systemctl (L-20)"
fi
grep -q 'work_runtime_yes' "${GOALS}" \
  || fail "goals.py must gate synthesis on work_runtime_yes (HI-15)"
grep -q 'policy/hi-17-seeds-local.sh' "${GOALS}" \
  || fail "goals.py must name hi-17-seeds-local.sh"
grep -q 'policy/work-runtime-git.sh' "${GOALS}" \
  || fail "goals.py must name work-runtime-git.sh"
grep -q 'Do not synthesise the work runtime (HI-15).' "${LOOP}" \
  || fail "loop.py must keep the HI-15 prompt when the bit is off"
grep -q 'is a user unit (L-23)' "${DENY}" \
  || fail "deny.py must keep USER_UNITS on kind=unit (L-23)"
grep -q 'synthesise' "${ENACT}" || fail "enact must grow a synthesise verb"
grep -q 'systemctl --user -M aios-work@' "${ENACT}" \
  || fail "enact live enable must use systemctl --user -M aios-work@"
if grep -nE 'github\.com|git clone' "${ENACT}" >/dev/null; then
  fail "enact must not clone GitHub (HI-17)"
fi
if grep -E 'curl[[:space:]]*\|' "${ENACT}" >/dev/null; then
  fail "enact contains curl| (HI-04)"
fi
grep -q '/srv/aios/src must not exist' "${FIRSTBOOT}" \
  || fail "firstboot must still refuse /srv/aios/src (HI-15)"
if grep -q 'enable aios-work' "${FIRSTBOOT}"; then
  fail "firstboot must not enable work units"
fi
if grep -A80 '^cmd_synthesise()' "${ENACT}" | grep -q -- '-Syu'; then
  fail "cmd_synthesise contains -Syu (L-20)"
fi

python3 -m py_compile \
  "${GOALS}" "${DENY}" "${TRIAGE}" "${LOOP}" "${MAIN}" \
  || fail "py_compile failed"
sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${POLICY}/work-runtime-git.sh" || fail "sh -n work-runtime-git.sh"
sh -n "${ISO_POLICY}/work-runtime-git.sh" || fail "sh -n ISO work-runtime-git.sh"
sh -n "${0}" || fail "sh -n p8-synthesis.sh"

# kind=unit enable must keep dying L-23 even after the synthesise verb exists.
_unit_out=$("${ENACT}" unit enable aios-work-runtime.service 2>&1 || true)
printf '%s\n' "${_unit_out}" | grep -q 'L-23' \
  || fail "enact unit enable aios-work-runtime.service must still die L-23: ${_unit_out}"

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

run_enact() {
  PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" "$@" 2>"${TMP}/err" || true
}

# Bit off: refuse. Skip is not a yes.
printf '%s\n' '{"accepted":true,"work_runtime":false}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"
_out=$(run_enact synthesise work-runtime)
grep -q 'HI-15' "${TMP}/err" \
  || fail "destroot synthesise with work_runtime false must quote HI-15: $(cat "${TMP}/err")"
[ ! -e "${DEST}/srv/aios/src" ] \
  || fail "bit-off synthesise created destroot /srv/aios/src"

printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"
_out=$(run_enact synthesise work-runtime-bots)
grep -q 'HI-15' "${TMP}/err" \
  || fail "synthesise work-runtime-bots must die: $(cat "${TMP}/err")"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "synthesise bots created destroot bots tree"

if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime \
  >"${TMP}/out" 2>"${TMP}/err"; then
  fail "destroot synthesise failed: $(cat "${TMP}/err")"
fi
[ -d "${DEST}/srv/aios/src/work-runtime/.git" ] \
  || fail "destroot missing work-runtime git after synthesise"
git -C "${DEST}/srv/aios/src/work-runtime" rev-parse --is-inside-work-tree >/dev/null \
  || fail "destroot work-runtime is not a git repo"
[ -f "${DEST}/srv/aios/src/work-runtime/AGENTS.md" ] \
  || fail "destroot work-runtime missing AGENTS.md"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "P8.1 synthesised bots (HI-15)"
[ -L "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime.service" ] \
  || fail "destroot missing user-unit wants symlink"
_origin=$(git -C "${DEST}/srv/aios/src/work-runtime" remote get-url origin 2>/dev/null || true)
case "${_origin}" in
  *github*|*http://*|*https://*)
    fail "destroot work-runtime origin is ${_origin}"
    ;;
esac
if grep -q 'invoked on destroot' "${TMP}/err"; then
  fail "destroot synthesise invoked a live helper: $(cat "${TMP}/err")"
fi

# Idempotent: second synthesise must not wipe git.
_rev=$(git -C "${DEST}/srv/aios/src/work-runtime" rev-parse HEAD)
PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime \
  >/dev/null 2>"${TMP}/err2" || fail "idempotent synthesise failed: $(cat "${TMP}/err2")"
_rev2=$(git -C "${DEST}/srv/aios/src/work-runtime" rev-parse HEAD)
[ "${_rev}" = "${_rev2}" ] || fail "idempotent synthesise rewrote git history"

if ! AIOS_POLICY_ROOT="${DEST}" "${POLICY}/work-runtime-git.sh"; then
  fail "work-runtime-git.sh failed against synthesised destroot"
fi
if ! AIOS_POLICY_ROOT="${DEST}" "${ISO_POLICY}/work-runtime-git.sh"; then
  fail "ISO work-runtime-git.sh failed against synthesised destroot"
fi

mkdir -p "${TMP}/empty"
if ! AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/work-runtime-git.sh"; then
  fail "work-runtime-git.sh failed against empty destroot (bit off)"
fi
mkdir -p "${TMP}/yes-no-tree/srv/aios/state/bootstrap-in-progress"
printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${TMP}/yes-no-tree/srv/aios/state/bootstrap-in-progress/answers.json"
if AIOS_POLICY_ROOT="${TMP}/yes-no-tree" "${POLICY}/work-runtime-git.sh" >/dev/null 2>&1; then
  fail "work-runtime-git.sh passed with bit on and no live tree"
fi

# Planner: answers yes → waiting-accept, no live copy.
MEM="${TMP}/memory"
mkdir -p "${MEM}" "${TMP}/notify"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null
printf '%s\n' '{"accepted":true,"work_runtime":true}' > "${TMP}/answers.json"
_plan=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    python3 "${MAIN}" goals
) || true
printf '%s\n' "${_plan}" | grep -q '"status": "waiting-accept"' \
  || fail "goals tick with bit on must plan: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'not-while-planning' \
  || fail "goals tick must not enact while planning: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'policy/hi-17-seeds-local.sh' \
  || fail "goals tick must name hi-17 oracle: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'policy/work-runtime-git.sh' \
  || fail "goals tick must name work-runtime-git oracle: ${_plan}"
printf '%s\n' "${_plan}" | grep -q '"work_runtime": false' \
  || fail "plan tick work_runtime must stay false: ${_plan}"
[ ! -e "${TMP}/work-src" ] || fail "planner created AIOS_WORK_SRC"
[ ! -e "${DEST}/srv/aios/src/work-runtime-bots" ] \
  || fail "planner synthesised bots"

# deny.py: bit off refuses; bit on allows synthesise work-runtime only.
_d_off=$(
  AIOS_ANSWERS="${TMP}/no-answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    python3 "${MAIN}" deny synthesise work-runtime 2>&1 || true
)
printf '%s\n' "${_d_off}" | grep -q 'HI-15' \
  || fail "deny synthesise without env answers must HI-15: ${_d_off}"
_d_on=$(
  AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    python3 "${MAIN}" deny synthesise work-runtime 2>&1
) || fail "deny synthesise with bit on failed: ${_d_on}"
_d_bots=$(
  AIOS_ANSWERS="${TMP}/answers.json" \
    python3 "${MAIN}" deny synthesise work-runtime-bots 2>&1 || true
)
printf '%s\n' "${_d_bots}" | grep -q 'HI-15' \
  || fail "deny synthesise bots must HI-15: ${_d_bots}"
_d_unit=$(python3 "${MAIN}" deny unit enable aios-work-runtime.service 2>&1 || true)
printf '%s\n' "${_d_unit}" | grep -q 'L-23' \
  || fail "deny unit enable must stay L-23: ${_d_unit}"

# triage: bit off raises HI-15; bit on is not a conflict.
_t_off=$(
  AIOS_ANSWERS="${TMP}/no-answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    python3 - "${ROOT}/agent/aios_agent" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from triage import classify
r = classify("synthesise the work runtime")
print(r.kind)
print(r.hi or "")
PY
) || fail "triage bit-off classify failed"
printf '%s\n' "${_t_off}" | grep -q conflict \
  || fail "triage bit off must conflict: ${_t_off}"
printf '%s\n' "${_t_off}" | grep -q HI-15 \
  || fail "triage bit off must quote HI-15: ${_t_off}"
_t_on=$(
  AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    python3 - "${ROOT}/agent/aios_agent" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from triage import classify
r = classify("synthesise the work runtime")
print(r.kind)
print(r.hi or "")
PY
) || fail "triage bit-on classify failed"
printf '%s\n' "${_t_on}" | grep -q conflict \
  && fail "triage bit on must not HI-15 conflict: ${_t_on}" || true

# Isolation: unset AIOS_ROOT / AIOS_POLICY_ROOT must not create live /srv/aios/src.
env -u AIOS_ROOT env -u AIOS_POLICY_ROOT \
  "${ENACT}" synthesise work-runtime >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_ROOT enact created /srv/aios/src"
fi
env -u AIOS_POLICY_ROOT "${POLICY}/work-runtime-git.sh" >/dev/null 2>&1 || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_POLICY_ROOT policy created /srv/aios/src"
fi

grep -Fq 'payload/profile/airootfs/usr/lib/aios/bin/enact' "${HASHES}" \
  || fail "payload/hashes.txt must pin enact"
grep -Fq 'agent/aios_agent/goals.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin goals.py"
grep -Fq 'checker/policy/work-runtime-git.sh' "${HASHES}" \
  || fail "payload/hashes.txt must pin work-runtime-git.sh"
grep -Fq 'bin/enact' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin bin/enact"
grep -Fq 'agent/aios_agent/goals.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin goals.py"
grep -Fq 'checker/policy/work-runtime-git.sh' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin work-runtime-git.sh"

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
  printf 'error: p8-synthesis failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-synthesis\n'
exit 0
