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
AIOSBIN="${AIROOTFS}/usr/lib/aios/bin/aios"
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
need_file "${AIOSBIN}"
need_file "${AIROOTFS}/usr/lib/aios/operator-client/tty/aios.py"
need_file "${AIROOTFS}/usr/lib/aios/operator-client/tty/notify.py"
CHECKER_UNIT="${AIROOTFS}/etc/systemd/system/aios-checker.service"
AGENT_UNIT="${AIROOTFS}/etc/systemd/system/aios-agent.service"
ENACT="${AIROOTFS}/usr/lib/aios/bin/enact"
need_file "${CHECKER_UNIT}"
need_file "${AGENT_UNIT}"
need_file "${ENACT}"
need_file "${AIROOTFS}/usr/lib/aios/checker/aios_checker/schema.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/main.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/deny.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/provider/base.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/provider/fixture.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/provider/live.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/loop.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/triage.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/skills.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/memory.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/goals.py"
need_file "${AIROOTFS}/usr/lib/aios/agent/aios_agent/intent_consume.py"
need_file "${AIROOTFS}/usr/lib/aios/intent/schema.json"
need_file "${AIROOTFS}/etc/systemd/system/aios-intent.socket"
need_file "${AIROOTFS}/etc/systemd/system/aios-work.slice"
need_file "${AIROOTFS}/usr/lib/systemd/system/aios-work-.service.d/10-floor.conf"
need_file "${AIROOTFS}/usr/lib/aios/installer/aios_installer/main.py"
need_file "${AIROOTFS}/usr/lib/aios/installer/aios_installer/questions.py"
need_file "${AIROOTFS}/usr/lib/aios/installer/aios_installer/compiler.py"
need_file "${AIROOTFS}/usr/lib/aios/installer/aios_installer/recover.py"
need_file "${AIROOTFS}/usr/lib/aios/installer/aios_installer/login.py"
SUDOERS="${AIROOTFS}/etc/sudoers.d/aios-checker-snapper"
AGENT_SUDOERS="${AIROOTFS}/etc/sudoers.d/aios-agent-enact"
need_file "${SUDOERS}"
need_file "${AGENT_SUDOERS}"
need_line "${SUDOERS}" \
  "aios-checker ALL=(root) NOPASSWD: /usr/bin/snapper --no-dbus -c root list"
need_line "${AGENT_SUDOERS}" \
  "aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact"
if grep -q 'NOPASSWD: ALL' "${SUDOERS}" "${AGENT_SUDOERS}" 2>/dev/null; then
  fail "sudoers must not grant ALL"
fi
need_line "${CHECKER_UNIT}" "User=aios-checker"
need_line "${CHECKER_UNIT}" "Group=aios-checker"
need_line "${CHECKER_UNIT}" \
  "ExecStart=/usr/bin/python3 /srv/aios/checker/aios_checker/main.py"
need_line "${AGENT_UNIT}" "User=aios-agent"
need_line "${AGENT_UNIT}" "Group=aios-agent"
need_line "${AGENT_UNIT}" \
  "ExecStart=/usr/bin/python3 /srv/aios/agent/aios_agent/main.py"
need_line "${AGENT_UNIT}" \
  "ConditionPathExists=/srv/aios/agent/aios_agent/main.py"
need_line "${AGENT_UNIT}" \
  "ConditionPathExists=/etc/aios/envelope-accepted"
need_line "${AGENT_UNIT}" \
  "ConditionPathExists=!/srv/aios/state/brake"
need_line "${AGENT_UNIT}" "Sockets=aios-intent.socket"
  "ConditionPathExists=!/srv/aios/state/brake.d/stamp"
grep -q 'cannot merge to main (HI-03)' "${AIROOTFS}/usr/lib/aios/agent/aios_agent/deny.py" \
  || fail "agent deny-list missing HI-03 merge-to-main"
grep -q 'HI-06' "${AIROOTFS}/usr/lib/aios/agent/aios_agent/deny.py" \
  || fail "agent deny-list missing HI-06 seatbelts"
grep -q 'etckeeper.timer' "${AIROOTFS}/usr/lib/aios/agent/aios_agent/deny.py" \
  || fail "agent deny-list missing etckeeper"
grep -q 'partial pacman is not allowlisted' "${ENACT}" \
  || fail "enact allowlist missing partial-pacman refusal"
grep -Fq '/usr/bin/pacman -Syu --noconfirm' "${ENACT}" \
  || fail "enact cmd_syu must run /usr/bin/pacman -Syu --noconfirm (P4.5)"
grep -q 'syu window is not this phase' "${ENACT}" \
  && fail "enact cmd_syu must not die closed (P4.5)"
grep -q '/boot/aios-gen/' "${ENACT}" \
  || fail "enact must copy ESP generation (L-19)"
grep -q 'initramfs-linux-lts.img' "${ENACT}" \
  || fail "enact ESP copy missing linux-lts initramfs (L-19)"
grep -E '^ESP_FILES=.*fallback' "${ENACT}" \
  && fail "enact must not copy fallback initramfs (L-19)"
grep -q 'Retention N=2' "${ENACT}" \
  || fail "enact must keep ESP retention N=2 (L-19)"
grep -q 'dropped stale ESP generation' "${ENACT}" \
  || fail "enact must drop extra aios-gen dirs (L-19)"
grep -q 'pacman -Qqe' "${ENACT}" \
  || fail "enact must refresh packages.txt from pacman -Qqe"
grep -q 'boot-seatbelt.sh' "${ENACT}" \
  || fail "enact must run boot-seatbelt.sh after the window (HI-06, L-19)"
grep -Fq 'syu|snapper-pre|snapper-post|bootctl|unit' "${ENACT}" \
  || fail "enact allowlist verbs missing"
grep -q 'ACCEPT_STAMP=/etc/aios/envelope-accepted' "${ENACT}" \
  || fail "enact must gate on root-owned accept stamp (L-20)"
if grep -q wheel "${AIROOTFS}/usr/lib/sysusers.d/aios.conf" 2>/dev/null; then
  fail "sysusers must not put aios uids in wheel"
fi
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

# aios-agent.service is copied for the chroot; it is not enabled on the ISO (L-20).
if [ -e "${AIROOTFS}/etc/systemd/system/multi-user.target.wants/aios-agent.service" ]; then
  fail "aios-agent.service must not be in multi-user.target.wants"
fi
agent_wants=$(find "${AIROOTFS}/etc/systemd" \
  \( -path '*.wants/aios-agent.service' -o -path '*.requires/aios-agent.service' \) \
  -print 2>/dev/null || true)
if [ -n "${agent_wants}" ]; then
  fail "aios-agent.service must not be enabled on the live ISO: ${agent_wants}"
fi
if grep -q 'enable aios-agent.service' "${FIRSTBOOT}" 2>/dev/null; then
  fail "firstboot must not enable aios-agent.service (L-20)"
fi
grep -q 'aios-agent.service' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-agent.service"
grep -q 'aios-agent-enact' "${FIRSTBOOT}" \
  || fail "firstboot must copy aios-agent enact sudoers"
grep -q 'mkdir -p "${TARGET}/etc/aios"' "${FIRSTBOOT}" \
  || fail "firstboot must create root-owned /etc/aios"
grep -q 'envelope-accepted must not exist before accept' "${FIRSTBOOT}" \
  || fail "firstboot must not mint envelope-accepted (L-20)"

# No aios-firstboot.service (HI-12: autologin execs the binary).
firstboot_unit=$(find "${PAYLOAD}" -name 'aios-firstboot.service' -print 2>/dev/null || true)
if [ -n "${firstboot_unit}" ]; then
  fail "aios-firstboot.service is not a named unit (HI-12): ${firstboot_unit}"
fi

# Harness A: firstboot/installer/aios must not contain -Syu.
if grep -q -- '-Syu' "${FIRSTBOOT}" "${INSTALLER}" "${AIOSBIN}" 2>/dev/null; then
  fail "firstboot/installer/aios contains -Syu (L-20)"
fi
if grep -R -q -- '-Syu' "${AIROOTFS}/usr/lib/aios/installer" \
  "${AIROOTFS}/usr/lib/aios/operator-client" 2>/dev/null; then
  fail "installer/operator-client TUI contains -Syu (L-20)"
fi
grep -q 'aios_installer/main.py' "${FIRSTBOOT}" \
  || fail "firstboot must copy installer Python tree"
grep -q '/srv/aios/state/snapper_pre' "${FIRSTBOOT}" \
  || fail "firstboot must write snapper_pre for installer recovery (HI-09)"
grep -q 'exec /usr/bin/python3' "${INSTALLER}" \
  || fail "bin/installer must exec python3 TUI"

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

if ! "${SCRIPT_DIR}/p4-enact-deny.sh"; then
  fail "p4-enact-deny"
fi

if ! "${SCRIPT_DIR}/p4-provider.sh"; then
  fail "p4-provider"
fi

if ! "${SCRIPT_DIR}/p4-loop.sh"; then
  fail "p4-loop"
fi

if ! "${SCRIPT_DIR}/p4-goals.sh"; then
  fail "p4-goals"
fi

if ! "${SCRIPT_DIR}/p5-installer-views.sh"; then
  fail "p5-installer-views"
fi

if ! "${SCRIPT_DIR}/p5-envelope-compiler.sh"; then
  fail "p5-envelope-compiler"
fi

if ! "${SCRIPT_DIR}/p5-recover.sh"; then
  fail "p5-recover"
fi

if ! "${SCRIPT_DIR}/p5-operator-login.sh"; then
  fail "p5-operator-login"
fi

if ! "${SCRIPT_DIR}/p6-intent-sock.sh"; then
  fail "p6-intent-sock"
fi

if ! "${SCRIPT_DIR}/p6-work-slice.sh"; then
  fail "p6-work-slice"
fi

if ! "${SCRIPT_DIR}/p7-summon-brake.sh"; then
  fail "p7-summon-brake"
fi

if ! "${SCRIPT_DIR}/p7-notify.sh"; then
  fail "p7-notify"
fi

if ! "${SCRIPT_DIR}/p7-os-views.sh"; then
  fail "p7-os-views"
fi

if ! "${SCRIPT_DIR}/p7-login.sh"; then
  fail "p7-login"
fi

if ! "${SCRIPT_DIR}/p9-vm-harness.sh"; then
  fail "p9-vm-harness"
fi

_prov=$(grep -R -n -- 'provider' "${ROOT}/checker" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "checker names provider (HI-02, L-08): ${_prov}"
grep -q '/srv/aios/state/provider/os.token' \
  "${AIROOTFS}/usr/lib/aios/agent/aios_agent/provider/base.py" \
  || fail "ISO agent missing P4.2 OS token lock"
grep -Eq "^[[:space:]]+'/provider/'[[:space:]]*\\\\$" "${FIRSTBOOT}" \
  || fail "firstboot printf payload missing exact /provider/ gitignore line (L-16)"
grep -qx '**/os.token' "${ROOT}/.gitignore" \
  || fail ".gitignore missing **/os.token (L-16)"

if [ "${failed}" -ne 0 ]; then
  printf 'error: P1.5 clean-image oracle failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: P1.5 clean-image\n'
exit 0
