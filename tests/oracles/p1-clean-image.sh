#!/bin/sh
# P1.5 clean-image oracle: fail-closed greps on the archiso profile.
# Does not build the ISO. Checker secrets-scan/pii-scan are P3.4.
# Envelope: P1.5, L-09, L-19, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
PAYLOAD="${ROOT}/payload"
PROFILE="${PAYLOAD}/profile"
AIROOTFS="${PROFILE}/airootfs"
PACKAGES="${PROFILE}/packages.x86_64"
PACSTRAP="${PROFILE}/pacstrap.x86_64"
PACSTRAP_ISO="${AIROOTFS}/usr/lib/aios/pacstrap.x86_64"
FIRSTBOOT="${AIROOTFS}/usr/lib/aios/bin/firstboot"
INSTALLER="${AIROOTFS}/usr/lib/aios/bin/installer"
DE_NAMES='^(hyprland|gnome|plasma|sddm|gdm)$'
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

need_file() {
  [ -f "$1" ] || fail "missing $1"
}

need_line() {
  grep -qx "$2" "$1" || fail "$2 missing from $1"
}

need_file "${PACKAGES}"
need_file "${PACSTRAP}"
need_file "${PACSTRAP_ISO}"
need_file "${FIRSTBOOT}"
need_file "${INSTALLER}"
need_file "${AIROOTFS}/etc/systemd/system/aios-checker.service"
need_file "${AIROOTFS}/usr/lib/aios/checker/aios_checker/schema.py"
[ -d "${AIROOTFS}/etc/systemd/system" ] || fail "missing airootfs systemd/system"

# No DE / display-manager names in the live ISO list or the installed set.
if grep -qEi "${DE_NAMES}" "${PACKAGES}" "${PACSTRAP}" "${PACSTRAP_ISO}" 2>/dev/null; then
  fail "DE/display-manager name in packages.x86_64 or pacstrap.x86_64"
fi

# Both kernels in both lists; zram-generator in the installed set.
need_line "${PACKAGES}" linux
need_line "${PACKAGES}" linux-lts
need_line "${PACSTRAP}" linux
need_line "${PACSTRAP}" linux-lts
need_line "${PACSTRAP}" zram-generator
# openssh present (and must stay disabled — checked via wants/ below).
need_line "${PACKAGES}" openssh
need_line "${PACSTRAP}" openssh

cmp -s "${PACSTRAP}" "${PACSTRAP_ISO}" \
  || fail "airootfs pacstrap.x86_64 is not the same bytes as profile/pacstrap.x86_64"

# openssh.service / sshd not enabled on the live ISO.
sshd_wants=$(find "${AIROOTFS}/etc/systemd" \
  \( -path '*.wants/*' -o -path '*.requires/*' \) \
  \( -name 'sshd.service' -o -name 'openssh.service' -o -name 'ssh.service' \
     -o -name 'sshd.socket' \) -print 2>/dev/null || true)
if [ -n "${sshd_wants}" ]; then
  fail "openssh/sshd enabled in airootfs: ${sshd_wants}"
fi

# aios-installer.service is copied for the chroot; it is not enabled on the ISO.
if [ -e "${AIROOTFS}/etc/systemd/system/multi-user.target.wants/aios-installer.service" ]; then
  fail "aios-installer.service must not be in multi-user.target.wants"
fi
installer_wants=$(find "${AIROOTFS}/etc/systemd" \
  \( -path '*.wants/aios-installer.service' -o -path '*.requires/aios-installer.service' \) \
  -print 2>/dev/null || true)
if [ -n "${installer_wants}" ]; then
  fail "aios-installer.service must not be enabled on the live ISO: ${installer_wants}"
fi

# aios-checker.service is copied for the chroot; it is not enabled on the ISO.
if [ -e "${AIROOTFS}/etc/systemd/system/multi-user.target.wants/aios-checker.service" ]; then
  fail "aios-checker.service must not be in multi-user.target.wants"
fi
checker_wants=$(find "${AIROOTFS}/etc/systemd" \
  \( -path '*.wants/aios-checker.service' -o -path '*.requires/aios-checker.service' \) \
  -print 2>/dev/null || true)
if [ -n "${checker_wants}" ]; then
  fail "aios-checker.service must not be enabled on the live ISO: ${checker_wants}"
fi

# No aios-firstboot.service (HI-12: autologin execs the binary).
firstboot_unit=$(find "${PAYLOAD}" -name 'aios-firstboot.service' -print 2>/dev/null || true)
if [ -n "${firstboot_unit}" ]; then
  fail "aios-firstboot.service is not a named unit (HI-12): ${firstboot_unit}"
fi

# Harness A: firstboot/installer must not contain -Syu.
if grep -q -- '-Syu' "${FIRSTBOOT}" "${INSTALLER}" 2>/dev/null; then
  fail "firstboot/installer contains -Syu (L-20)"
fi

# secrets-scan style: no private keys, minisign secret, or .env under payload/.
env_files=$(find "${PAYLOAD}" -type f \
  \( -name '.env' -o -name '.env.*' ! -name '.env.example' \
     -o -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
     -o -name '*.minisign.key' -o -name 'minisign.key' \) -print 2>/dev/null || true)
if [ -n "${env_files}" ]; then
  fail "secret file names in payload/: ${env_files}"
fi

key_hits=$(find "${PAYLOAD}" -type f ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' \
  -exec grep -E -n -- \
    '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----|-----BEGIN OPENSSH PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY BLOCK-----|-----BEGIN MINISIGN SECRET KEY-----|untrusted comment: minisign encrypted secret key' \
    {} + 2>/dev/null || true)
if [ -n "${key_hits}" ]; then
  fail "private key material in payload/"
  printf '%s\n' "${key_hits}" >&2
fi

# pii-scan style: no emails/phones in payload/. Skip a token only when that
# token is a systemd instance (getty@tty1.service). Path prefixes and other
# text on the line must not hide a real address.
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
unit_tok='^[A-Za-z0-9._%+-]+@[A-Za-z0-9_.-]+\.(service|socket|device|mount|automount|swap|target|path|timer|slice|scope)$'
email_hits=$(
  find "${PAYLOAD}" -type f ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' -print \
  | while IFS= read -r _f; do
      grep -E -h -o -- "${email_re}" "${_f}" 2>/dev/null \
      | while IFS= read -r _tok; do
          [ -n "${_tok}" ] || continue
          printf '%s\n' "${_tok}" | grep -Eq -- "${unit_tok}" && continue
          printf '%s:%s\n' "${_f}" "${_tok}"
        done
    done
)
if [ -n "${email_hits}" ]; then
  fail "email-like PII in payload/"
  printf '%s\n' "${email_hits}" >&2
fi


phone_hits=$(find "${PAYLOAD}" -type f ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' \
  -exec grep -E -n -- '(^|[^0-9])[0-9]{3}[-.][0-9]{3}[-.][0-9]{4}([^0-9]|$)|(^|[^0-9])\+[0-9][-0-9(). ]{8,18}[0-9]' \
  {} + 2>/dev/null || true)
if [ -n "${phone_hits}" ]; then
  fail "phone-like PII in payload/"
  printf '%s\n' "${phone_hits}" >&2
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: P1.5 clean-image oracle failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: P1.5 clean-image\n'
exit 0
