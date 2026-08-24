#!/bin/sh
# P8.2: L-15 write set lock + L-23 vendor user-unit file. HI-15 HI-16.
# Host-only. Isolation destroot is required; never write live /etc, /usr, /srv/aios.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
AIROOTFS="${ROOT}/payload/profile/airootfs"
SLICE="${AIROOTFS}/etc/systemd/system/aios-work.slice"
FLOOR="${AIROOTFS}/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
USER_UNIT="${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime.service"
TMPFILES="${AIROOTFS}/usr/lib/tmpfiles.d/aios.conf"
FIRSTBOOT="${AIROOTFS}/usr/lib/aios/bin/firstboot"
SEED_CLAUSE="${ROOT}/seed/work-runtime/envelope/work-runtime.md"
ISO_SEED_CLAUSE="${AIROOTFS}/srv/aios/seeds/work-runtime/envelope/work-runtime.md"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${AIROOTFS}/usr/lib/aios/checker/policy"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${AIROOTFS}/usr/lib/aios/hashes.txt"
RW_SET='ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime'
INACC='InaccessiblePaths=/srv/aios/envelope /srv/aios/state /srv/aios/agent /srv/aios/checker /srv/aios/git /etc/systemd/system /usr/lib/aios/bin/enact'
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

WR_BEFORE=0
if [ -e /srv/aios/src ]; then
  WR_BEFORE=1
fi
LIVE_SLICE_BEFORE=0
if [ -e /etc/systemd/system/aios-work.slice ]; then
  LIVE_SLICE_BEFORE=1
fi
LIVE_FLOOR_BEFORE=0
if [ -e /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf ]; then
  LIVE_FLOOR_BEFORE=1
fi
LIVE_USER_UNIT_BEFORE=0
if [ -e /usr/lib/systemd/user/aios-work-runtime.service ]; then
  LIVE_USER_UNIT_BEFORE=1
fi
LIVE_SYS_UNIT_BEFORE=0
if [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  LIVE_SYS_UNIT_BEFORE=1
fi
LIVE_LINGER_BEFORE=0
if [ -e /var/lib/systemd/linger/aios-work ]; then
  LIVE_LINGER_BEFORE=1
fi

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -f "${SLICE}" ] || fail "missing aios-work.slice"
[ -f "${FLOOR}" ] || fail "missing floor drop-in"
[ -f "${USER_UNIT}" ] || fail "missing aios-work-runtime.service user unit (L-23)"
[ -f "${TMPFILES}" ] || fail "missing tmpfiles.d/aios.conf"
[ -f "${FIRSTBOOT}" ] || fail "missing firstboot"
[ -f "${SEED_CLAUSE}" ] || fail "missing seed work-runtime.md"
[ -f "${ISO_SEED_CLAUSE}" ] || fail "missing ISO seed work-runtime.md"
[ -x "${POLICY}/hi-16-os-privilege.sh" ] || fail "missing hi-16-os-privilege.sh"
[ -x "${POLICY}/work-slice.sh" ] || fail "missing work-slice.sh"

if [ -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime.service" ]; then
  fail "aios-work-runtime.service must not be a system unit (L-23)"
fi
if [ -e "${AIROOTFS}/usr/lib/systemd/system/aios-work-runtime.service" ]; then
  fail "aios-work-runtime.service must not be a system unit (L-23)"
fi
if [ -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime-bots.service" ] \
  || [ -e "${AIROOTFS}/usr/lib/systemd/system/aios-work-runtime-bots.service" ] \
  || [ -e "${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime-bots.service" ]; then
  fail "aios-work-runtime-bots.service must not be added (L-23)"
fi
if [ -e "${AIROOTFS}/usr/lib/systemd/user/default.target.wants/aios-work-runtime.service" ] \
  || [ -e "${AIROOTFS}/etc/systemd/user/default.target.wants/aios-work-runtime.service" ] \
  || [ -e "${AIROOTFS}/etc/systemd/system/default.target.wants/aios-work-runtime.service" ]; then
  fail "aios-work-runtime.service must not be enabled (HI-15)"
fi
if [ -e "${AIROOTFS}/srv/aios/src" ]; then
  fail "/srv/aios/src must not exist in airootfs (HI-15)"
fi

grep -qx 'Description=AIOS unprivileged work runtime' "${USER_UNIT}" \
  || fail "user unit Description mismatch"
grep -qx 'ConditionPathIsDirectory=/srv/aios/src/work-runtime' "${USER_UNIT}" \
  || fail "user unit missing ConditionPathIsDirectory (HI-15)"
grep -qx 'ConditionPathExists=/srv/aios/src/work-runtime/main.py' "${USER_UNIT}" \
  || fail "user unit missing ConditionPathExists main.py"
grep -qx 'MemoryMax=2G' "${USER_UNIT}" || fail "user unit MemoryMax must be 2G (L-06)"
grep -qx 'CPUQuota=200%' "${USER_UNIT}" || fail "user unit CPUQuota must be 200% (L-06)"
grep -qx 'NoNewPrivileges=yes' "${USER_UNIT}" \
  || fail "user unit missing NoNewPrivileges=yes (HI-16)"
grep -qx 'ProtectSystem=strict' "${USER_UNIT}" \
  || fail "user unit missing ProtectSystem=strict (HI-16)"
grep -qx 'ProtectHome=read-only' "${USER_UNIT}" \
  || fail "user unit ProtectHome must be read-only (L-15)"
grep -qx 'CapabilityBoundingSet=' "${USER_UNIT}" \
  || fail "user unit CapabilityBoundingSet must be empty (L-06)"
grep -qx "${RW_SET}" "${USER_UNIT}" \
  || fail "user unit ReadWritePaths is not the L-15 set"
_rw=$(grep -c '^ReadWritePaths=' "${USER_UNIT}" || true)
[ "${_rw}" = 1 ] || fail "user unit ReadWritePaths must be a single line"
grep -qx "${INACC}" "${USER_UNIT}" \
  || fail "user unit InaccessiblePaths is not the privileged set"
grep -q 'InaccessiblePaths=.*envelope' "${USER_UNIT}" \
  || fail "user unit does not hide envelope"
grep -q 'InaccessiblePaths=.*state' "${USER_UNIT}" \
  || fail "user unit does not hide state"
grep -q 'InaccessiblePaths=.*enact' "${USER_UNIT}" \
  || fail "user unit does not hide enact"
if grep '^ReadWritePaths=' "${USER_UNIT}" | grep -Eq '/home|~/src|/srv/aios/envelope|/srv/aios/state|/srv/aios/agent|/srv/aios/checker|/srv/aios/git'; then
  fail "user unit ReadWritePaths includes a privileged or home path"
fi
_rw_u=$(grep '^ReadWritePaths=' "${USER_UNIT}")
_rw_f=$(grep '^ReadWritePaths=' "${FLOOR}")
[ "${_rw_u}" = "${_rw_f}" ] || fail "user unit and floor ReadWritePaths disagree (L-15)"
if grep -E '^(User|Group|Slice)=' "${USER_UNIT}" >/dev/null; then
  fail "user unit must not set User=/Group=/Slice="
fi
grep -qx 'ExecStart=/usr/bin/python3 /srv/aios/src/work-runtime/main.py' "${USER_UNIT}" \
  || fail "user unit ExecStart must be work-runtime main.py"
if grep '^ExecStart=' "${USER_UNIT}" | grep -q 'enact'; then
  fail "user unit must not ExecStart enact"
fi
if grep '^ExecStart=' "${USER_UNIT}" | grep -Eq 'aios_agent|/usr/lib/aios/bin/'; then
  fail "user unit must not ExecStart the OS agent"
fi
grep -qx 'WantedBy=default.target' "${USER_UNIT}" \
  || fail "user unit missing WantedBy=default.target"
if grep -q -- '-Syu' "${USER_UNIT}" "${FLOOR}" "${SLICE}"; then
  fail "P8.2 units contain -Syu (L-20)"
fi

grep -Eq '^f[[:space:]]+/var/lib/systemd/linger/aios-work([[:space:]]|$)' "${TMPFILES}" \
  || fail "tmpfiles.d/aios.conf missing linger/aios-work (L-23)"
if grep -q 'loginctl enable-linger' "${FIRSTBOOT}" "${TMPFILES}"; then
  fail "linger must be tmpfiles, not loginctl"
fi

grep -q '/usr/lib/systemd/user/aios-work-runtime.service' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-work-runtime user unit"
grep -q 'aios-work-runtime user unit missing on target' "${FIRSTBOOT}" \
  || fail "firstboot must fail closed if the user unit is missing"
grep -q 'usr/lib/systemd/user' "${FIRSTBOOT}" \
  || fail "firstboot must mkdir /usr/lib/systemd/user"
grep -q '/srv/aios/src must not exist' "${FIRSTBOOT}" \
  || fail "firstboot must refuse /srv/aios/src (HI-15)"
grep -q 'user unit must stay disabled' "${FIRSTBOOT}" \
  || fail "firstboot must refuse to leave the user unit enabled"
if grep -q 'enable aios-work' "${FIRSTBOOT}"; then
  fail "firstboot must not enable work units"
fi
if grep -E 'systemctl.*[[:space:]](enable|start)[[:space:]].*aios-work' "${FIRSTBOOT}" >/dev/null; then
  fail "firstboot must not enable/start a work process"
fi
if grep -q -- '-Syu' "${FIRSTBOOT}"; then
  fail "firstboot contains -Syu (L-20)"
fi

cmp -s "${SEED_CLAUSE}" "${ISO_SEED_CLAUSE}" \
  || fail "ISO work-runtime envelope != seed"
grep -q '/srv/aios/src/work-runtime' "${SEED_CLAUSE}" \
  || fail "seed envelope must name the L-15 write set"
grep -q 'ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime' "${SEED_CLAUSE}" \
  || fail "seed envelope must lock ReadWritePaths"
grep -q '~/src' "${SEED_CLAUSE}" \
  || fail "seed envelope must name ~/src as the bridge"

sh -n "${0}" || fail "sh -n p8-writeset.sh"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"
sh -n "${POLICY}/hi-16-os-privilege.sh" || fail "sh -n hi-16-os-privilege.sh"
sh -n "${ISO_POLICY}/hi-16-os-privilege.sh" || fail "sh -n ISO hi-16-os-privilege.sh"

mkdir -p "${TMP}/root/etc/systemd/system" \
  "${TMP}/root/usr/lib/systemd/system/aios-work-.service.d" \
  "${TMP}/root/usr/lib/systemd/user"
cp -a "${SLICE}" "${TMP}/root/etc/systemd/system/aios-work.slice"
cp -a "${FLOOR}" "${TMP}/root/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
cp -a "${USER_UNIT}" "${TMP}/root/usr/lib/systemd/user/aios-work-runtime.service"

# Isolation is required; never probe the workstation's live /etc/systemd.
if ! AIOS_POLICY_ROOT="${TMP}/root" "${POLICY}/work-slice.sh"; then
  fail "work-slice.sh failed against payload copies"
fi
if ! AIOS_POLICY_ROOT="${TMP}/root" "${POLICY}/hi-16-os-privilege.sh"; then
  fail "hi-16-os-privilege.sh failed against payload copies"
fi
if ! AIOS_POLICY_ROOT="${TMP}/root" "${ISO_POLICY}/hi-16-os-privilege.sh"; then
  fail "ISO hi-16-os-privilege.sh failed against payload copies"
fi

mkdir -p "${TMP}/empty"
if AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/work-slice.sh" >/dev/null 2>&1; then
  fail "work-slice.sh passed with empty AIOS_POLICY_ROOT destroot"
fi
if AIOS_POLICY_ROOT="${TMP}/empty" "${POLICY}/hi-16-os-privilege.sh" >/dev/null 2>&1; then
  fail "hi-16-os-privilege.sh passed with empty AIOS_POLICY_ROOT destroot"
fi

grep -Fq 'payload/profile/airootfs/usr/lib/systemd/user/aios-work-runtime.service' "${HASHES}" \
  || fail "payload/hashes.txt must pin aios-work-runtime user unit"
grep -Fq 'aios-work-.service.d/10-floor.conf' "${HASHES}" \
  || fail "payload/hashes.txt must pin floor drop-in"
grep -Fq 'usr/lib/tmpfiles.d/aios.conf' "${HASHES}" \
  || fail "payload/hashes.txt must pin tmpfiles.d/aios.conf"
grep -Fq '/usr/lib/systemd/user/aios-work-runtime.service' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin aios-work-runtime user unit"
grep -Fq '/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin floor drop-in"
grep -Fq '/usr/lib/tmpfiles.d/aios.conf' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin tmpfiles.d/aios.conf"

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
    /*) f="${AIROOTFS}${path}" ;;
    *) f="${AIROOTFS}/usr/lib/aios/${path}" ;;
  esac
  [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
  printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
    || fail "ISO hash mismatch: ${path}"
done < "${ISO_HASHES}"

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15)"
fi
if [ "${LIVE_SLICE_BEFORE}" -eq 0 ] && [ -e /etc/systemd/system/aios-work.slice ]; then
  fail "oracle wrote live aios-work.slice"
fi
if [ "${LIVE_FLOOR_BEFORE}" -eq 0 ] \
  && [ -e /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf ]; then
  fail "oracle wrote live floor drop-in"
fi
if [ "${LIVE_USER_UNIT_BEFORE}" -eq 0 ] \
  && [ -e /usr/lib/systemd/user/aios-work-runtime.service ]; then
  fail "oracle wrote live aios-work-runtime.service"
fi
if [ "${LIVE_SYS_UNIT_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  fail "oracle wrote live system aios-work-runtime.service"
fi
if [ "${LIVE_LINGER_BEFORE}" -eq 0 ] \
  && [ -e /var/lib/systemd/linger/aios-work ]; then
  fail "oracle wrote live linger/aios-work"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-writeset failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-writeset\n'
exit 0
