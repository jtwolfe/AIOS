#!/usr/bin/env bash
# Build the AIOS live ISO from payload/profile with a pinned Arch bootstrap.
# Harness A: no sysupgrade in this script. Fail closed on pin mismatch.
set -euo pipefail
umask 022

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
PROFILE="${SCRIPT_DIR}/profile"
DIST="${REPO_ROOT}/dist"
WORK="${REPO_ROOT}/work"
CACHE="${WORK}/cache"

# Dated Archive bootstrap; do not substitute an undated alias.
BOOTSTRAP_VERSION="2026.08.01"
BOOTSTRAP_FILENAME="archlinux-bootstrap-${BOOTSTRAP_VERSION}-x86_64.tar.zst"
BOOTSTRAP_URL="https://archive.archlinux.org/iso/${BOOTSTRAP_VERSION}/${BOOTSTRAP_FILENAME}"
BOOTSTRAP_SHA256="9600cef264af08899eff8f8b9bb2dd141c748a0038b651256d335e489a8dd2f6"
SHA256SUMS_URL="https://archive.archlinux.org/iso/${BOOTSTRAP_VERSION}/sha256sums.txt"
BOOTSTRAP_SIG_URL="${BOOTSTRAP_URL}.sig"
# Matching repo freeze so package fetch is not a rolling mirror.
ARCHIVE_REPO='https://archive.archlinux.org/repos/2026/08/01/$repo/os/$arch'

PACSTRAP_LOCK=(
  base
  linux
  linux-lts
  linux-firmware
  btrfs-progs
  snapper
  snap-pac
  kernel-modules-hook
  git
  python
  pacman
  systemd
  etckeeper
  minisign
  iwd
  sudo
  openssh
  zram-generator
)

BOOTSTRAP_ROOT=""
MOUNTED_REPO=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Mount targets under dir, deepest first. Empty if dir is missing.
mounts_under() {
  local dir="${1%/}" t depth targets
  [[ -d "${dir}" ]] || return 0
  command -v findmnt >/dev/null 2>&1 || die "need findmnt (util-linux)"
  targets=$(findmnt --list -n -o TARGET) || die "findmnt --list failed"
  while IFS= read -r t; do
    [[ -z "${t}" ]] && continue
    case "${t}" in
      "${dir}"|"${dir}"/*)
        depth=${t//[^\/]/}
        printf '%s\t%s\n' "${#depth}" "${t}"
        ;;
    esac
  done <<< "${targets}" | sort -k1,1nr | cut -f2-
}

# Unmount every mount under dir (proc/sys/dev/run, repo bind, mkarchiso). Busy umount dies.
unmount_under() {
  local dir="$1" t list
  [[ -d "${dir}" ]] || return 0
  list=$(mounts_under "${dir}") || die "could not list mounts under ${dir}"
  while IFS= read -r t; do
    [[ -z "${t}" ]] && continue
    umount "${t}" || die "busy umount: ${t}"
  done <<< "${list}"
}

cleanup() {
  local leftover
  trap - EXIT
  # arch-chroot leftovers (proc/sys/dev/run) and the repo bind, deepest first.
  unmount_under "${WORK}/mkarchiso"
  unmount_under "${WORK}/bootstrap"
  leftover=$(mounts_under "${WORK}/bootstrap") || die "could not list mounts under ${WORK}/bootstrap"
  if [[ -n "${leftover}" ]]; then
    die "still mounted under ${WORK}/bootstrap after cleanup:"$'\n'"${leftover}"
  fi
  leftover=$(mounts_under "${WORK}/mkarchiso") || die "could not list mounts under ${WORK}/mkarchiso"
  if [[ -n "${leftover}" ]]; then
    die "still mounted under ${WORK}/mkarchiso after cleanup:"$'\n'"${leftover}"
  fi
}
trap cleanup EXIT

fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "${dest}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${dest}" "${url}"
  else
    die "need curl or wget to fetch ${url}"
  fi
}

hash_ok() {
  local hash="$1" file="$2"
  printf '%s  %s\n' "${hash}" "${file}" | sha256sum -c --status -
}

check_package_lists() {
  local pac
  [[ -f "${PROFILE}/packages.x86_64" ]] || die "missing ${PROFILE}/packages.x86_64"
  [[ -f "${PROFILE}/pacstrap.x86_64" ]] || die "missing ${PROFILE}/pacstrap.x86_64"
  [[ -f "${PROFILE}/profiledef.sh" ]] || die "missing ${PROFILE}/profiledef.sh"
  if grep -qEi '^(hyprland|gnome|plasma|sddm|gdm)$' "${PROFILE}/packages.x86_64" "${PROFILE}/pacstrap.x86_64"; then
    die "DE/display-manager name in package lists"
  fi
  if grep -qEi '^(yay|paru)$' "${PROFILE}/packages.x86_64" "${PROFILE}/pacstrap.x86_64"; then
    die "AUR helper in package lists"
  fi
  cmp -s "${PROFILE}/pacstrap.x86_64" <(printf '%s\n' "${PACSTRAP_LOCK[@]}") \
    || die "pacstrap.x86_64 is not the locked 18-name set"
  while read -r pac; do
    [[ -z "${pac}" || "${pac}" == \#* ]] && continue
    grep -qx "${pac}" "${PROFILE}/packages.x86_64" || die "${pac} in pacstrap.x86_64 is not in packages.x86_64"
  done < "${PROFILE}/pacstrap.x86_64"
  cmp -s "${PROFILE}/pacstrap.x86_64" "${PROFILE}/airootfs/usr/lib/aios/pacstrap.x86_64" \
    || die "airootfs pacstrap.x86_64 is not the same bytes as profile/pacstrap.x86_64"
}

verify_pin() {
  mkdir -p "${CACHE}"
  local sums="${CACHE}/sha256sums-${BOOTSTRAP_VERSION}.txt"
  local tarball="${CACHE}/${BOOTSTRAP_FILENAME}"
  local listed gpg_rc

  fetch "${SHA256SUMS_URL}" "${sums}"
  listed=$(awk -v f="${BOOTSTRAP_FILENAME}" '$2 == f { print $1; exit }' "${sums}")
  [[ -n "${listed}" ]] || die "${BOOTSTRAP_FILENAME} not listed in ${SHA256SUMS_URL}"
  [[ "${listed}" == "${BOOTSTRAP_SHA256}" ]] || die "pin ${BOOTSTRAP_SHA256} != sha256sums.txt ${listed}"

  if [[ ! -f "${tarball}" ]] || ! hash_ok "${BOOTSTRAP_SHA256}" "${tarball}"; then
    fetch "${BOOTSTRAP_URL}" "${tarball}"
  fi
  hash_ok "${BOOTSTRAP_SHA256}" "${tarball}" || die "bootstrap sha256 mismatch after fetch"
  printf '%s  %s\n' "${BOOTSTRAP_SHA256}" "${tarball}" | sha256sum -c -

  if command -v gpg >/dev/null 2>&1; then
    if fetch "${BOOTSTRAP_SIG_URL}" "${tarball}.sig"; then
      gpg_rc=0
      gpg --verify "${tarball}.sig" "${tarball}" >/dev/null 2>&1 || gpg_rc=$?
      if [[ "${gpg_rc}" -eq 0 ]]; then
        printf 'pgp: Arch signature accepted for %s\n' "${BOOTSTRAP_FILENAME}"
      elif [[ "${gpg_rc}" -eq 2 ]]; then
        printf 'pgp: Arch signing key not in this keyring; sha256 pin still binds\n' >&2
      else
        die "pgp: bad Arch signature for ${BOOTSTRAP_FILENAME} (gpg exit ${gpg_rc})"
      fi
    fi
  fi
}

prepare_chroot() {
  local tarball="${CACHE}/${BOOTSTRAP_FILENAME}"
  local parent="${WORK}/bootstrap"
  local leftover
  [[ "${EUID}" -eq 0 ]] || die "mkarchiso needs root (bootstrap pin already verified)"
  command -v findmnt >/dev/null 2>&1 || die "need findmnt (util-linux)"

  if [[ -d "${parent}" ]]; then
    leftover=$(mounts_under "${parent}") || die "could not list mounts under ${parent}"
    if [[ -n "${leftover}" ]]; then
      die "refusing to rm -rf ${parent}: still mounted:"$'\n'"${leftover}"
    fi
  fi
  rm -rf "${parent}"
  mkdir -p "${parent}"
  tar -C "${parent}" -xf "${tarball}" --numeric-owner
  [[ -d "${parent}/root.x86_64" ]] || die "unexpected bootstrap layout (wanted root.x86_64)"
  BOOTSTRAP_ROOT="${parent}/root.x86_64"

  printf 'Server = %s\n' "${ARCHIVE_REPO}" > "${BOOTSTRAP_ROOT}/etc/pacman.d/mirrorlist"
  if [[ -e /etc/resolv.conf ]]; then
    rm -f "${BOOTSTRAP_ROOT}/etc/resolv.conf"
    cp -L /etc/resolv.conf "${BOOTSTRAP_ROOT}/etc/resolv.conf"
  fi

  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman-key --init
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman-key --populate archlinux
  # Frozen archive + bootstrap db: install only, no sysupgrade.
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman -S --noconfirm --needed archiso
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" command -v mkarchiso >/dev/null \
    || die "mkarchiso missing after installing archiso in the bootstrap chroot"

  mkdir -p "${BOOTSTRAP_ROOT}/mnt/aios" "${DIST}"
  mount --bind "${REPO_ROOT}" "${BOOTSTRAP_ROOT}/mnt/aios"
  MOUNTED_REPO="${BOOTSTRAP_ROOT}/mnt/aios"
}

run_mkarchiso() {
  local epoch leftover
  epoch=$(date -u -d "${BOOTSTRAP_VERSION//./-}" +%s) || epoch=""
  mkdir -p "${DIST}"
  # Fresh -w each run so leftover _run_once stamps cannot skip pacstrap.
  if [[ -d "${WORK}/mkarchiso" ]]; then
    unmount_under "${WORK}/mkarchiso"
    leftover=$(mounts_under "${WORK}/mkarchiso") || die "could not list mounts under ${WORK}/mkarchiso"
    if [[ -n "${leftover}" ]]; then
      die "refusing to rm -rf ${WORK}/mkarchiso: still mounted:"$'\n'"${leftover}"
    fi
  fi
  rm -rf "${WORK}/mkarchiso"
  mkdir -p "${WORK}/mkarchiso"
  if [[ -n "${epoch}" ]]; then
    SOURCE_DATE_EPOCH="${epoch}" \
      "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" \
      env SOURCE_DATE_EPOCH="${epoch}" \
      mkarchiso -v -r -w /mnt/aios/work/mkarchiso -o /mnt/aios/dist /mnt/aios/payload/profile
  else
    "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" \
      mkarchiso -v -r -w /mnt/aios/work/mkarchiso -o /mnt/aios/dist /mnt/aios/payload/profile
  fi
}

check_package_lists
verify_pin
prepare_chroot
run_mkarchiso

shopt -s nullglob
isos=("${DIST}"/aios-*.iso)
[[ ${#isos[@]} -ge 1 ]] || die "mkarchiso finished but ${DIST}/aios-*.iso is missing"
printf 'built %s\n' "${isos[@]}"
