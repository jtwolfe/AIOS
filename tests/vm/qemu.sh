#!/bin/sh
# QEMU floor: OVMF pflash, serial stdio, fw_cfg auto on the live ISO.
# Fail closed if KVM or firmware is missing. Does not build the ISO.
# Host greps (tests/oracles/p9-vm-harness.sh) do not require a built image.
#
# Usage: tests/vm/qemu.sh [probe|iso|disk|snap]
#   probe  (default)  require KVM+OVMF, print floor invocations, exit 0
#   iso               boot live ISO (needs dist/aios-*.iso)
#   disk              boot installed disk (needs work/aios.qcow2 + OVMF_VARS)
#   snap [name]       persistent qcow2 snapshot (default: pre). recover reboots
#                     this disk, so this is not a throwaway overlay.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
WORK="${ROOT}/work"
DIST="${ROOT}/dist"
OVMF_CODE=
OVMF_VARS_TEMPLATE=

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

try_pair() {
  if [ -r "$1" ] && [ -r "$2" ]; then
    OVMF_CODE=$1
    OVMF_VARS_TEMPLATE=$2
    return 0
  fi
  return 1
}

find_ovmf() {
  # First match wins (design-plan P1 QEMU).
  try_pair /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd \
    && return 0
  try_pair /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
    && return 0
  try_pair /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd \
    && return 0
  try_pair /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_VARS.fd \
    && return 0
  try_pair /usr/share/OVMF/x64/OVMF_CODE.4m.fd /usr/share/OVMF/x64/OVMF_VARS.4m.fd \
    && return 0
  die "OVMF firmware missing (need CODE+VARS under /usr/share/edk2, edk2-ovmf, or OVMF)"
}

require_kvm() {
  [ -c /dev/kvm ] || die "KVM missing (/dev/kvm); fail closed"
  [ -r /dev/kvm ] || die "KVM not readable (/dev/kvm)"
}

print_floor() {
  cat <<EOF
# Live ISO (firstboot). OVMF so bootctl in arch-chroot can write EFI vars.
# fw_cfg auto is tests/vm only; public ISO loader entries omit it.
qemu-system-x86_64 \\
  -machine q35,accel=kvm \\
  -cpu host \\
  -m 4096 \\
  -smp 2 \\
  -drive if=pflash,format=raw,readonly=on,file=${OVMF_CODE} \\
  -drive if=pflash,format=raw,file=${WORK}/OVMF_VARS.fd \\
  -drive file=${WORK}/aios.qcow2,if=virtio,format=qcow2 \\
  -cdrom dist/aios-*.iso \\
  -netdev user,id=n0 \\
  -device virtio-net-pci,netdev=n0 \\
  -fw_cfg name=opt/org.aios/firstboot,string=auto \\
  -fw_cfg name=opt/org.aios/console,string=serial \\
  -serial stdio \\
  -display none \\
  -no-reboot

# Disk boot (installer stub). No -cdrom. No firstboot fw_cfg.
# Serial TUI: firstboot set-default aios-linux-serial.conf from console=serial.
qemu-system-x86_64 \\
  -machine q35,accel=kvm \\
  -cpu host \\
  -m 4096 \\
  -smp 2 \\
  -drive if=pflash,format=raw,readonly=on,file=${OVMF_CODE} \\
  -drive if=pflash,format=raw,file=${WORK}/OVMF_VARS.fd \\
  -drive file=${WORK}/aios.qcow2,if=virtio,format=qcow2 \\
  -netdev user,id=n0 \\
  -device virtio-net-pci,netdev=n0 \\
  -serial stdio \\
  -display none

# Persistent qcow2 snapshot after firstboot. recover reboots this disk.
qemu-img snapshot -c pre ${WORK}/aios.qcow2
EOF
}

find_iso() {
  _iso=
  _n=0
  for _f in "${DIST}"/aios-*.iso; do
    [ -f "${_f}" ] || continue
    _iso=${_f}
    _n=$((_n + 1))
  done
  [ "${_n}" -gt 0 ] || die "no dist/aios-*.iso (payload/build.sh; not required for host greps)"
  [ "${_n}" -eq 1 ] || die "multiple dist/aios-*.iso; leave one"
  printf '%s\n' "${_iso}"
}

require_qemu() {
  command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 missing"
}

ensure_qcow() {
  mkdir -p "${WORK}"
  if [ ! -f "${WORK}/aios.qcow2" ]; then
    command -v qemu-img >/dev/null 2>&1 || die "qemu-img missing"
    qemu-img create -f qcow2 "${WORK}/aios.qcow2" 32G >/dev/null
  fi
}

snap_disk() {
  _name=$1
  case "${_name}" in
    ''|*/*|*'..'*) die "invalid snapshot name" ;;
  esac
  [ -f "${WORK}/aios.qcow2" ] || die "missing ${WORK}/aios.qcow2"
  command -v qemu-img >/dev/null 2>&1 || die "qemu-img missing"
  qemu-img snapshot -c "${_name}" "${WORK}/aios.qcow2" \
    || die "qemu-img snapshot -c ${_name} failed"
}

mode=${1:-probe}

case "${mode}" in
  probe)
    require_kvm
    find_ovmf
    print_floor
    ;;
  -h|--help)
    printf 'usage: %s [probe|iso|disk|snap]\n' "$0"
    ;;
  iso)
    require_kvm
    find_ovmf
    require_qemu
    ISO=$(find_iso)
    ensure_qcow
    cp "${OVMF_VARS_TEMPLATE}" "${WORK}/OVMF_VARS.fd"
    exec qemu-system-x86_64 \
      -machine q35,accel=kvm \
      -cpu host \
      -m 4096 \
      -smp 2 \
      -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
      -drive if=pflash,format=raw,file="${WORK}/OVMF_VARS.fd" \
      -drive file="${WORK}/aios.qcow2",if=virtio,format=qcow2 \
      -cdrom "${ISO}" \
      -netdev user,id=n0 \
      -device virtio-net-pci,netdev=n0 \
      -fw_cfg name=opt/org.aios/firstboot,string=auto \
      -fw_cfg name=opt/org.aios/console,string=serial \
      -serial stdio \
      -display none \
      -no-reboot
    ;;
  disk)
    require_kvm
    find_ovmf
    require_qemu
    [ -f "${WORK}/aios.qcow2" ] || die "missing ${WORK}/aios.qcow2"
    [ -f "${WORK}/OVMF_VARS.fd" ] || die "missing ${WORK}/OVMF_VARS.fd (run iso first)"
    exec qemu-system-x86_64 \
      -machine q35,accel=kvm \
      -cpu host \
      -m 4096 \
      -smp 2 \
      -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
      -drive if=pflash,format=raw,file="${WORK}/OVMF_VARS.fd" \
      -drive file="${WORK}/aios.qcow2",if=virtio,format=qcow2 \
      -netdev user,id=n0 \
      -device virtio-net-pci,netdev=n0 \
      -serial stdio \
      -display none
    ;;
  snap)
    snap_disk "${2:-pre}"
    ;;
  *)
    die "usage: $0 [probe|iso|disk|snap]"
    ;;
esac
