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
SECKEY_BIND=""
PUBLISH=0
PUBKEY="${SCRIPT_DIR}/minisign.pub"
HASHES="${SCRIPT_DIR}/hashes.txt"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: payload/build.sh [--publish]
  --publish  fail closed unless every dist/aios-*.iso has a minisign signature (L-10)
EOF
}

# sudo keeps the operator home so the secret key is not looked up as root.
operator_home() {
  local user="${SUDO_USER:-}" home
  if [[ -n "${user}" && "${user}" != root ]]; then
    home=$(getent passwd "${user}" | cut -d: -f6 || true)
    [[ -n "${home}" && -d "${home}" ]] || die "cannot resolve home for SUDO_USER"
    printf '%s\n' "${home}"
    return
  fi
  printf '%s\n' "${HOME}"
}

# XDG under sudo is root's or empty; only honor it if it is under the operator home.
operator_config_home() {
  local home xdg
  home=$(operator_home)
  xdg="${XDG_CONFIG_HOME:-}"
  if [[ -n "${xdg}" ]]; then
    case "${xdg}" in
      "${home}"|"${home}"/*)
        printf '%s\n' "${xdg}"
        return
        ;;
    esac
  fi
  printf '%s\n' "${home}/.config"
}

# Secret key is operator-local; never under payload/.
resolve_seckey() {
  local home cfg key
  if [[ -n "${AIOS_MINISIGN_SECKEY:-}" ]]; then
    printf '%s\n' "${AIOS_MINISIGN_SECKEY}"
    return
  fi
  home=$(operator_home)
  cfg=$(operator_config_home)
  for key in \
    "${cfg}/aios/minisign.key" \
    "${home}/.minisign/minisign.key"
  do
    if [[ -f "${key}" ]]; then
      printf '%s\n' "${key}"
      return
    fi
  done
  printf '%s\n' "${cfg}/aios/minisign.key"
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
  # arch-chroot leftovers (proc/sys/dev/run), seckey bind, and the repo bind, deepest first.
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
  if [[ -n "${SECKEY_BIND}" ]]; then
    rm -f "${SECKEY_BIND}"
    SECKEY_BIND=""
  fi
}

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

# Live ISO pubkey must match the repo trust anchor (hashes.txt on the ISO is a live-path list).
sync_iso_pubkey() {
  local dest="${PROFILE}/airootfs/usr/lib/aios/minisign.pub"
  mkdir -p "${PROFILE}/airootfs/usr/lib/aios"
  if [[ ! -f "${dest}" ]] || ! cmp -s "${PUBKEY}" "${dest}"; then
    cp -a "${PUBKEY}" "${dest}"
  fi
}

check_hashes() {
  local lines path base pin rel
  [[ -f "${HASHES}" ]] || die "missing ${HASHES}"
  [[ -f "${PUBKEY}" ]] || die "missing ${PUBKEY}"
  lines=$(grep -E '^[0-9a-f]{64} ' "${HASHES}" || true)
  [[ -n "${lines}" ]] || die "${HASHES} has no sha256 lines"
  grep -Eq '^[0-9a-f]{64}  .+/pacstrap\.x86_64$' "${HASHES}" \
    || die "${HASHES} must pin pacstrap.x86_64"
  for pin in \
    'payload/profile/airootfs/usr/lib/aios/bin/firstboot$' \
    'payload/profile/airootfs/usr/lib/aios/bin/installer$' \
    'payload/profile/airootfs/usr/lib/aios/bin/enact$' \
    'payload/profile/airootfs/usr/lib/aios/bin/aios$' \
    'payload/profile/airootfs/usr/lib/sysusers.d/aios.conf$' \
    'payload/profile/airootfs/usr/lib/tmpfiles.d/aios.conf$' \
    'payload/profile/airootfs/etc/systemd/system/aios-installer.service$' \
    'payload/profile/airootfs/etc/systemd/system/aios-checker.service$' \
    'payload/profile/airootfs/etc/systemd/system/aios-agent.service$' \
    'payload/profile/airootfs/etc/systemd/system/aios-intent.socket$' \
    'payload/profile/airootfs/etc/sudoers.d/aios-checker-snapper$' \
    'payload/profile/airootfs/etc/sudoers.d/aios-agent-enact$' \
    'payload/profile/airootfs/usr/lib/aios/hard-invariants.md$' \
    'payload/profile/airootfs/usr/lib/aios/minisign.pub$' \
    'payload/profile/airootfs/usr/lib/aios/hashes.txt$' \
    'getty@tty1.service.d/autologin.conf$' \
    'serial-getty@ttyS0.service.d/autologin.conf$' \
    'payload/profile/airootfs/srv/aios/seeds/work-runtime/' \
    'payload/profile/airootfs/srv/aios/seeds/work-runtime-bots/'
  do
    grep -Eq "^[0-9a-f]{64}  .*${pin}" "${HASHES}" \
      || die "${HASHES} must pin ${pin}"
  done
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    grep -Eq "^[0-9a-f]{64}  ${rel}$" "${HASHES}" \
      || die "${HASHES} must pin ${rel}"
  done < <(cd "${REPO_ROOT}" && find \
      seed/work-runtime seed/work-runtime-bots \
      payload/profile/airootfs/srv/aios/seeds \
      checker \
      payload/profile/airootfs/usr/lib/aios/checker \
      agent \
      payload/profile/airootfs/usr/lib/aios/agent \
      intent \
      payload/profile/airootfs/usr/lib/aios/intent \
      installer \
      payload/profile/airootfs/usr/lib/aios/installer \
      operator-client \
      payload/profile/airootfs/usr/lib/aios/operator-client \
      -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sort)
  while read -r path; do
    [[ -z "${path}" ]] && continue
    path="${path#\*}"
    base="${path##*/}"
    case "${base}" in
      minisign.key|*.minisign.key)
        die "${HASHES} lists a secret key path"
        ;;
    esac
  done < <(awk '/^[0-9a-f]{64} / { print $2 }' "${HASHES}")
  (cd "${REPO_ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict -) \
    || die "${HASHES} mismatch"
}

ensure_chroot_minisign() {
  [[ -n "${BOOTSTRAP_ROOT}" && -x "${BOOTSTRAP_ROOT}/bin/arch-chroot" ]] \
    || die "bootstrap chroot missing; cannot sign"
  # Same-day Archive freeze as the bootstrap tarball.
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman -Syu --noconfirm --needed minisign
  [[ -x "${BOOTSTRAP_ROOT}/usr/bin/minisign" ]] \
    || die "minisign missing after installing in the bootstrap chroot"
}

run_minisign() {
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" minisign "$@"
}

iso_in_chroot() {
  local iso="$1" rel
  rel="${iso#"${REPO_ROOT}/"}"
  [[ "${iso}" == "${REPO_ROOT}/${rel}" ]] || die "ISO is not under the repository: ${iso}"
  printf '%s\n' "/mnt/aios/${rel}"
}

bind_seckey() {
  local seckey="$1"
  [[ -n "${BOOTSTRAP_ROOT}" && -d "${BOOTSTRAP_ROOT}" ]] || die "bootstrap chroot missing; cannot bind secret key"
  mkdir -p "${BOOTSTRAP_ROOT}/root"
  SECKEY_BIND="${BOOTSTRAP_ROOT}/root/aios-minisign.key"
  rm -f "${SECKEY_BIND}"
  touch "${SECKEY_BIND}"
  chmod 600 "${SECKEY_BIND}"
  mount --bind "${seckey}" "${SECKEY_BIND}" || die "could not bind-mount minisign secret key"
}

unbind_seckey() {
  if [[ -n "${SECKEY_BIND}" ]]; then
    if findmnt -M "${SECKEY_BIND}" >/dev/null 2>&1; then
      umount "${SECKEY_BIND}" || die "busy umount: ${SECKEY_BIND}"
    fi
    rm -f "${SECKEY_BIND}"
    SECKEY_BIND=""
  fi
}

sign_isos() {
  local iso seckey rc payload_real seckey_real chroot_iso
  seckey=$(resolve_seckey)
  payload_real=$(realpath "${SCRIPT_DIR}")
  if [[ -e "${seckey}" ]]; then
    seckey_real=$(realpath "${seckey}")
    case "${seckey_real}" in
      "${payload_real}"|"${payload_real}"/*)
        die "minisign secret key must not live under payload/"
        ;;
    esac
    if git -C "${REPO_ROOT}" ls-files --error-unmatch -- "${seckey}" >/dev/null 2>&1; then
      die "minisign secret key is tracked in git"
    fi
  fi

  if [[ ! -f "${seckey}" ]]; then
    if [[ "${PUBLISH}" -eq 1 ]]; then
      die "publish refused: minisign secret key missing (${seckey}); unsigned images must not leave the workstation (L-10)"
    fi
    for iso in "${isos[@]}"; do
      printf 'unsigned: %s (no secret key; must not leave this workstation)\n' "${iso}" >&2
    done
    return 0
  fi

  [[ -f "${PUBKEY}" ]] || die "missing ${PUBKEY}"
  ensure_chroot_minisign
  bind_seckey "${seckey}"

  for iso in "${isos[@]}"; do
    chroot_iso=$(iso_in_chroot "${iso}")
    run_minisign -S -s /root/aios-minisign.key -m "${chroot_iso}" \
      || die "minisign sign failed for ${iso}"
    if [[ ! -f "${iso}.minisig" ]]; then
      die "minisign: missing signature ${iso}.minisig after sign"
    fi
    rc=0
    run_minisign -Vm "${chroot_iso}" -p /mnt/aios/payload/minisign.pub >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
      die "minisign: bad signature for ${iso} (exit ${rc})"
    fi
    printf 'signed %s\n' "${iso}"
  done
  unbind_seckey
}

assert_published_signed() {
  local iso rc chroot_iso
  [[ "${PUBLISH}" -eq 1 ]] || return 0
  ensure_chroot_minisign
  for iso in "${isos[@]}"; do
    if [[ ! -f "${iso}.minisig" ]]; then
      die "publish refused: missing ${iso}.minisig; unsigned images must not leave the workstation (L-10)"
    fi
    chroot_iso=$(iso_in_chroot "${iso}")
    rc=0
    run_minisign -Vm "${chroot_iso}" -p /mnt/aios/payload/minisign.pub >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
      die "publish refused: bad minisign signature for ${iso} (exit ${rc}) (L-10)"
    fi
  done
}

check_firstboot_payload() {
  local iso="${PROFILE}/airootfs"
  [[ -x "${iso}/usr/lib/aios/bin/firstboot" ]] || die "missing executable firstboot"
  [[ -x "${iso}/usr/lib/aios/bin/installer" ]] || die "missing executable installer"
  [[ -x "${iso}/usr/lib/aios/bin/enact" ]] || die "missing executable enact"
  [[ -x "${iso}/usr/lib/aios/bin/aios" ]] || die "missing executable aios"
  [[ -f "${iso}/usr/lib/aios/operator-client/tty/aios.py" ]] \
    || die "missing operator-client/tty/aios.py"
  [[ -f "${iso}/etc/systemd/system/aios-installer.service" ]] || die "missing aios-installer.service"
  [[ ! -e "${iso}/etc/systemd/system/multi-user.target.wants/aios-installer.service" ]] \
    || die "aios-installer.service must not be enabled on the live ISO"
  [[ -f "${iso}/etc/systemd/system/aios-checker.service" ]] || die "missing aios-checker.service"
  [[ ! -e "${iso}/etc/systemd/system/multi-user.target.wants/aios-checker.service" ]] \
    || die "aios-checker.service must not be enabled on the live ISO"
  grep -q '^User=aios-checker$' "${iso}/etc/systemd/system/aios-checker.service" \
    || die "aios-checker.service must set User=aios-checker"
  grep -q '^Group=aios-checker$' "${iso}/etc/systemd/system/aios-checker.service" \
    || die "aios-checker.service must set Group=aios-checker"
  grep -q '^ExecStart=/usr/bin/python3 /srv/aios/checker/aios_checker/main.py$' \
    "${iso}/etc/systemd/system/aios-checker.service" \
    || die "aios-checker.service ExecStart must be the checker driver"
  [[ -f "${iso}/etc/systemd/system/aios-agent.service" ]] || die "missing aios-agent.service"
  [[ ! -e "${iso}/etc/systemd/system/multi-user.target.wants/aios-agent.service" ]] \
    || die "aios-agent.service must not be enabled on the live ISO"
  grep -q '^User=aios-agent$' "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must set User=aios-agent"
  grep -q '^Group=aios-agent$' "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must set Group=aios-agent"
  grep -q '^ExecStart=/usr/bin/python3 /srv/aios/agent/aios_agent/main.py$' \
    "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service ExecStart must be the agent driver"
  grep -qx 'ConditionPathExists=/srv/aios/agent/aios_agent/main.py' \
    "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must ConditionPathExists the agent driver"
  grep -qx 'ConditionPathExists=/etc/aios/envelope-accepted' \
    "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must ConditionPathExists the accept stamp (L-20)"
  grep -qx 'ConditionPathExists=!/srv/aios/state/brake' \
    "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must ConditionPathExists the brake (L-12)"
  grep -qx 'Sockets=aios-intent.socket' \
    "${iso}/etc/systemd/system/aios-agent.service" \
    || die "aios-agent.service must list Sockets=aios-intent.socket (L-05)"
  [[ -f "${iso}/etc/systemd/system/aios-intent.socket" ]] || die "missing aios-intent.socket"
  [[ ! -e "${iso}/etc/systemd/system/sockets.target.wants/aios-intent.socket" ]] \
    || die "aios-intent.socket must not be enabled on the live ISO"
  grep -qx 'ListenStream=/run/aios/intent.sock' \
    "${iso}/etc/systemd/system/aios-intent.socket" \
    || die "aios-intent.socket ListenStream must be /run/aios/intent.sock"
  grep -qx 'SocketUser=aios-agent' \
    "${iso}/etc/systemd/system/aios-intent.socket" \
    || die "aios-intent.socket SocketUser must be aios-agent"
  grep -qx 'SocketGroup=aios-work' \
    "${iso}/etc/systemd/system/aios-intent.socket" \
    || die "aios-intent.socket SocketGroup must be aios-work"
  grep -qx 'SocketMode=0660' \
    "${iso}/etc/systemd/system/aios-intent.socket" \
    || die "aios-intent.socket SocketMode must be 0660"
  grep -qx 'Accept=no' \
    "${iso}/etc/systemd/system/aios-intent.socket" \
    || die "aios-intent.socket Accept must be no"
  [[ -f "${iso}/usr/lib/aios/intent/schema.json" ]] || die "missing intent schema.json"
  [[ -f "${iso}/usr/lib/aios/agent/aios_agent/intent_consume.py" ]] \
    || die "missing agent intent_consume.py"
  [[ -f "${iso}/usr/lib/aios/checker/aios_checker/schema.py" ]] || die "missing checker schema.py"
  [[ -d "${REPO_ROOT}/checker" ]] || die "missing checker/"
  diff -qr "${REPO_ROOT}/checker" "${iso}/usr/lib/aios/checker" \
    || die "ISO checker != checker/"
  [[ -f "${iso}/usr/lib/aios/agent/aios_agent/main.py" ]] || die "missing agent main.py"
  [[ -d "${REPO_ROOT}/agent" ]] || die "missing agent/"
  diff -qr "${REPO_ROOT}/agent" "${iso}/usr/lib/aios/agent" \
    || die "ISO agent != agent/"
  grep -q 'aios-checker.service' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must copy aios-checker.service"
  grep -q 'aios-agent.service' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must copy aios-agent.service"
  grep -q 'enable aios-agent.service' "${iso}/usr/lib/aios/bin/firstboot" \
    && die "firstboot must not enable aios-agent.service"
  grep -q 'aios-intent.socket' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must copy aios-intent.socket"
  grep -q 'enable aios-intent.socket' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must enable aios-intent.socket on the installed disk"
  [[ -f "${iso}/etc/sudoers.d/aios-checker-snapper" ]] \
    || die "missing aios-checker snapper sudoers"
  grep -q 'NOPASSWD: /usr/bin/snapper --no-dbus -c root list' \
    "${iso}/etc/sudoers.d/aios-checker-snapper" \
    || die "sudoers must allow only snapper list"
  grep -q 'NOPASSWD: ALL' "${iso}/etc/sudoers.d/aios-checker-snapper" \
    && die "sudoers must not grant ALL"
  grep -q 'aios-checker-snapper' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must copy aios-checker snapper sudoers"
  [[ -f "${iso}/etc/sudoers.d/aios-agent-enact" ]] \
    || die "missing aios-agent enact sudoers"
  grep -qx 'aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact' \
    "${iso}/etc/sudoers.d/aios-agent-enact" \
    || die "sudoers must allow only enact"
  grep -q 'NOPASSWD: ALL' "${iso}/etc/sudoers.d/aios-agent-enact" \
    && die "sudoers must not grant ALL"
  grep -q 'aios-agent-enact' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must copy aios-agent enact sudoers"
  grep -q 'envelope-accepted must not exist before accept' \
    "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must not mint envelope-accepted (L-20)"
  [[ ! -e "${iso}/etc/systemd/system/aios-firstboot.service" ]] \
    || die "aios-firstboot.service is not a named unit (HI-12)"
  grep -q 'login-program /usr/lib/aios/bin/firstboot' \
    "${iso}/etc/systemd/system/getty@tty1.service.d/autologin.conf" \
    || die "getty@tty1 autologin must exec firstboot"
  grep -q 'login-program /usr/lib/aios/bin/firstboot' \
    "${iso}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" \
    || die "serial-getty autologin must exec firstboot"
  grep -q 'TTYPath=/dev/console' "${iso}/etc/systemd/system/aios-installer.service" \
    || die "installer unit must bind /dev/console"
  grep -q 'After=.*getty@tty1.service' "${iso}/etc/systemd/system/aios-installer.service" \
    || die "installer unit must After= gettys so it wins /dev/console"
  grep -q '^Type=simple$' "${iso}/etc/systemd/system/aios-installer.service" \
    || die "installer unit must not use Type=idle against getty"
  grep -q 'mask getty@tty1.service serial-getty@ttyS0.service' \
    "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must mask gettys in the chroot"
  grep -q 'vmlinuz-linux-lts' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must write a linux-lts boot entry"
  grep -q 'vmlinuz-linux' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must write a linux boot entry"
  grep -q 'console=tty0 console=ttyS0' "${iso}/usr/lib/aios/bin/firstboot" \
    || die "firstboot must write serial boot entries"
  if grep -q -- '-Syu' "${iso}/usr/lib/aios/bin/firstboot" \
    "${iso}/usr/lib/aios/bin/installer" \
    "${iso}/usr/lib/aios/bin/aios"; then
    die "firstboot/installer/aios must not contain -Syu"
  fi
  if grep -R -q -- '-Syu' "${iso}/usr/lib/aios/installer" \
    "${iso}/usr/lib/aios/operator-client" 2>/dev/null; then
    die "installer/operator-client TUI must not contain -Syu"
  fi

  local iso_hashes="${iso}/usr/lib/aios/hashes.txt"
  local iso_pub="${iso}/usr/lib/aios/minisign.pub"
  local docs_hi="${REPO_ROOT}/docs/envelope/hard-invariants.md"
  local line hash path f rel
  [[ -f "${iso_hashes}" ]] || die "missing ISO hashes.txt"
  [[ -f "${iso_pub}" ]] || die "missing ISO minisign.pub"
  cmp -s "${PUBKEY}" "${iso_pub}" || die "ISO minisign.pub != payload/minisign.pub"
  [[ -f "${iso}/usr/lib/aios/hard-invariants.md" ]] || die "missing HI file"
  [[ -f "${iso}/usr/lib/aios/envelope/hard-invariants.md" ]] || die "missing envelope HI file"
  cmp -s "${docs_hi}" "${iso}/usr/lib/aios/hard-invariants.md" \
    || die "ISO HI != docs/envelope/hard-invariants.md"
  cmp -s "${docs_hi}" "${iso}/usr/lib/aios/envelope/hard-invariants.md" \
    || die "ISO envelope HI != docs/envelope/hard-invariants.md"
  [[ -d "${iso}/srv/aios/seeds/work-runtime" ]] || die "missing work-runtime seed"
  [[ -d "${iso}/srv/aios/seeds/work-runtime-bots" ]] || die "missing work-runtime-bots seed"
  diff -qr "${REPO_ROOT}/seed/work-runtime" "${iso}/srv/aios/seeds/work-runtime" \
    || die "ISO work-runtime seed != seed/work-runtime"
  diff -qr "${REPO_ROOT}/seed/work-runtime-bots" "${iso}/srv/aios/seeds/work-runtime-bots" \
    || die "ISO work-runtime-bots seed != seed/work-runtime-bots"
  grep -q '/srv/aios/seeds/work-runtime/' "${iso_hashes}" \
    || die "ISO hashes.txt must pin work-runtime seed"
  grep -q '/srv/aios/seeds/work-runtime-bots/' "${iso_hashes}" \
    || die "ISO hashes.txt must pin work-runtime-bots seed"
  grep -Eq '  pacstrap\.x86_64$' "${iso_hashes}" || die "ISO hashes.txt must pin pacstrap.x86_64"
  grep -Eq '  bin/firstboot$' "${iso_hashes}" || die "ISO hashes.txt must pin firstboot"
  grep -Eq '  bin/installer$' "${iso_hashes}" || die "ISO hashes.txt must pin installer"
  grep -Eq '  bin/enact$' "${iso_hashes}" || die "ISO hashes.txt must pin enact"
  grep -Eq '  bin/aios$' "${iso_hashes}" || die "ISO hashes.txt must pin aios"
  grep -Eq '  minisign\.pub$' "${iso_hashes}" || die "ISO hashes.txt must pin minisign.pub"
  grep -Eq 'aios-installer\.service$' "${iso_hashes}" || die "ISO hashes.txt must pin installer unit"
  grep -Eq 'aios-checker\.service$' "${iso_hashes}" || die "ISO hashes.txt must pin checker unit"
  grep -Eq 'aios-agent\.service$' "${iso_hashes}" || die "ISO hashes.txt must pin agent unit"
  grep -Fq 'sudoers.d/aios-checker-snapper' "${iso_hashes}" \
    || die "ISO hashes.txt must pin aios-checker snapper sudoers"
  grep -Fq 'sudoers.d/aios-agent-enact' "${iso_hashes}" \
    || die "ISO hashes.txt must pin aios-agent enact sudoers"
  grep -Eq 'sysusers\.d/aios\.conf$' "${iso_hashes}" || die "ISO hashes.txt must pin sysusers"
  grep -Eq 'tmpfiles\.d/aios\.conf$' "${iso_hashes}" || die "ISO hashes.txt must pin tmpfiles"
  grep -Fq 'getty@tty1.service.d/autologin.conf' "${iso_hashes}" \
    || die "ISO hashes.txt must pin getty@tty1 drop-in"
  grep -Fq 'serial-getty@ttyS0.service.d/autologin.conf' "${iso_hashes}" \
    || die "ISO hashes.txt must pin serial-getty drop-in"
  for rel in hard-invariants.md envelope/hard-invariants.md; do
    grep -Eq "^[0-9a-f]{64}  ${rel}$" "${iso_hashes}" \
      || die "ISO hashes.txt must pin ${rel}"
  done
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    grep -Eq "^[0-9a-f]{64}  /${rel}$" "${iso_hashes}" \
      || die "ISO hashes.txt must pin /${rel}"
  done < <(cd "${iso}" && find srv/aios/seeds -type f | sort)
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    grep -Eq "^[0-9a-f]{64}  ${rel}$" "${iso_hashes}" \
      || die "ISO hashes.txt must pin ${rel}"
  done < <(cd "${iso}/usr/lib/aios" && find checker agent installer operator-client -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sort)
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    hash=${line%% *}
    path=${line#* }
    path=${path# }
    path=${path#\*}
    [[ -n "${hash}" && -n "${path}" ]] || die "bad ISO hashes.txt line"
    if [[ "${path}" == /* ]]; then
      f="${iso}${path}"
    else
      f="${iso}/usr/lib/aios/${path}"
    fi
    [[ -e "${f}" ]] || die "ISO hashed path missing: ${path}"
    printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --status - \
      || die "ISO hash mismatch: ${path}"
  done < "${iso_hashes}"
}

# firstboot refuses disks unless /usr/lib/aios/hashes.txt.minisig verifies (P1.2/P1.4).
sign_live_hashes() {
  local seckey iso_hashes iso_sig
  iso_hashes="${PROFILE}/airootfs/usr/lib/aios/hashes.txt"
  iso_sig="${iso_hashes}.minisig"
  [[ -f "${iso_hashes}" ]] || die "missing ${iso_hashes}"
  seckey=$(resolve_seckey)
  rm -f "${iso_sig}"
  if [[ ! -f "${seckey}" ]]; then
    if [[ "${PUBLISH}" -eq 1 ]]; then
      die "publish refused: minisign secret key missing; cannot sign live hashes.txt (L-10)"
    fi
    printf 'unsigned: %s (no secret key; firstboot will refuse disks)\n' "${iso_hashes}" >&2
    return 0
  fi
  ensure_chroot_minisign
  bind_seckey "${seckey}"
  run_minisign -S -s /root/aios-minisign.key \
    -m /mnt/aios/payload/profile/airootfs/usr/lib/aios/hashes.txt \
    || die "minisign sign failed for live hashes.txt"
  [[ -f "${iso_sig}" ]] || die "missing ${iso_sig} after sign"
  run_minisign -Vm /mnt/aios/payload/profile/airootfs/usr/lib/aios/hashes.txt \
    -p /mnt/aios/payload/minisign.pub >/dev/null \
    || die "minisign: bad signature for live hashes.txt"
  unbind_seckey
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

  # arch-chroot wants a mountpoint (Arch Wiki). Bind the root onto itself.
  mount --bind "${BOOTSTRAP_ROOT}" "${BOOTSTRAP_ROOT}"
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman-key --init
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman-key --populate archlinux
  # Same-day Archive freeze as the bootstrap tarball (not Harness A / not rolling).
  # Bootstrap ships with empty sync dbs; -Syu against that freeze is a full
  # upgrade of one snapshot, not a partial upgrade.
  "${BOOTSTRAP_ROOT}/bin/arch-chroot" "${BOOTSTRAP_ROOT}" pacman -Syu --noconfirm --needed archiso
  [[ -x "${BOOTSTRAP_ROOT}/usr/bin/mkarchiso" ]] \
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

trap cleanup EXIT

check_package_lists
sync_iso_pubkey
check_hashes
check_firstboot_payload
verify_pin
prepare_chroot
sign_live_hashes
run_mkarchiso

shopt -s nullglob
isos=("${DIST}"/aios-*.iso)
[[ ${#isos[@]} -ge 1 ]] || die "mkarchiso finished but ${DIST}/aios-*.iso is missing"
printf 'built %s\n' "${isos[@]}"
sign_isos
assert_published_signed
