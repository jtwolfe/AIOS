#!/bin/sh
# P5.1: L-18 installer views. Skip ≠ yes. No sysupgrade. No work-runtime synthesis.
# Envelope: P5.1, L-09, L-12, L-18, L-20, HI-02, HI-15.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/installer/aios_installer/main.py"
ISO_INST="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/installer"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
HASHES="${ROOT}/payload/hashes.txt"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${ROOT}/installer/aios_installer/questions.py" ] || fail "missing questions.py"
[ -f "${ROOT}/installer/aios_installer/compiler.py" ] || fail "missing compiler.py"
[ -f "${ROOT}/installer/aios_installer/recover.py" ] || fail "missing recover.py"
[ -f "${ISO_INST}/aios_installer/main.py" ] || fail "missing ISO installer main.py"
[ -x "${ISO_BIN}" ] || fail "ISO bin/installer must be executable"

for _id in chrome conversation questions envelope accept recovery; do
  grep -q "${_id}" "${MAIN}" \
    || fail "main.py missing view id ${_id} (L-18)"
done

grep -q 'L-18' "${MAIN}" || fail "main.py must quote L-18"
grep -q 'L-09' "${MAIN}" || fail "main.py must quote L-09"
grep -q 'L-12' "${MAIN}" || fail "main.py must quote L-12"
grep -q 'L-20' "${MAIN}" || fail "main.py must quote L-20"
grep -q 'HI-15' "${ROOT}/installer/aios_installer/questions.py" \
  || fail "questions.py must quote HI-15"
grep -q 'L-18' "${ROOT}/installer/aios_installer/recover.py" \
  || fail "recover.py must quote L-18"
grep -q 'p5.2' "${ROOT}/installer/aios_installer/compiler.py" \
  || fail "compiler.py must note the compiler is P5.2"

grep -q 'exec /usr/bin/python3' "${ISO_BIN}" \
  || fail "bin/installer must exec python3"
grep -q 'aios_installer/main.py' "${ISO_BIN}" \
  || fail "bin/installer must launch aios_installer/main.py"
grep -q 'L-09' "${ISO_BIN}" || fail "bin/installer must quote L-09"

grep -q 'aios_installer/main.py' "${FIRSTBOOT}" \
  || fail "firstboot must copy installer main.py"
grep -q 'payload installer source missing' "${FIRSTBOOT}" \
  || fail "firstboot must require installer source"

python3 -m py_compile \
  "${ROOT}/installer/aios_installer/main.py" \
  "${ROOT}/installer/aios_installer/questions.py" \
  "${ROOT}/installer/aios_installer/compiler.py" \
  "${ROOT}/installer/aios_installer/recover.py" \
  "${ROOT}/installer/aios_installer/login.py" \
  "${ISO_INST}/aios_installer/main.py" \
  "${ISO_INST}/aios_installer/questions.py" \
  "${ISO_INST}/aios_installer/compiler.py" \
  "${ISO_INST}/aios_installer/recover.py" \
  "${ISO_INST}/aios_installer/login.py" \
  || fail "py_compile failed"

sh -n "${ISO_BIN}" || fail "sh -n bin/installer"
sh -n "${FIRSTBOOT}" || fail "sh -n firstboot"

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' \
  "${ROOT}/installer" \
  "${ISO_BIN}" \
  "${FIRSTBOOT}" \
  "${ISO_INST}" 2>/dev/null
then
  fail "installer/firstboot contains -Syu (L-20)"
fi

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  cmp -s "${ROOT}/installer/${rel}" "${ISO_INST}/${rel}" \
    || fail "ISO installer ${rel} bytes differ"
done <<EOF
$(cd "${ROOT}/installer" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  [ -f "${ROOT}/installer/${rel}" ] \
    || fail "ISO extra file ${rel} not in installer source"
done <<EOF
$(cd "${ISO_INST}" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF

UNIT="${ROOT}/payload/profile/airootfs/etc/systemd/system/aios-installer.service"
grep -qx 'ExecStart=/usr/lib/aios/bin/installer' "${UNIT}" \
  || fail "aios-installer.service must ExecStart bin/installer"
grep -qx 'TTYPath=/dev/console' "${UNIT}" \
  || fail "aios-installer.service must TTYPath=/dev/console"
if [ -e "${ROOT}/payload/profile/airootfs/etc/systemd/system/multi-user.target.wants/aios-installer.service" ]; then
  fail "aios-installer.service must not be enabled on the live ISO (L-09)"
fi

if grep -R -qi 'synthesi' "${ROOT}/installer" 2>/dev/null; then
  grep -R -q 'HI-15' "${ROOT}/installer" \
    || fail "installer mentions synthesis without HI-15"
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
_live_existed=0
[ -e "${LIVE_BIP}" ] && _live_existed=1
drive() {
  _boot=$(mktemp -d "${TMP}/boot.XXXXXX")
  printf '%s\n' "$@" | AIOS_BOOTSTRAP="${_boot}" python3 -u "${MAIN}"
}

_out=$(drive \
  'view questions' \
  'skip work-runtime' \
  'answer purpose a lab vm' \
  'view envelope' \
  'view accept' \
  'view recovery' \
  'resume' \
  'brake' \
  'mode os' \
  'mode work' \
  'quit') || true

printf '%s\n' "${_out}" | grep -q 'view: questions' \
  || fail "fixture never opened questions: ${_out}"
printf '%s\n' "${_out}" | grep -q 'view: envelope' \
  || fail "envelope view not reachable without transcript scroll: ${_out}"
printf '%s\n' "${_out}" | grep -q 'view: accept' \
  || fail "accept view missing: ${_out}"
printf '%s\n' "${_out}" | grep -q 'view: recovery' \
  || fail "recovery view missing: ${_out}"
printf '%s\n' "${_out}" | grep -q 'skip: not-yes' \
  || fail "skip work-runtime must be not-yes: ${_out}"
printf '%s\n' "${_out}" | grep -q 'work-runtime: true' \
  && fail "skip work-runtime must not set the bit true: ${_out}" || true
printf '%s\n' "${_out}" | grep -q 'work-runtime: false' \
  || fail "skip work-runtime must leave the bit false: ${_out}"
printf '%s\n' "${_out}" | grep -q 'purpose: a lab vm' \
  || fail "purpose answer missing: ${_out}"
printf '%s\n' "${_out}" | grep -q 'actions: accept reject' \
  || fail "accept/reject keys missing on envelope/accept: ${_out}"
printf '%s\n' "${_out}" | grep -q 'resume: last-step=' \
  || fail "recovery resume action missing: ${_out}"
printf '%s\n' "${_out}" | grep -q 'L-12' \
  || fail "brake must quote L-12: ${_out}"
printf '%s\n' "${_out}" | grep -q 'mode refused' \
  || fail "OS/work mode switch must be refused: ${_out}"
printf '%s\n' "${_out}" | grep -q 'compiler: p5.2' \
  || fail "envelope draft must note compiler is P5.2: ${_out}"
printf '%s\n' "${_out}" | grep -q 'catalog: chrome conversation questions envelope accept recovery' \
  || fail "catalog missing L-18 ids: ${_out}"
printf '%s\n' "${_out}" | grep -q '"bots"' \
  && fail "answers must not include a bots key: ${_out}" || true

_yes=$(drive 'answer work-runtime yes' 'quit') || true
printf '%s\n' "${_yes}" | grep -q 'work-runtime: true' \
  || fail "explicit yes must set the bit: ${_yes}"

# First question is purpose; named skip of work-runtime is the HI-15 case.
_skip2=$(drive 'skip work-runtime' 'quit') || true
printf '%s\n' "${_skip2}" | grep -q 'work-runtime: true' \
  && fail "named skip must not be yes: ${_skip2}" || true
printf '%s\n' "${_skip2}" | grep -q 'work-runtime: false' \
  || fail "named skip must leave false: ${_skip2}"

_acc_root=$(mktemp -d "${TMP}/accroot.XXXXXX")
_acc=$(
  _boot=$(mktemp -d "${TMP}/boot.XXXXXX")
  printf '%s\n' \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit' | AIOS_BOOTSTRAP="${_boot}" AIOS_ROOT="${_acc_root}" python3 -u "${MAIN}"
) || true
printf '%s\n' "${_acc}" | grep -q 'envelope-decision: accepted' \
  || fail "accept action missing: ${_acc}"
_rej=$(drive 'view envelope' 'reject' 'quit') || true
printf '%s\n' "${_rej}" | grep -q 'envelope-decision: rejected' \
  || fail "reject action missing: ${_rej}"

_rec=$(drive 'view recovery' 'quit') || true
printf '%s\n' "${_rec}" | grep -q 'view: recovery' \
  || fail "recovery view cannot be opened: ${_rec}"
printf '%s\n' "${_rec}" | grep -q 'snapper-id:' \
  || fail "recovery missing snapper-id: ${_rec}"
printf '%s\n' "${_rec}" | grep -q 'last-step:' \
  || fail "recovery missing last-step: ${_rec}"

_conv=$(drive 'view conversation' 'send is the envelope a view?' 'quit') || true
printf '%s\n' "${_conv}" | grep -q 'turn-ended: question' \
  || fail "questions must end the conversation turn: ${_conv}"
printf '%s\n' "${_conv}" | grep -q 'view: conversation' \
  || fail "conversation view missing: ${_conv}"

_ch=$(drive 'view chrome' 'quit') || true
printf '%s\n' "${_ch}" | grep -q 'mode: installer' \
  || fail "chrome must name mode installer: ${_ch}"
printf '%s\n' "${_ch}" | grep -q 'actions: view brake send mode' \
  || fail "chrome actions missing: ${_ch}"

_colon=$(drive ':' '::' 'view chrome' 'quit') || true
printf '%s\n' "${_colon}" | grep -q 'list index' \
  && fail "colon must be a blank command: ${_colon}" || true
printf '%s\n' "${_colon}" | grep -q 'error:' \
  && fail "colon must not print error: ${_colon}" || true
printf '%s\n' "${_colon}" | grep -q 'view: chrome' \
  || fail "command after colon must still run: ${_colon}"

if grep -n 'sleep(3600)' "${MAIN}" >/dev/null; then
  fail "TTY path must not sleep(3600) on EOF (L-09)"
fi
grep -q 'signal.SIG_IGN' "${MAIN}" \
  || fail "TTY must ignore SIGINT so readline is not interrupted (L-09)"

mkdir -p "${TMP}/brake-boot"
_br=$(
  AIOS_BOOTSTRAP="${TMP}/brake-boot" \
  AIOS_BRAKE="${TMP}/brake" python3 -u "${MAIN}" <<'EOF'
brake
quit
EOF
) || true
[ -f "${TMP}/brake" ] || fail "brake must write AIOS_BRAKE"
printf '%s\n' "${_br}" | grep -q 'brake: on' \
  || fail "brake flag missing: ${_br}"

printf x > "${TMP}/brake_notdir"
mkdir -p "${TMP}/brake-fail-boot" "${TMP}/brake-fail-root"
_br_fail=$(
  AIOS_BOOTSTRAP="${TMP}/brake-fail-boot" \
  AIOS_ROOT="${TMP}/brake-fail-root" \
  AIOS_BRAKE="${TMP}/brake_notdir/nested" python3 -u "${MAIN}" <<'EOF'
answer operator alice
brake
view envelope
accept
quit
EOF
) || true
[ ! -e "${TMP}/brake_notdir/nested" ] || fail "failed brake must not create a file"
printf '%s\n' "${_br_fail}" | grep -q 'brake: on' \
  && fail "brake must not claim on when the file is missing: ${_br_fail}" || true
printf '%s\n' "${_br_fail}" | grep -q 'brake failed' \
  || fail "failed brake must report OSError: ${_br_fail}"
printf '%s\n' "${_br_fail}" | grep -q 'envelope-decision: accepted' \
  || fail "failed brake must not freeze writes: ${_br_fail}"

mkdir -p "${TMP}/pty-boot"
python3 - "${MAIN}" "${TMP}/pty-boot" <<'PY' || fail "PTY Ctrl+D/Ctrl+C must keep the TUI up (L-09)"
import os
import pty
import select
import signal
import sys
import time

main = sys.argv[1]
boot = sys.argv[2]
ROUNDS = 8


def still_running(pid):
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == 0:
        return True, None
    return False, status


def drain_until(fd, needle, timeout=3.0):
    buf = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remain = min(0.2, max(0.0, deadline - time.monotonic()))
        ready, _, _ = select.select([fd], [], [], remain)
        if not ready:
            if needle in buf:
                break
            continue
        try:
            chunk = os.read(fd, 8192)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if needle in buf:
            extra, _, _ = select.select([fd], [], [], 0.05)
            if extra:
                try:
                    buf += os.read(fd, 8192)
                except OSError:
                    pass
            break
    quiet_until = time.monotonic() + 0.08
    while time.monotonic() < quiet_until:
        ready, _, _ = select.select([fd], [], [], 0.04)
        if not ready:
            break
        try:
            chunk = os.read(fd, 8192)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        quiet_until = time.monotonic() + 0.08
    return buf


def wait_read_block(pid, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        alive, status = still_running(pid)
        if not alive:
            return False, status
        blocked = False
        try:
            wchan = open(
                "/proc/%d/wchan" % pid, encoding="ascii", errors="replace"
            ).read().strip()
        except OSError:
            wchan = ""
        if wchan and wchan not in ("0",):
            blocked = True
        try:
            sc = open(
                "/proc/%d/syscall" % pid, encoding="ascii", errors="replace"
            ).read().split()
            if sc and sc[0] in ("0", "19", "63", "0x0", "0x13", "0x3f"):
                blocked = True
        except OSError:
            pass
        if blocked:
            return True, None
        time.sleep(0.02)
    return False, None


pid, master = pty.fork()
if pid == 0:
    os.environ["AIOS_BOOTSTRAP"] = boot
    os.execv(sys.executable, [sys.executable, "-u", main])
    os._exit(127)

buf = b""
died = None
try:
    chunk = drain_until(master, b"view: questions")
    buf += chunk
    if b"Traceback" in buf:
        raise SystemExit("traceback on TTY during start: %s" % buf)
    ok, status = wait_read_block(pid)
    if not ok:
        raise SystemExit("child not blocked in readline after start status=%s" % status)
    os.write(master, b"\x04")
    ok, status = wait_read_block(pid)
    if not ok:
        raise SystemExit("child not blocked in readline after Ctrl+D status=%s" % status)
    os.write(master, b"view chrome\n")
    buf += drain_until(master, b"view: chrome")
    alive, status = still_running(pid)
    if not alive:
        died = "Ctrl+D"
        raise SystemExit("child died after Ctrl+D status=%s" % status)
    if b"view: chrome" not in buf:
        raise SystemExit("Ctrl+D then view did not render: %s" % buf)
    for _round in range(ROUNDS):
        ok, status = wait_read_block(pid)
        if not ok:
            raise SystemExit(
                "child not blocked in readline before Ctrl+C round %s status=%s"
                % (_round, status)
            )
        os.write(master, b"\x03")
        # VINTR flushes the input queue when n_tty sees it; wait until the
        # child is still blocked in read after that byte has been consumed.
        settle = time.monotonic() + 0.05
        while time.monotonic() < settle:
            alive, status = still_running(pid)
            if not alive:
                died = "Ctrl+C"
                raise SystemExit(
                    "child died after Ctrl+C round %s status=%s" % (_round, status)
                )
            time.sleep(0.01)
        ok, status = wait_read_block(pid)
        if not ok:
            alive, status = still_running(pid)
            if not alive:
                died = "Ctrl+C"
                raise SystemExit(
                    "child died after Ctrl+C round %s status=%s" % (_round, status)
                )
            raise SystemExit(
                "child not blocked in readline after Ctrl+C round %s" % _round
            )
        os.write(master, b"view envelope\n")
        got = drain_until(master, b"view: envelope")
        buf += got
        alive, status = still_running(pid)
        if not alive:
            died = "Ctrl+C"
            raise SystemExit(
                "child died after Ctrl+C round %s status=%s" % (_round, status)
            )
        if b"Traceback" in got or b"Traceback" in buf:
            raise SystemExit("traceback on TTY after Ctrl+C: %s" % buf)
        if b"view: envelope" not in got:
            raise SystemExit(
                "next view not rendered after Ctrl+C round %s: %s" % (_round, got)
            )
        ok, status = wait_read_block(pid)
        if not ok:
            raise SystemExit(
                "child not blocked in readline after envelope round %s status=%s"
                % (_round, status)
            )
        os.write(master, b"view chrome\n")
        buf += drain_until(master, b"view: chrome")
finally:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass
    try:
        os.close(master)
    except OSError:
        pass

text = buf.decode("utf-8", "replace")
if died:
    raise SystemExit("child died after %s" % died)
if "Traceback" in text:
    raise SystemExit("traceback on TTY: %s" % text)
PY

if [ "${_live_existed}" -eq 0 ] && [ -e "${LIVE_BIP}" ]; then
  fail "oracle created ${LIVE_BIP} (HI-09)"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p5-installer-views failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p5-installer-views\n'
exit 0
