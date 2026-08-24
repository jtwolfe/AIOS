#!/bin/sh
# P6.2: aios-work.slice + floor drop-in. HI-13 HI-16. L-23 user unit is a file, not a system unit.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
AIROOTFS="${ROOT}/payload/profile/airootfs"
SLICE="${AIROOTFS}/etc/systemd/system/aios-work.slice"
FLOOR="${AIROOTFS}/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
USER_UNIT="${AIROOTFS}/usr/lib/systemd/user/aios-work-runtime.service"
FIRSTBOOT="${AIROOTFS}/usr/lib/aios/bin/firstboot"
POLICY="${ROOT}/checker/policy"
ISO_POLICY="${AIROOTFS}/usr/lib/aios/checker/policy"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${AIROOTFS}/usr/lib/aios/hashes.txt"
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
[ -f "${FIRSTBOOT}" ] || fail "missing firstboot"
[ -x "${POLICY}/work-slice.sh" ] || fail "missing work-slice.sh"
[ -x "${POLICY}/hi-16-os-privilege.sh" ] || fail "missing hi-16-os-privilege.sh"

grep -qx 'MemoryMax=2G' "${SLICE}" || fail "aios-work.slice MemoryMax must be 2G (L-06)"
grep -qx 'CPUQuota=200%' "${SLICE}" || fail "aios-work.slice CPUQuota must be 200% (L-06)"
grep -qx '\[Slice\]' "${SLICE}" || fail "aios-work.slice missing [Slice] (L-06)"
grep -qx 'Description=AIOS unprivileged work' "${SLICE}" \
  || fail "aios-work.slice Description mismatch"

grep -qx 'NoNewPrivileges=yes' "${FLOOR}" \
  || fail "floor drop-in missing NoNewPrivileges=yes (HI-16)"
grep -qx 'ProtectSystem=strict' "${FLOOR}" \
  || fail "floor drop-in missing ProtectSystem=strict (HI-16)"
grep -qx 'CapabilityBoundingSet=' "${FLOOR}" \
  || fail "floor drop-in CapabilityBoundingSet must be empty (L-06)"
grep -qx 'Slice=aios-work.slice' "${FLOOR}" \
  || fail "floor drop-in missing Slice=aios-work.slice"
grep -qx 'ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime' "${FLOOR}" \
  || fail "floor ReadWritePaths is not the L-15 floor set"
_rw=$(grep -c '^ReadWritePaths=' "${FLOOR}" || true)
[ "${_rw}" = 1 ] || fail "floor ReadWritePaths must be a single floor line"
grep -qx 'InaccessiblePaths=/srv/aios/envelope /srv/aios/state /srv/aios/agent /srv/aios/checker /srv/aios/git /etc/systemd/system /usr/lib/aios/bin/enact' \
  "${FLOOR}" || fail "floor InaccessiblePaths is not the privileged set"
grep -q 'InaccessiblePaths=.*envelope' "${FLOOR}" \
  || fail "floor drop-in does not hide envelope"
grep -q 'InaccessiblePaths=.*state' "${FLOOR}" \
  || fail "floor drop-in does not hide state"
grep -q 'InaccessiblePaths=.*enact' "${FLOOR}" \
  || fail "floor drop-in does not hide enact"
if grep '^ReadWritePaths=' "${FLOOR}" | grep -Eq '/home|/srv/aios/envelope|/srv/aios/state|/srv/aios/agent|/srv/aios/checker|/srv/aios/git'; then
  fail "floor ReadWritePaths includes a privileged or home path"
fi

[ -f "${USER_UNIT}" ] || fail "missing aios-work-runtime.service user unit (L-23)"
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
if [ -e "${AIROOTFS}/srv/aios/src" ]; then
  fail "/srv/aios/src must not exist in airootfs (HI-15)"
fi
if [ -e "${AIROOTFS}/etc/systemd/system/multi-user.target.wants/aios-work.slice" ] \
  || [ -e "${AIROOTFS}/etc/systemd/system/slices.target.wants/aios-work.slice" ]; then
  fail "aios-work.slice must not be enabled on the live ISO"
fi

grep -q 'aios-work.slice' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-work.slice"
grep -q 'aios-work-.service.d/10-floor.conf' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-work floor drop-in"
grep -q 'aios-work.slice missing on target' "${FIRSTBOOT}" \
  || fail "firstboot must fail closed if aios-work.slice is missing"
grep -q 'aios-work floor drop-in missing on target' "${FIRSTBOOT}" \
  || fail "firstboot must fail closed if the floor drop-in is missing"
grep -q '/srv/aios/src must not exist' "${FIRSTBOOT}" \
  || fail "firstboot must refuse /srv/aios/src (HI-15)"
if grep -q 'enable aios-work' "${FIRSTBOOT}"; then
  fail "firstboot must not enable work units"
fi
if grep -E 'systemctl.*[[:space:]]start[[:space:]].*aios-work' "${FIRSTBOOT}" >/dev/null; then
  fail "firstboot must not start a work process"
fi
if grep -q -- '-Syu' "${FIRSTBOOT}" "${SLICE}" "${FLOOR}"; then
  fail "P6.2 files contain -Syu (L-20)"
fi

cmp -s "${POLICY}/work-slice.sh" "${ISO_POLICY}/work-slice.sh" \
  || fail "ISO work-slice.sh bytes differ"
cmp -s "${POLICY}/hi-16-os-privilege.sh" "${ISO_POLICY}/hi-16-os-privilege.sh" \
  || fail "ISO hi-16-os-privilege.sh bytes differ"

sh -n "${0}" || fail "sh -n p6-work-slice.sh"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"
sh -n "${POLICY}/work-slice.sh" || fail "sh -n work-slice.sh"
sh -n "${POLICY}/hi-16-os-privilege.sh" || fail "sh -n hi-16-os-privilege.sh"
sh -n "${ISO_POLICY}/work-slice.sh" || fail "sh -n ISO work-slice.sh"
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

grep -Fq 'payload/profile/airootfs/etc/systemd/system/aios-work.slice' "${HASHES}" \
  || fail "payload/hashes.txt must pin aios-work.slice"
grep -Fq 'aios-work-.service.d/10-floor.conf' "${HASHES}" \
  || fail "payload/hashes.txt must pin floor drop-in"
grep -Fq 'usr/lib/systemd/user/aios-work-runtime.service' "${HASHES}" \
  || fail "payload/hashes.txt must pin aios-work-runtime user unit"
grep -Fq '/etc/systemd/system/aios-work.slice' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin aios-work.slice"
grep -Fq '/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin floor drop-in"
grep -Fq '/usr/lib/systemd/user/aios-work-runtime.service' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin aios-work-runtime user unit"

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
if [ "${LIVE_LINGER_BEFORE}" -eq 0 ] \
  && [ -e /var/lib/systemd/linger/aios-work ]; then
  fail "oracle wrote live linger/aios-work"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p6-work-slice failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p6-work-slice\n'
exit 0
