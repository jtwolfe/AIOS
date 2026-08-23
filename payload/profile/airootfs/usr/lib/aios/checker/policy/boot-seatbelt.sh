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

MAP=/srv/aios/state/esp-generations
GENROOT=/boot/aios-gen

command -v pacman >/dev/null 2>&1 || fail "pacman missing"
pacman -Q linux >/dev/null 2>&1 || fail "linux is not installed"
pacman -Q linux-lts >/dev/null 2>&1 || fail "linux-lts is not installed"
pacman -Q snap-pac >/dev/null 2>&1 || fail "snap-pac is not installed"
pacman -Q kernel-modules-hook >/dev/null 2>&1 || fail "kernel-modules-hook is not installed"

need_file /boot/vmlinuz-linux
need_file /boot/vmlinuz-linux-lts
need_file /boot/initramfs-linux.img
need_file /boot/initramfs-linux-lts.img
need_file /boot/loader/entries/aios-linux.conf
need_file /boot/loader/entries/aios-linux-lts.conf
grep -q vmlinuz-linux /boot/loader/entries/aios-linux.conf \
  || fail "aios-linux.conf does not point at linux"
grep -q vmlinuz-linux-lts /boot/loader/entries/aios-linux-lts.conf \
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

if command -v bootctl >/dev/null 2>&1; then
  LIST=$(bootctl list 2>/dev/null || true)
  if [ -n "${LIST}" ]; then
    printf '%s\n' "${LIST}" | grep -Fq 'aios-linux.conf' \
      || fail "bootctl list does not show linux"
    printf '%s\n' "${LIST}" | grep -Fq 'aios-linux-lts.conf' \
      || fail "bootctl list does not show linux-lts"
    if [ "${N}" -ge 2 ]; then
      printf '%s\n' "${LIST}" | grep -Fq 'aios-prev.conf' \
        || fail "bootctl list does not show previous after a second generation exists"
    fi
  fi
fi

# If this uid can list snapper, the last pre/post or single window must match the map.
# Timeline snapshots are not ESP keys (L-19).
if command -v snapper >/dev/null 2>&1; then
  SNAP=$(snapper --no-dbus -c root list 2>/dev/null || true)
  if [ -n "${SNAP}" ]; then
    LASTWIN=$(
      printf '%s\n' "${SNAP}" | awk -F'|' '
        /^[[:space:]]*[0-9]+/ {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
          n=$1
          if (n+0 == 0) next
          type=$2
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", type)
          if (type == "timeline" || type == "number") next
          last=n
          lasttype=type
        }
        END { if (last != "") print last, lasttype }
      '
    )
    if [ -n "${LASTWIN}" ]; then
      WID=${LASTWIN%% *}
      WTYPE=${LASTWIN#* }
      if [ "${WTYPE}" = pre ]; then
        fail "incomplete snapper pre ${WID} has no matching ESP generation"
      fi
      [ "${WID}" = "${ID}" ] \
        || fail "last snapper window ${WID} (${WTYPE}) != esp-generations ${ID}"
    fi
  fi
fi

exit 0
