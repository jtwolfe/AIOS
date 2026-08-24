#!/bin/sh
# P7.7: L-19 restore procedure. Host destroot; never mutate workstation btrfs.
# Envelope: P7.7, L-19, HI-06, L-04, L-12.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
MAIN="${ROOT}/operator-client/tty/aios.py"
GATE="${ROOT}/agent/aios_agent/rollback_gate.py"
LOGIN_GATE="${ROOT}/agent/aios_agent/login_gate.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_ENACT="${ENACT}"
ISO_GATE="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent/aios_agent/rollback_gate.py"
ISO_LOGIN_GATE="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent/aios_agent/login_gate.py"
ISO_AGENT_MAIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/agent/aios_agent/main.py"
ISO_LOGIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer/aios_installer/login.py"
LOGIN="${ROOT}/installer/aios_installer/login.py"
AGENT_MAIN="${ROOT}/agent/aios_agent/main.py"
RUN="${ROOT}/tests/vm/run.sh"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"
[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${GATE}" ] || fail "missing ${GATE}"
[ -f "${ISO_GATE}" ] || fail "missing ISO rollback_gate.py"
[ -f "${ISO_OC}/tty/aios.py" ] || fail "missing ISO aios.py"
[ -x "${RUN}" ] || fail "missing ${RUN}"

grep -q 'P7.7' "${MAIN}" || fail "aios.py must quote P7.7"
grep -q 'L-19' "${MAIN}" || fail "aios.py must quote L-19"
grep -q 'HI-06' "${MAIN}" || fail "aios.py must quote HI-06"
grep -q 'L-19' "${ENACT}" || fail "enact must quote L-19"
grep -q 'HI-06' "${ENACT}" || fail "enact must quote HI-06"
grep -q 'subvol=@.restore-' "${ENACT}" \
  || fail "enact must write subvol=@.restore-N (L-19)"
grep -q 'refuse RO snapper snapshot as /' "${ENACT}" \
  || fail "enact must refuse RO snapper snapshot as / (L-19, HI-06)"
grep -q 'pre id' "${ENACT}" || fail "enact must refuse a pre id (L-19)"
grep -q 'failed window' "${ENACT}" \
  || fail "enact must refuse the failed window post id (HI-06, L-19)"
grep -q 'prefer subvol= over subvolid=' "${ENACT}" \
  || fail "enact must prefer subvol= over subvolid="
grep -q 'AIOS_ROOT' "${ENACT}" || fail "enact rollback must honor AIOS_ROOT"
grep -q 'tick_rollback' "${LOGIN_GATE}" \
  || fail "login_gate drain must tick rollback"
grep -q 'rollback-request' "${MAIN}" \
  || fail "aios.py must file rollback-request (L-19)"
grep -q 'rollback-request' "${LOGIN}" \
  || fail "accept must create rollback-request (L-19)"
grep -q 'boot-seatbelt' "${RUN}" \
  || fail "run.sh must name boot-seatbelt (vm-boot-seatbelt)"
grep -q 'AIOS_VM_BOOT' "${RUN}" \
  || fail "run.sh must gate qemu boot on AIOS_VM_BOOT"

if grep -nE '^[^#]*snapper[[:space:]]+(rollback|undochange)' "${ENACT}"
then
  fail "enact must not call snapper rollback/undochange (L-19)"
fi
if grep -n -- 'subvolume snapshot -r' "${ENACT}"; then
  fail "enact must not create a RO btrfs snapshot (L-19)"
fi

if grep -En -- '[[:space:]]sudo[[:space:]]|sudo$|NOPASSWD' "${MAIN}" >/dev/null
then
  fail "operator-client must not sudo (L-19)"
fi

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
cp -a "${GATE}" "${_pyct}/rollback_gate.py" || fail "copy rollback_gate.py"
cp -a "${LOGIN_GATE}" "${_pyct}/login_gate.py" || fail "copy login_gate.py"
python3 -m py_compile \
  "${_pyct}/aios.py" \
  "${_pyct}/rollback_gate.py" \
  "${_pyct}/login_gate.py" \
  || fail "py_compile failed"
rm -rf "${_pyct}"

sh -n "${ENACT}" || fail "sh -n enact"
sh -n "${RUN}" || fail "sh -n run.sh"
sh -n "${0}" || fail "sh -n p7-rollback.sh"

cmp -s "${MAIN}" "${ISO_OC}/tty/aios.py" \
  || fail "ISO aios.py bytes differ"
cmp -s "${GATE}" "${ISO_GATE}" \
  || fail "ISO rollback_gate.py bytes differ"
cmp -s "${LOGIN_GATE}" "${ISO_LOGIN_GATE}" \
  || fail "ISO login_gate.py bytes differ"
cmp -s "${AGENT_MAIN}" "${ISO_AGENT_MAIN}" \
  || fail "ISO agent main.py bytes differ"
cmp -s "${LOGIN}" "${ISO_LOGIN}" \
  || fail "ISO login.py bytes differ"

LIVE_RB="/boot/loader/entries/aios-rollback.conf"
LIVE_BTRFS="/run/aios-btrfs"
LIVE_BROKEN="/srv/aios/state/broken-subvol"
_live_rb=0
_live_btrfs=0
_live_broken=0
[ -e "${LIVE_RB}" ] && _live_rb=1
[ -e "${LIVE_BTRFS}" ] && _live_btrfs=1
[ -e "${LIVE_BROKEN}" ] && _live_broken=1

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

DEST="${TMP}/root"
mkdir -p \
  "${DEST}/etc/aios" \
  "${DEST}/etc" \
  "${DEST}/boot/loader/entries" \
  "${DEST}/boot/aios-gen/1" \
  "${DEST}/boot/aios-gen/3" \
  "${DEST}/srv/aios/state" \
  "${DEST}/run/aios" \
  "${DEST}/.snapshots/2" \
  "${DEST}/run/aios-btrfs/@snapshots/2"

: > "${DEST}/etc/aios/envelope-accepted"
printf '%s\n' 'UUID=11111111-1111-1111-1111-111111111111 / btrfs rw,subvol=@ 0 0' \
  > "${DEST}/etc/fstab"
printf '%s\n' '# snapper_id esp_dir' \
  '1 /boot/aios-gen/1' \
  '3 /boot/aios-gen/3' > "${DEST}/srv/aios/state/esp-generations"
for _f in vmlinuz-linux vmlinuz-linux-lts initramfs-linux.img initramfs-linux-lts.img
do
  printf 'k1-%s\n' "${_f}" > "${DEST}/boot/aios-gen/1/${_f}"
  printf 'k3-%s\n' "${_f}" > "${DEST}/boot/aios-gen/3/${_f}"
  printf 'live-%s\n' "${_f}" > "${DEST}/boot/${_f}"
done
cat > "${DEST}/boot/loader/entries/aios-linux.conf" <<'EOF'
title   AIOS (linux)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=11111111-1111-1111-1111-111111111111 rootflags=subvol=@ rw console=tty0
EOF
cat > "${DEST}/boot/loader/entries/aios-linux-lts.conf" <<'EOF'
title   AIOS (linux-lts)
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options root=UUID=11111111-1111-1111-1111-111111111111 rootflags=subvol=@ rw console=tty0
EOF
cat > "${DEST}/boot/loader/loader.conf" <<'EOF'
default aios-linux.conf
timeout 5
console-mode keep
editor no
EOF
printf '%s\n' '<snapshot><type>pre</type><num>2</num></snapshot>' \
  > "${DEST}/.snapshots/2/info.xml"
cp -a "${DEST}/.snapshots/2/info.xml" \
  "${DEST}/run/aios-btrfs/@snapshots/2/info.xml"
: > "${DEST}/run/aios/rollback-request"
: > "${DEST}/run/aios/rollback-status"
chmod 0660 "${DEST}/run/aios/rollback-request"
chmod 0640 "${DEST}/run/aios/rollback-status"

BIN="${TMP}/bin"
mkdir -p "${BIN}"
for _n in btrfs bootctl mount mountpoint snapper
do
  cat > "${BIN}/${_n}" <<EOF
#!/bin/sh
printf 'error: ${_n} invoked on destroot\n' >&2
exit 1
EOF
  chmod +x "${BIN}/${_n}"
done
ORACLE_PATH="${BIN}:${PATH}"

run_enact() {
  PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" "${ENACT}" "$@" 2>"${TMP}/err" || true
}

_out=$(run_enact rollback)
grep -q 'rollback requires N' "${TMP}/err" \
  || fail "rollback without N: $(cat "${TMP}/err")"

_out=$(run_enact rollback 3)
grep -q 'failed window' "${TMP}/err" \
  || fail "last map id must be refused: $(cat "${TMP}/err")"
[ ! -f "${DEST}/boot/loader/entries/aios-rollback.conf" ] \
  || fail "failed-window refusal wrote rollback.conf"

_out=$(run_enact rollback 2)
grep -q 'pre id' "${TMP}/err" \
  || fail "pre id must be refused: $(cat "${TMP}/err")"

_out=$(run_enact rollback 1)
printf '%s\n' "${_out}" | grep -q 'restore @.restore-1' \
  || fail "prepare stdout missing restore: ${_out} err=$(cat "${TMP}/err")"
[ -f "${DEST}/boot/loader/entries/aios-rollback.conf" ] \
  || fail "missing destroot aios-rollback.conf"
grep -Fq 'rootflags=subvol=@.restore-1' \
  "${DEST}/boot/loader/entries/aios-rollback.conf" \
  || fail "rollback.conf missing subvol=@.restore-1"
if grep -F 'rootflags=subvol=@snapshots/' \
  "${DEST}/boot/loader/entries/aios-rollback.conf"
then
  fail "rollback.conf used RO snapper path"
fi
if grep -F 'subvolid=' "${DEST}/boot/loader/entries/aios-rollback.conf"
then
  fail "rollback.conf used subvolid="
fi
grep -Fq 'linux   /aios-gen/1/vmlinuz-linux' \
  "${DEST}/boot/loader/entries/aios-rollback.conf" \
  || fail "rollback.conf linux path"
grep -q '^default aios-rollback.conf$' "${DEST}/boot/loader/loader.conf" \
  || fail "loader.conf default not aios-rollback.conf"
[ -f "${DEST}/run/aios-btrfs/@.restore-1/.aios-restore" ] \
  || fail "destroot did not record RW @.restore-1"

PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" AIOS_CMDLINE='root=UUID=11111111-1111-1111-1111-111111111111 rootflags=subvol=@.restore-1 rw console=tty0' \
  "${ENACT}" rollback 1 >"${TMP}/promote.out" 2>"${TMP}/err" || true
grep -q 'promoted @.restore-1' "${TMP}/promote.out" \
  || fail "promote stdout: $(cat "${TMP}/promote.out") err=$(cat "${TMP}/err")"
[ -f "${DEST}/srv/aios/state/broken-subvol" ] \
  || fail "missing state/broken-subvol (HI-09)"
grep -qx '@.broken-1' "${DEST}/srv/aios/state/broken-subvol" \
  || fail "broken-subvol must record @.broken-1"
[ -d "${DEST}/run/aios-btrfs/@.broken-1" ] \
  || fail "missing destroot @.broken-1"
[ -d "${DEST}/run/aios-btrfs/@" ] \
  || fail "missing destroot @ after promote"
[ ! -e "${DEST}/boot/loader/entries/aios-rollback.conf" ] \
  || fail "aios-rollback.conf survived promote"
grep -Fq 'rootflags=subvol=@' "${DEST}/boot/loader/entries/aios-linux.conf" \
  || fail "aios-linux.conf must use subvol=@ after promote"
if grep -F 'subvolid=' "${DEST}/boot/loader/entries/aios-linux.conf"
then
  fail "aios-linux.conf used subvolid= after promote"
fi
grep -q '^default aios-linux.conf$' "${DEST}/boot/loader/loader.conf" \
  || fail "promote must default aios-linux.conf"
grep -q 'k1-vmlinuz-linux' "${DEST}/boot/vmlinuz-linux" \
  || fail "promote must restore ESP live vmlinuz from aios-gen/1"

PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" AIOS_CMDLINE='root=UUID=11111111-1111-1111-1111-111111111111 rootflags=subvol=@.restore-1 rw console=tty0' \
  "${ENACT}" rollback 1 promote >"${TMP}/promote2.out" 2>"${TMP}/err2" || true
grep -q 'promoted @.restore-1' "${TMP}/promote2.out" \
  || fail "second promote must be idempotent: $(cat "${TMP}/promote2.out") err=$(cat "${TMP}/err2")"
grep -q 'already promoted' "${TMP}/err2" \
  || fail "second promote must log already promoted: $(cat "${TMP}/err2")"

# Serial console writes aios-rollback-serial.conf.
rm -rf "${DEST}/run/aios-btrfs/@.restore-1" "${DEST}/run/aios-btrfs/@.broken-1"
mkdir -p "${DEST}/run/aios-btrfs/@"
PATH="${ORACLE_PATH}" AIOS_ROOT="${DEST}" \
  AIOS_CMDLINE='root=UUID=11111111-1111-1111-1111-111111111111 rw console=tty0 console=ttyS0' \
  "${ENACT}" rollback 1 >"${TMP}/serial.out" 2>"${TMP}/err" || true
[ -f "${DEST}/boot/loader/entries/aios-rollback-serial.conf" ] \
  || fail "serial fixture missing aios-rollback-serial.conf err=$(cat "${TMP}/err")"
grep -Fq 'console=tty0 console=ttyS0' \
  "${DEST}/boot/loader/entries/aios-rollback-serial.conf" \
  || fail "serial rollback.conf consoles"

# TUI files the request; does not sudo or snapshot.
printf '%s\n' 'view snapper' 'rollback 1' 'quit' | \
  AIOS_BRAKE="${TMP}/unused-brake" \
  AIOS_ROOT="${DEST}" \
  AIOS_ESP_GENERATIONS="${DEST}/srv/aios/state/esp-generations" \
  python3 -u "${MAIN}" >"${TMP}/tui.out" || true
grep -q 'rollback 1 requested (L-19' "${TMP}/tui.out" \
  || fail "TUI rollback must request N: $(cat "${TMP}/tui.out")"
grep -qx 'rollback 1' "${DEST}/run/aios/rollback-request" \
  || fail "TUI must write rollback-request"
if grep -Eqi 'sudo|subvolume snapshot' "${TMP}/tui.out"
then
  fail "TUI enacted privileged restore: $(cat "${TMP}/tui.out")"
fi

printf '%s\n' 'view snapper' 'rollback 3' 'quit' | \
  AIOS_BRAKE="${TMP}/unused-brake" \
  AIOS_ROOT="${DEST}" \
  AIOS_ESP_GENERATIONS="${DEST}/srv/aios/state/esp-generations" \
  python3 -u "${MAIN}" >"${TMP}/tui-last.out" || true
grep -q 'failed window' "${TMP}/tui-last.out" \
  || fail "TUI must refuse last post id: $(cat "${TMP}/tui-last.out")"

printf '%s\n' 's' '1' 'quit' | \
  AIOS_BRAKE="${TMP}/unused-brake" \
  AIOS_ROOT="${DEST}" \
  AIOS_ESP_GENERATIONS="${DEST}/srv/aios/state/esp-generations" \
  python3 -u "${MAIN}" >"${TMP}/tui-key.out" || true
grep -q 'rollback 1 requested' "${TMP}/tui-key.out" \
  || fail "snapper digit must select N: $(cat "${TMP}/tui-key.out")"

# Agent tick runs destroot enact (no sudo).
printf '%s\n' 'rollback 1' > "${DEST}/run/aios/rollback-request"
# Restore a prepare-able dest after serial/promote mutations.
rm -rf "${DEST}/run/aios-btrfs/@.restore-1" "${DEST}/run/aios-btrfs/@.broken-1"
mkdir -p "${DEST}/run/aios-btrfs/@"
rm -f "${DEST}/boot/loader/entries/aios-rollback.conf" \
  "${DEST}/boot/loader/entries/aios-rollback-serial.conf"
PATH="${ORACLE_PATH}" \
  AIOS_ROOT="${DEST}" \
  AIOS_ENACT="${ENACT}" \
  PYTHONPATH="${ROOT}/agent/aios_agent" \
  python3 -c 'from rollback_gate import tick_rollback
tick_rollback()' || fail "agent tick_rollback failed"
grep -q '"state":"prepared"' "${DEST}/run/aios/rollback-status" \
  || fail "agent status not prepared: $(cat "${DEST}/run/aios/rollback-status")"
[ -f "${DEST}/boot/loader/entries/aios-rollback.conf" ] \
  || fail "agent tick did not write rollback.conf"
_req=$(cat "${DEST}/run/aios/rollback-request")
[ -z "${_req}" ] || fail "agent tick must clear rollback-request"

_prep_tui=$(
  printf '%s\n' 'view snapper' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${DEST}" \
    AIOS_ESP_GENERATIONS="${DEST}/srv/aios/state/esp-generations" \
    python3 -u "${MAIN}"
) || true
printf '%s\n' "${_prep_tui}" | grep -q 'rollback-status: prepared 1' \
  || fail "TUI must show prepared status: ${_prep_tui}"
printf '%s\n' "${_prep_tui}" | grep -q 'reboot into @.restore-1 (L-19)' \
  || fail "TUI must show restore reboot when prepared: ${_prep_tui}"
printf '%s\n' "${_prep_tui}" | grep -q 'rollback-entry: aios-rollback.conf' \
  || fail "TUI must show rollback entry when prepared: ${_prep_tui}"

# After restore-boot, two ticks must stay promoted (cmdline still names @.restore-N).
: > "${DEST}/run/aios/rollback-request"
PATH="${ORACLE_PATH}" \
  AIOS_ROOT="${DEST}" \
  AIOS_ENACT="${ENACT}" \
  AIOS_CMDLINE='root=UUID=11111111-1111-1111-1111-111111111111 rootflags=subvol=@.restore-1 rw console=tty0' \
  PYTHONPATH="${ROOT}/agent/aios_agent" \
  python3 -c 'from rollback_gate import tick_rollback
tick_rollback()
tick_rollback()' || fail "double tick_rollback on restore cmdline failed"
grep -q '"state":"promoted"' "${DEST}/run/aios/rollback-status" \
  || fail "double tick status not promoted: $(cat "${DEST}/run/aios/rollback-status")"
if grep -q '"state":"refused"' "${DEST}/run/aios/rollback-status"
then
  fail "second tick overwrote promoted to refused: $(cat "${DEST}/run/aios/rollback-status")"
fi
_prom_tui=$(
  printf '%s\n' 'view snapper' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${DEST}" \
    AIOS_ESP_GENERATIONS="${DEST}/srv/aios/state/esp-generations" \
    python3 -u "${MAIN}"
) || true
printf '%s\n' "${_prom_tui}" | grep -q 'rollback-status: promoted 1' \
  || fail "TUI must show promoted status: ${_prom_tui}"
printf '%s\n' "${_prom_tui}" | grep -q 'promoted; reboot into @ (L-19)' \
  || fail "TUI must show @ reboot when promoted: ${_prom_tui}"

# vm-boot-seatbelt fail closed without ISO (do not skip green).
_iso_n=0
for _f in "${ROOT}/dist"/aios-*.iso; do
  [ -f "${_f}" ] || continue
  _iso_n=$((_iso_n + 1))
done
if [ "${_iso_n}" -eq 0 ]; then
  _seat=$("${RUN}" boot-seatbelt 2>&1) && _seat_rc=0 || _seat_rc=$?
  [ "${_seat_rc}" -ne 0 ] \
    || fail "run.sh boot-seatbelt must fail closed without ISO (do not skip green)"
  printf '%s\n' "${_seat}" | grep -q 'fail closed (do not skip green)' \
    || fail "run.sh boot-seatbelt missing fail-closed ISO error: ${_seat}"
fi

if [ "${_live_rb}" -eq 0 ] && [ -e "${LIVE_RB}" ]; then
  fail "oracle created ${LIVE_RB}"
fi
if [ "${_live_btrfs}" -eq 0 ] && [ -e "${LIVE_BTRFS}" ]; then
  fail "oracle created ${LIVE_BTRFS}"
fi
if [ "${_live_broken}" -eq 0 ] && [ -e "${LIVE_BROKEN}" ]; then
  fail "oracle created ${LIVE_BROKEN}"
fi

grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/bin/enact$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin enact"
grep -E '^[0-9a-f]{64}  agent/aios_agent/rollback_gate.py$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin rollback_gate.py"
grep -Eq '^[0-9a-f]{64}  agent/aios_agent/rollback_gate.py$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin rollback_gate.py"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-rollback failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-rollback\n'
exit 0
