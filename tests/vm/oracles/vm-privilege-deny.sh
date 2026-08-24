#!/bin/sh
# P6.3 guest/vm oracle. HI-13 HI-16.
# Work slice cannot pacman, cannot enact, cannot write envelope, cannot read
# the OS key. Intent is not a shell. Denial is EPERM/capabilities, not
# "the model declined".
#
# Host (default): fail closed without ISO/KVM via tests/vm/run.sh
# privilege-deny. qemu is gated on AIOS_VM_BOOT (HI-08). Full ISO boot is
# not claimed against a stale image.
# Guest: AIOS_VM_GUEST=1 on an installed AIOS box, never in this worktree.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)
RUN="${ROOT}/tests/vm/run.sh"
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

os_denial() {
  printf '%s\n' "$1" | grep -Eqi \
    'EPERM|Operation not permitted|Permission denied|you cannot perform this operation unless you are root|Capability|NoNewPrivileges'
}

model_story() {
  printf '%s\n' "$1" | grep -Eqi 'the model declined'
}

guest_oracle() {
  # HI-13: Work agents never enact privileged change. They file intents.
  # HI-16: The privilege boundary is enforced by the operating system, not
  # by work-agent cooperation.
  [ "$(id -u)" -eq 0 ] || die "guest oracle must run as root for sudo -u aios-work"
  command -v sudo >/dev/null 2>&1 || die "sudo missing; fail closed"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run missing; fail closed"
  id -u aios-work >/dev/null 2>&1 || die "aios-work uid missing (L-02)"

  POLICY=/usr/lib/aios/checker/policy
  if [ ! -x "${POLICY}/work-slice.sh" ]; then
    POLICY=/srv/aios/checker/policy
  fi
  [ -x "${POLICY}/work-slice.sh" ] || die "work-slice.sh missing"
  [ -x "${POLICY}/hi-16-os-privilege.sh" ] || die "hi-16-os-privilege.sh missing"
  # Live guest: destroot would skip uid checks. Absence of P6.2 units is not green.
  [ -f /etc/systemd/system/aios-work.slice ] \
    || die "live aios-work.slice missing; fail closed (HI-16)"
  [ -f /usr/lib/systemd/system/aios-work-.service.d/10-floor.conf ] \
    || die "live floor drop-in missing; fail closed (HI-16)"
  env -u AIOS_POLICY_ROOT "${POLICY}/work-slice.sh" \
    || die "work-slice.sh failed in guest (HI-13)"
  env -u AIOS_POLICY_ROOT "${POLICY}/hi-16-os-privilege.sh" \
    || die "hi-16-os-privilege.sh failed in guest (HI-16)"

  [ -e /srv/aios/envelope ] || die "missing /srv/aios/envelope"
  [ -e /usr/lib/aios/bin/enact ] || die "missing /usr/lib/aios/bin/enact"
  [ -e /srv/aios/state ] || die "missing /srv/aios/state"

  if sudo -u aios-work test -w /srv/aios/envelope; then
    die "aios-work can write /srv/aios/envelope (HI-13)"
  fi
  if sudo -u aios-work test -w /srv/aios/state; then
    die "aios-work can write /srv/aios/state (HI-16)"
  fi
  _token=/srv/aios/state/provider/os.token
  if [ -e "${_token}" ] && sudo -u aios-work test -r "${_token}"; then
    die "aios-work can read OS token (L-16, HI-13)"
  fi

  # Floor drop-in applies to aios-work-*.service. Prove it loaded (HI-16).
  _probe=aios-work-privilege-deny-probe.service
  systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
  if ! systemd-run --quiet --service-type=oneshot --remain-after-exit \
    --uid=aios-work --gid=aios-work \
    --slice=aios-work.slice \
    --unit="${_probe}" \
    /usr/bin/true; then
    systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
    die "could not start aios-work slice probe (HI-16)"
  fi
  _caps=$(systemctl show -p CapabilityBoundingSet --value "${_probe}" 2>/dev/null || true)
  _inacc=$(systemctl show -p InaccessiblePaths --value "${_probe}" 2>/dev/null || true)
  _sl=$(systemctl show -p Slice --value "${_probe}" 2>/dev/null || true)
  systemctl stop "${_probe}" >/dev/null 2>&1 || true
  systemctl reset-failed "${_probe}" >/dev/null 2>&1 || true
  [ -z "${_caps}" ] \
    || die "slice probe CapabilityBoundingSet is not empty: ${_caps}"
  printf '%s\n' "${_inacc}" | grep -q enact \
    || die "slice probe InaccessiblePaths missing enact: ${_inacc}"
  [ "${_sl}" = "aios-work.slice" ] \
    || die "slice probe Slice is ${_sl}, not aios-work.slice"

  _unit=aios-work-privilege-deny.service
  systemctl reset-failed "${_unit}" >/dev/null 2>&1 || true
  _out=$(systemd-run --quiet --wait --pipe --collect \
    --uid=aios-work --gid=aios-work \
    --slice=aios-work.slice \
    --unit="${_unit}" \
    /usr/bin/pacman -S --noconfirm neovim 2>&1) && _rc=0 || _rc=$?
  [ "${_rc}" != 0 ] || die "pacman -S from aios-work.slice succeeded (HI-13)"
  if model_story "${_out}"; then
    die "pacman -S denial must not be the model declined: ${_out}"
  fi
  os_denial "${_out}" \
    || die "pacman -S from aios-work.slice must fail as EPERM/capabilities: ${_out}"

  _xout=$(systemd-run --quiet --wait --pipe --collect \
    --uid=aios-work --gid=aios-work \
    --slice=aios-work.slice \
    --unit=aios-work-privilege-deny-x.service \
    /usr/bin/test -x /usr/lib/aios/bin/enact 2>&1) && _xrc=0 || _xrc=$?
  [ "${_xrc}" != 0 ] \
    || die "slice can execute enact (HI-16): ${_xout}"

  [ -S /run/aios/intent.sock ] || die "intent.sock missing; fail closed (L-05)"
  _payload='{"id":"6ba7b810-9dad-41d1-80b4-00c04fd430c8","source":"work-runtime","asked":"install neovim as the system editor","clause":null,"suggested_oracles":["pacman -Qi neovim"],"paths":["/srv/aios/src/work-runtime"]}'
  _ack=$(sudo -u aios-work python3 -c '
import socket
import sys

path = "/run/aios/intent.sock"
payload = sys.argv[1].encode("utf-8")
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(3)
sock.connect(path)
sock.sendall(payload)
sock.shutdown(socket.SHUT_WR)
data = b""
while True:
    chunk = sock.recv(4096)
    if not chunk:
        break
    data += chunk
sock.close()
sys.stdout.buffer.write(data)
' "${_payload}" 2>&1) || die "aios-work could not file a work-intent: ${_ack}"
  printf '%s\n' "${_ack}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("accepted") is not True:
    raise SystemExit("valid intent not ACK: %s" % d)
if d.get("id") != "6ba7b810-9dad-41d1-80b4-00c04fd430c8":
    raise SystemExit("ACK id mismatch")
' || die "valid work-intent ACK: ${_ack}"

  printf 'ok: vm-privilege-deny (guest). HI-13 HI-16.\n'
}

if [ "${AIOS_VM_GUEST:-0}" = 1 ]; then
  # Never run live pacman/sudo against the payload worktree host.
  if [ -f "${ROOT}/payload/profile/airootfs/etc/systemd/system/aios-work.slice" ]; then
    die "AIOS_VM_GUEST=1 in the worktree; refuse (do not mutate the workstation)"
  fi
  guest_oracle
  exit 0
fi

# Host: qemu.sh via run.sh, not a second wrapper. AIOS_VM_BOOT gates boot.
[ -x "${RUN}" ] || die "missing ${RUN}"
exec "${RUN}" privilege-deny
