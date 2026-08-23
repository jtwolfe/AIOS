#!/bin/sh
# HI-06 / L-19: snapper-alone on this layout is a false seatbelt (ESP is not in @).
set -eu

fail() {
  printf 'boot-seatbelt: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [ -s "$1" ] || fail "missing or empty $1"
}

# Privileged id is the last esp-generations row (firstboot single / last enact post).
# snapper list must still contain that id; timeline singles may be newer (HI-06).
# aios-checker is not root; sudoers names this exact command. Not 750 /.snapshots.
snapper_has_id() {
  _want=$1
  SNAP=
  command -v snapper >/dev/null 2>&1 || fail "snapper binary missing"
  if SNAP=$(snapper --no-dbus -c root list 2>/dev/null) && [ -n "${SNAP}" ]; then
    :
  elif command -v sudo >/dev/null 2>&1 \
    && SNAP=$(sudo -n /usr/bin/snapper --no-dbus -c root list 2>/dev/null) \
    && [ -n "${SNAP}" ]; then
    :
  else
    fail "cannot list snapper windows as this uid"
  fi
  _found=$(
    printf '%s\n' "${SNAP}" | awk -F'|' -v want="${_want}" '
      /^[[:space:]]*[0-9]/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
        gsub(/[-+*]$/, "", $1)
        if ($1+0 == want+0 && want+0 > 0) { print 1; found=1; exit }
      }
      END { if (!found) print 0 }
    '
  )
  [ "${_found}" = 1 ] \
    || fail "snapper list does not contain privileged id ${_want}"
}

MAP=/srv/aios/state/esp-generations
GENROOT=/boot/aios-gen

command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Q linux >/dev/null 2>&1 || fail "linux is not installed"
pacman -Q linux-lts >/dev/null 2>&1 || fail "linux-lts is not installed"
pacman -Q snap-pac >/dev/null 2>&1 || fail "snap-pac is not installed"
pacman -Q kernel-modules-hook >/dev/null 2>&1 || fail "kernel-modules-hook is not installed"

command -v mountpoint >/dev/null 2>&1 || fail "mountpoint missing"
mountpoint -q /boot \
  || fail "/boot is not a mount (ESP generations on @ are a false seatbelt)"
if command -v findmnt >/dev/null 2>&1; then
  _fstype=$(findmnt -n -o FSTYPE /boot) || fail "cannot read /boot fstype"
  [ "${_fstype}" != btrfs ] \
    || fail "/boot is btrfs; ESP is not in @ (HI-06)"
fi

need_file /boot/vmlinuz-linux
need_file /boot/vmlinuz-linux-lts
need_file /boot/initramfs-linux.img
need_file /boot/initramfs-linux-lts.img
need_file /boot/loader/entries/aios-linux.conf
need_file /boot/loader/entries/aios-linux-lts.conf
# vmlinuz-linux is a prefix of vmlinuz-linux-lts; require the field, not a substring.
grep -Eq '^linux[[:space:]]+/vmlinuz-linux$' /boot/loader/entries/aios-linux.conf \
  || fail "aios-linux.conf does not point at linux"
grep -Eq '^linux[[:space:]]+/vmlinuz-linux-lts$' /boot/loader/entries/aios-linux-lts.conf \
  || fail "aios-linux-lts.conf does not point at linux-lts"

KVER=$(uname -r)
[ -n "${KVER}" ] || fail "uname -r is empty"
[ -d "/usr/lib/modules/${KVER}" ] || fail "modules dir missing for running kernel ${KVER}"
if [ ! -f "/usr/lib/modules/${KVER}/modules.dep" ] \
  && [ ! -d "/usr/lib/modules/${KVER}/kernel" ]; then
  fail "running kernel ${KVER} has no modules.dep or kernel/ tree"
fi

[ -f "${MAP}" ] || fail "missing ${MAP}"
# Last non-comment map line is the current window; keyed by snapper id, not a timestamp.
LAST=$(grep -v '^[[:space:]]*#' "${MAP}" | grep -v '^[[:space:]]*$' | tail -n 1 || true)
[ -n "${LAST}" ] || fail "${MAP} has no generations"
ID=${LAST%% *}
DIR=${LAST#* }
[ -n "${ID}" ] && [ -n "${DIR}" ] && [ "${ID}" != "${LAST}" ] \
  || fail "malformed esp-generations line: ${LAST}"
case "${ID}" in
  ''|*[!0-9]*) fail "esp-generations id is not numeric: ${ID}" ;;
esac
[ "${ID}" -gt 0 ] || fail "esp-generations id must be > 0"
[ "${DIR}" = "/boot/aios-gen/${ID}" ] || fail "esp-generations path ${DIR} != /boot/aios-gen/${ID}"

need_file "${GENROOT}/${ID}/vmlinuz-linux"
need_file "${GENROOT}/${ID}/vmlinuz-linux-lts"
need_file "${GENROOT}/${ID}/initramfs-linux.img"
need_file "${GENROOT}/${ID}/initramfs-linux-lts.img"

N=0
for _d in "${GENROOT}"/*; do
  [ -d "${_d}" ] || continue
  N=$((N + 1))
done
[ "${N}" -ge 1 ] || fail "no /boot/aios-gen/<id>/ directories"
# Retention is current + previous successful post once a previous exists.
[ "${N}" -le 2 ] || fail "too many ESP generations (${N}); keep N=2 (HI-06)"

MAPN=$(grep -v '^[[:space:]]*#' "${MAP}" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
[ "${MAPN}" = "${N}" ] || fail "esp-generations has ${MAPN} rows but ${N} aios-gen dirs"

PREV=/boot/loader/entries/aios-prev.conf
if [ "${N}" -ge 2 ]; then
  need_file "${PREV}"
else
  [ ! -e "${PREV}" ] || fail "aios-prev.conf must be absent until a second generation exists"
fi

command -v bootctl >/dev/null 2>&1 || fail "bootctl missing"
LIST=$(bootctl list 2>/dev/null) || fail "bootctl list failed"
[ -n "${LIST}" ] || fail "bootctl list is empty"
printf '%s\n' "${LIST}" | grep -Fq 'aios-linux.conf' \
  || fail "bootctl list does not show linux"
printf '%s\n' "${LIST}" | grep -Fq 'aios-linux-lts.conf' \
  || fail "bootctl list does not show linux-lts"
if [ "${N}" -ge 2 ]; then
  printf '%s\n' "${LIST}" | grep -Fq 'aios-prev.conf' \
    || fail "bootctl list does not show previous after a second generation exists"
fi

# Membership, not last-row: hourly Type=single timeline snapshots are newer.
snapper_has_id "${ID}"

exit 0
