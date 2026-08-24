#!/bin/sh
# P8.13 / P8.16: jobs are path+slice+skill; virsh from the slice fails; VM is an intent.
# Host-only. Isolation destroot is required; never write live /srv/aios/src.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
DENY="${ROOT}/agent/aios_agent/deny.py"
TUI="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker/policy"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
SEED="${ROOT}/seed/work-runtime"
BOTS_SEED="${ROOT}/seed/work-runtime-bots"
ISO_BOTS="${ROOT}/payload/profile/airootfs/srv/aios/seeds/work-runtime-bots"
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

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${BOTS_SEED}/main.py" ] || fail "bots seed missing main.py"
[ -f "${BOTS_SEED}/jobs/build-guests.md" ] || fail "bots seed missing a job file"
[ -f "${BOTS_SEED}/envelope/work-runtime-bots.md" ] || fail "bots seed missing envelope clause"
[ -x "${POLICY}/work-runtime-bots-git.sh" ] || fail "missing work-runtime-bots-git.sh"

cmp -s "${GOALS}" "${ISO_AGENT}/aios_agent/goals.py" \
  || fail "goals.py dual-tree mismatch"
cmp -s "${DENY}" "${ISO_AGENT}/aios_agent/deny.py" \
  || fail "deny.py dual-tree mismatch"
cmp -s "${TUI}" "${ISO_OC}/tty/aios.py" \
  || fail "aios.py dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-bots-git.sh" "${ISO_POLICY}/work-runtime-bots-git.sh" \
  || fail "work-runtime-bots-git.sh dual-tree mismatch"
diff -qr -x __pycache__ -x '*.pyc' "${BOTS_SEED}" "${ISO_BOTS}" \
  || fail "ISO work-runtime-bots seed != seed/work-runtime-bots"

if grep -Ein -- '^(name|avatar|psyche|personhood|identity):' \
  "${BOTS_SEED}/jobs/"*.md "${ISO_BOTS}/jobs/"*.md 2>/dev/null \
  | grep -v README.md
then
  fail "jobs must not store avatars, personhood, identity, or psyche"
fi
grep -q 'path:' "${BOTS_SEED}/jobs/build-guests.md" \
  || fail "job file missing path"
grep -q 'slice:' "${BOTS_SEED}/jobs/build-guests.md" \
  || fail "job file missing slice"
grep -q 'skill:' "${BOTS_SEED}/jobs/build-guests.md" \
  || fail "job file missing skill"
grep -q 'virsh' "${BOTS_SEED}/main.py" \
  || fail "bots main.py must refuse virsh"
grep -q 'work-runtime-bots' "${BOTS_SEED}/main.py" \
  || fail "bots main.py must file work-runtime-bots intents"
grep -q 'last_evidence' "${BOTS_SEED}/main.py" \
  || fail "handoff must be operational (last_evidence)"

_pyct=$(mktemp -d)
cp -a "${BOTS_SEED}/main.py" "${_pyct}/main.py"
python3 -m py_compile "${GOALS}" "${DENY}" "${MAIN}" "${TUI}" "${_pyct}/main.py" \
  || fail "py_compile failed"
rm -rf "${_pyct}"
sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${POLICY}/work-runtime-bots-git.sh" || fail "sh -n work-runtime-bots-git.sh"
sh -n "${0}" || fail "sh -n p8-bots-job.sh"

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
cp -a "${BOTS_SEED}" "${DEST}/srv/aios/seeds/work-runtime-bots"
printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${DEST}/srv/aios/state/bootstrap-in-progress/answers.json"
printf '%s\n' '# Clause: work-runtime-bots' 'enabled: true' \
  > "${DEST}/srv/aios/envelope/work-runtime-bots.md"

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
  >"${TMP}/wr.out" 2>"${TMP}/wr.err"; then
  fail "destroot synthesise work-runtime failed: $(cat "${TMP}/wr.err")"
fi
if ! PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime-bots \
  >"${TMP}/bots.out" 2>"${TMP}/bots.err"; then
  fail "destroot synthesise bots failed: $(cat "${TMP}/bots.err")"
fi
if grep -q 'invoked on destroot' "${TMP}/bots.err"; then
  fail "destroot synthesise bots invoked a live helper: $(cat "${TMP}/bots.err")"
fi
TREE="${DEST}/srv/aios/src/work-runtime-bots"
[ -d "${TREE}/.git" ] || fail "destroot missing bots git after synthesise"
git -C "${TREE}" rev-parse --is-inside-work-tree >/dev/null \
  || fail "destroot bots is not a git repo"
[ -f "${TREE}/main.py" ] || fail "synthesised bots missing main.py"
[ -f "${TREE}/jobs/build-guests.md" ] || fail "synthesised bots missing job file"
[ -L "${DEST}/etc/systemd/user/default.target.wants/aios-work-runtime-bots.service" ] \
  || fail "destroot missing bots user-unit wants symlink"
[ ! -e "${DEST}/etc/systemd/system/aios-work-runtime-bots.service" ] \
  || fail "destroot grew a system bots unit"
_origin=$(git -C "${TREE}" remote get-url origin 2>/dev/null || true)
case "${_origin}" in
  *github*|*http://*|*https://*)
    fail "destroot bots origin is ${_origin}"
    ;;
esac

_rev=$(git -C "${TREE}" rev-parse HEAD)
PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" synthesise work-runtime-bots \
  >/dev/null 2>"${TMP}/err2" || fail "idempotent bots synthesise failed: $(cat "${TMP}/err2")"
_rev2=$(git -C "${TREE}" rev-parse HEAD)
[ "${_rev}" = "${_rev2}" ] || fail "idempotent bots synthesise rewrote git history"

if ! AIOS_POLICY_ROOT="${DEST}" "${POLICY}/work-runtime-bots-git.sh"; then
  fail "work-runtime-bots-git.sh failed against synthesised destroot"
fi
if ! AIOS_POLICY_ROOT="${DEST}" "${ISO_POLICY}/work-runtime-bots-git.sh"; then
  fail "ISO work-runtime-bots-git.sh failed against synthesised destroot"
fi

_rost=$(python3 "${TREE}/main.py" roster) || fail "bots roster failed"
printf '%s\n' "${_rost}" | grep -q 'path + slice + skill' \
  || fail "roster must name path+slice+skill: ${_rost}"
printf '%s\n' "${_rost}" | grep -q 'not selves' \
  || fail "roster must say not selves: ${_rost}"
printf '%s\n' "${_rost}" | grep -q 'slice=aios-work.slice' \
  || fail "roster missing slice: ${_rost}"
printf '%s\n' "${_rost}" | grep -q 'skill=skills/fleet.md' \
  || fail "roster missing skill: ${_rost}"
printf '%s\n' "${_rost}" | grep -Eqi 'avatar=|psyche=|personhood=' \
  && fail "roster leaked identity: ${_rost}" || true

_vir=$(python3 "${TREE}/main.py" virsh list 2>"${TMP}/vir.err" || true)
grep -q 'HI-13' "${TMP}/vir.err" \
  || fail "virsh from bots must quote HI-13: $(cat "${TMP}/vir.err")"
grep -q 'intent' "${TMP}/vir.err" \
  || fail "virsh from bots must name intent.sock: $(cat "${TMP}/vir.err")"
printf '%s\n' "${_vir}" | grep -q '"source"' \
  && fail "virsh must not file an intent: ${_vir}" || true

_vm=$(python3 "${TREE}/main.py" vm start build-guest) || fail "vm start must file an intent"
printf '%s\n' "${_vm}" | grep -q '"source": "work-runtime-bots"' \
  || fail "vm start intent source must be work-runtime-bots: ${_vm}"
printf '%s\n' "${_vm}" | grep -q 'vm start build-guest' \
  || fail "vm start asked missing: ${_vm}"
printf '%s\n' "${_vm}" | python3 -c '
import json,sys
doc=json.load(sys.stdin)
need=("id","source","asked")
for k in need:
    if k not in doc:
        raise SystemExit("missing %s" % k)
if doc.get("source") != "work-runtime-bots":
    raise SystemExit("bad source")
' || fail "vm start intent schema: ${_vm}"

_hand=$(python3 "${TREE}/main.py" handoff build-guests) || fail "handoff failed"
printf '%s\n' "${_hand}" | python3 -c '
import json,sys
doc=json.load(sys.stdin)
for k in ("path","slice","skill","oracles","last_evidence"):
    if k not in doc:
        raise SystemExit("handoff missing %s" % k)
blob=json.dumps(doc).lower()
for tok in ("avatar","psyche","personhood"):
    if tok in blob:
        raise SystemExit("handoff has %s" % tok)
' || fail "handoff must be operational: ${_hand}"

_d_ok=$(
  AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/missing.md" \
    AIOS_ENVELOPE_BOTS="${DEST}/srv/aios/envelope/work-runtime-bots.md" \
    python3 "${MAIN}" deny synthesise work-runtime-bots 2>&1
) || fail "deny synthesise bots with second bit on failed: ${_d_ok}"

printf '%s\n' '{"work_runtime":true}' > "${TMP}/on.json"
_tui=$(
  printf '%s\n' 'view roster' 'view job' 'quit' \
    | AIOS_ANSWERS="${TMP}/on.json" \
      AIOS_ENVELOPE_BOTS="${DEST}/srv/aios/envelope/work-runtime-bots.md" \
      AIOS_BOTS_SRC="${TREE}" \
      AIOS_BRAKE="${TMP}/unused-brake" \
      python3 -u "${TUI}" work
) || true
printf '%s\n' "${_tui}" | grep -q '^mode: work$' \
  || fail "work session with bots bit on must open: ${_tui}"
printf '%s\n' "${_tui}" | grep -q '^view: job$' \
  || fail "job view missing with bots bit on: ${_tui}"
printf '%s\n' "${_tui}" | grep -q 'path + slice + skill' \
  || fail "job view must name path+slice+skill: ${_tui}"
printf '%s\n' "${_tui}" | grep -q 'no avatar' \
  || fail "job view must refuse avatars: ${_tui}"
printf '%s\n' "${_tui}" | grep -q 'catalog:.* roster' \
  || fail "work catalog missing roster when bots bit on: ${_tui}"

MEM="${TMP}/memory"
mkdir -p "${MEM}" "${TMP}/notify"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null

_plan=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/missing.md" \
    AIOS_ENVELOPE_BOTS="${DEST}/srv/aios/envelope/work-runtime-bots.md" \
    AIOS_WORK_SRC="${DEST}/srv/aios/src/work-runtime" \
    AIOS_BOTS_SRC="${TMP}/no-bots-src" \
    python3 "${MAIN}" goals
) || true
printf '%s\n' "${_plan}" | grep -q '"status": "waiting-accept"' \
  || fail "goals tick with bots bit on must plan: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'work-runtime-bots' \
  || fail "goals tick must name work-runtime-bots: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'policy/work-runtime-bots-git.sh' \
  || fail "goals tick must name bots git oracle: ${_plan}"
printf '%s\n' "${_plan}" | grep -q 'not-while-planning' \
  || fail "goals tick must not enact while planning: ${_plan}"
[ ! -e "${TMP}/no-bots-src" ] || fail "planner created AIOS_BOTS_SRC"

_idle=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${DEST}/srv/aios/state/bootstrap-in-progress/answers.json" \
    AIOS_ENVELOPE_WORK="${DEST}/srv/aios/envelope/missing.md" \
    AIOS_ENVELOPE_BOTS="${DEST}/srv/aios/envelope/work-runtime-bots.md" \
    AIOS_WORK_SRC="${DEST}/srv/aios/src/work-runtime" \
    AIOS_BOTS_SRC="${TREE}" \
    python3 "${MAIN}" goals
) || true
printf '%s\n' "${_idle}" | grep -q '"status": "idle"' \
  || fail "empty tick after bots git must idle: ${_idle}"

env -u AIOS_ROOT env -u AIOS_POLICY_ROOT \
  "${ENACT}" synthesise work-runtime-bots >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_ROOT enact created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime-bots/main.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin bots main.py"
grep -Fq 'seed/work-runtime-bots/jobs/build-guests.md' "${HASHES}" \
  || fail "payload/hashes.txt must pin job file"
grep -Fq '/srv/aios/seeds/work-runtime-bots/main.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin bots main.py"

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

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-bots-job failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-bots-job\n'
exit 0
