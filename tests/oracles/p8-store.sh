#!/bin/sh
# P8.11: work store is git in the work tree, not /srv/aios/memory.
# Host-only. Isolation destroot is required; never write live /srv/aios, /etc, /usr.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
DENY="${ROOT}/agent/aios_agent/deny.py"
MEMORY="${ROOT}/agent/aios_agent/memory.py"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${ROOT}/payload/profile/airootfs/usr/lib/aios/checker/policy"
ISO_AGENT="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
SEED="${ROOT}/seed/work-runtime"
ISO_SEED="${ROOT}/payload/profile/airootfs/srv/aios/seeds/work-runtime"
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
MEM_BEFORE=0
if [ -e /srv/aios/memory ]; then
  MEM_BEFORE=1
fi
LIVE_WANTS_BEFORE=0
if [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
  LIVE_WANTS_BEFORE=1
fi

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${GOALS}" ] || fail "missing goals.py"
[ -f "${MEMORY}" ] || fail "missing memory.py"
[ -x "${POLICY}/work-runtime-store.sh" ] || fail "missing work-runtime-store.sh"
[ -x "${ISO_POLICY}/work-runtime-store.sh" ] || fail "missing ISO work-runtime-store.sh"
[ -d "${SEED}/notes" ] || fail "seed missing notes/"
[ -d "${SEED}/skills" ] || fail "seed missing skills/"
[ -d "${SEED}/routines" ] || fail "seed missing routines/"
[ -d "${SEED}/connectors" ] || fail "seed missing connectors/"
[ -f "${SEED}/notes/README.md" ] || fail "seed missing notes/README.md"
[ -f "${SEED}/routines/README.md" ] || fail "seed missing routines/README.md"
[ -f "${SEED}/connectors/README.md" ] || fail "seed missing connectors/README.md"

cmp -s "${GOALS}" "${ISO_AGENT}/aios_agent/goals.py" \
  || fail "goals.py dual-tree mismatch"
cmp -s "${DENY}" "${ISO_AGENT}/aios_agent/deny.py" \
  || fail "deny.py dual-tree mismatch"
cmp -s "${MEMORY}" "${ISO_AGENT}/aios_agent/memory.py" \
  || fail "memory.py dual-tree mismatch"
cmp -s "${POLICY}/work-runtime-store.sh" "${ISO_POLICY}/work-runtime-store.sh" \
  || fail "work-runtime-store.sh dual-tree mismatch"
cmp -s "${SEED}/notes/README.md" "${ISO_SEED}/notes/README.md" \
  || fail "seed notes dual-tree mismatch"
cmp -s "${SEED}/routines/README.md" "${ISO_SEED}/routines/README.md" \
  || fail "seed routines dual-tree mismatch"
cmp -s "${SEED}/connectors/README.md" "${ISO_SEED}/connectors/README.md" \
  || fail "seed connectors dual-tree mismatch"
cmp -s "${SEED}/envelope/work-runtime.md" "${ISO_SEED}/envelope/work-runtime.md" \
  || fail "seed work-runtime.md dual-tree mismatch"

grep -q 'policy/work-runtime-store.sh' "${GOALS}" \
  || fail "goals.py must name work-runtime-store.sh"
grep -q '/srv/aios/memory' "${SEED}/notes/README.md" \
  || fail "seed notes must name /srv/aios/memory"
grep -q 'routines' "${SEED}/envelope/work-runtime.md" \
  || fail "seed envelope must name routines store"
if grep -E 'curl[[:space:]]*\|' "${ENACT}" >/dev/null; then
  fail "enact contains curl| (HI-04)"
fi

python3 -m py_compile "${GOALS}" "${DENY}" "${MEMORY}" "${MAIN}" \
  || fail "py_compile failed"
sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${POLICY}/work-runtime-store.sh" || fail "sh -n work-runtime-store.sh"
sh -n "${ISO_POLICY}/work-runtime-store.sh" || fail "sh -n ISO work-runtime-store.sh"
sh -n "${0}" || fail "sh -n p8-store.sh"

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

MEM="${DEST}/srv/aios/memory"
mkdir -p "${MEM}"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null

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
  >"${TMP}/out" 2>"${TMP}/err"; then
  fail "destroot synthesise failed: $(cat "${TMP}/err")"
fi
TREE="${DEST}/srv/aios/src/work-runtime"
git -C "${TREE}" rev-parse --is-inside-work-tree >/dev/null \
  || fail "destroot work-runtime is not a git repo"
for _d in notes skills routines connectors
do
  [ -d "${TREE}/${_d}" ] || fail "synthesised tree missing ${_d}/"
done
_listed=$(git -c safe.directory="${TREE}" -C "${TREE}" ls-files)
printf '%s\n' "${_listed}" | grep -q '^notes/' \
  || fail "work git does not track notes/"
printf '%s\n' "${_listed}" | grep -q '^skills/' \
  || fail "work git does not track skills/"
printf '%s\n' "${_listed}" | grep -q '^routines/' \
  || fail "work git does not track routines/"
printf '%s\n' "${_listed}" | grep -q '^connectors/' \
  || fail "work git does not track connectors/"
if git -c safe.directory="${MEM}" -C "${MEM}" ls-files | grep -E '(^|/)(routines|connectors)(/|$)' >/dev/null; then
  fail "memory git tracks routines or connectors before ingest"
fi

if ! (
  cd "${ROOT}/agent"
  AIOS_MEMORY="${MEM}" python3 -c 'from aios_agent.memory import ingest; ingest({"asked":"p8-store"})'
); then
  fail "memory ingest failed"
fi
if git -c safe.directory="${MEM}" -C "${MEM}" ls-files | grep -E '(^|/)(routines|connectors)(/|$)' >/dev/null; then
  fail "memory ingest wrote routines or connectors"
fi
git -c safe.directory="${MEM}" -C "${MEM}" ls-files | grep -q 'exchanges/' \
  || fail "memory ingest did not record an exchange"

if ! AIOS_POLICY_ROOT="${DEST}" AIOS_WORK_SRC="${TREE}" AIOS_MEMORY="${MEM}" \
  "${POLICY}/work-runtime-store.sh"; then
  fail "work-runtime-store.sh failed against synthesised destroot"
fi
if ! AIOS_POLICY_ROOT="${DEST}" AIOS_WORK_SRC="${TREE}" AIOS_MEMORY="${MEM}" \
  "${ISO_POLICY}/work-runtime-store.sh"; then
  fail "ISO work-runtime-store.sh failed against synthesised destroot"
fi

mkdir -p "${TMP}/empty"
if ! AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/work-runtime-store.sh"; then
  fail "work-runtime-store.sh failed against empty destroot (bit off)"
fi

BAD="${TMP}/bad-memory"
mkdir -p "${BAD}/routines"
git -C "${BAD}" init -b main >/dev/null
git -C "${BAD}" config user.name aios
git -C "${BAD}" config user.email aios@localhost
printf '%s\n' x > "${BAD}/routines/x"
git -C "${BAD}" add routines/x
git -C "${BAD}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): plant routines' >/dev/null
if AIOS_POLICY_ROOT="${DEST}" AIOS_WORK_SRC="${TREE}" AIOS_MEMORY="${BAD}" \
  "${POLICY}/work-runtime-store.sh" >/dev/null 2>&1; then
  fail "work-runtime-store.sh passed with routines in memory git"
fi

mkdir -p "${TMP}/yes-no-store/srv/aios/state/bootstrap-in-progress"
printf '%s\n' '{"accepted":true,"work_runtime":true}' \
  > "${TMP}/yes-no-store/srv/aios/state/bootstrap-in-progress/answers.json"
if AIOS_POLICY_ROOT="${TMP}/yes-no-store" "${POLICY}/work-runtime-store.sh" >/dev/null 2>&1; then
  fail "work-runtime-store.sh passed with bit on and no live tree"
fi

# Isolation: unset must not create live /srv/aios/src or memory store files.
env -u AIOS_ROOT env -u AIOS_POLICY_ROOT env -u AIOS_WORK_SRC env -u AIOS_MEMORY \
  "${ENACT}" synthesise work-runtime >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_ROOT enact created /srv/aios/src"
fi
env -u AIOS_POLICY_ROOT env -u AIOS_WORK_SRC env -u AIOS_MEMORY \
  "${POLICY}/work-runtime-store.sh" >/dev/null 2>&1 || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_POLICY_ROOT store policy created /srv/aios/src"
fi
if [ "${MEM_BEFORE}" -eq 0 ] && [ -e /srv/aios/memory ]; then
  fail "unset isolation created /srv/aios/memory"
fi

grep -Fq 'checker/policy/work-runtime-store.sh' "${HASHES}" \
  || fail "payload/hashes.txt must pin work-runtime-store.sh"
grep -Fq 'seed/work-runtime/notes/README.md' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed notes"
grep -Fq 'seed/work-runtime/routines/README.md' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed routines"
grep -Fq 'seed/work-runtime/connectors/README.md' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed connectors"
grep -Fq 'checker/policy/work-runtime-store.sh' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin work-runtime-store.sh"
grep -Fq '/srv/aios/seeds/work-runtime/notes/README.md' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed notes"
grep -Fq '/srv/aios/seeds/work-runtime/routines/README.md' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed routines"
grep -Fq '/srv/aios/seeds/work-runtime/connectors/README.md' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed connectors"

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
if [ "${MEM_BEFORE}" -eq 0 ] && [ -e /srv/aios/memory ]; then
  fail "oracle created /srv/aios/memory"
fi
if [ "${LIVE_WANTS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
  fail "oracle wrote live user-unit wants"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-store failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-store\n'
exit 0
