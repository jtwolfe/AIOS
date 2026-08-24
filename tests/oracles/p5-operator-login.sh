#!/bin/sh
# P5.4: one asked operator login, no enact sudo (L-13). Skip ≠ username.
# Envelope: P5.4, L-13, L-09, L-17, L-20, HI-09, HI-15.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/installer/aios_installer/main.py"
LOGIN="${ROOT}/installer/aios_installer/login.py"
QUESTIONS="${ROOT}/installer/aios_installer/questions.py"
HI="${ROOT}/docs/envelope/hard-invariants.md"
ISO_INST="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
AIROOTFS="${ROOT}/payload/profile/airootfs"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${LOGIN}" ] || fail "missing ${LOGIN}"
[ -f "${QUESTIONS}" ] || fail "missing ${QUESTIONS}"
[ -f "${ISO_INST}/aios_installer/login.py" ] || fail "missing ISO login.py"

grep -q 'L-13' "${LOGIN}" || fail "login.py must quote L-13"
grep -q 'L-13' "${QUESTIONS}" || fail "questions.py must quote L-13"
grep -q 'HI-15' "${QUESTIONS}" || fail "questions.py must quote HI-15"
grep -q 'AIOS_ROOT' "${LOGIN}" || fail "login.py must honor AIOS_ROOT"
grep -q 'useradd' "${LOGIN}" || fail "login.py must use useradd on the installed disk"
grep -q 'L-13' "${MAIN}" || fail "main.py must quote L-13 on accept"
grep -q 'asked' "${ROOT}/installer/README.md" \
  || fail "README must close operator username as asked"
grep -q 'return "leave"' "${MAIN}" || fail "accept must leave the TUI (L-09)"
grep -q 'handoff_console' "${MAIN}" || fail "main.py must hand off the console after accept"
grep -q 'handoff_console' "${LOGIN}" || fail "login.py must hand off the console after accept"
grep -q -- '--no-block' "${LOGIN}" \
  || fail "getty start must be --no-block (Conflicts deadlock)"
grep -q '/usr/lib/aios/bin/installer' "${LOGIN}" \
  || fail "dest_root must use installer binary, not the wants link"
grep -q '/etc/aios' "${LOGIN}" \
  || fail "dest_root must use /etc/aios so mask cannot un-accept"
if grep -q 'usr/lib/systemd/system/aios-installer' "${LOGIN}"; then
  fail "must not move the installer unit under /usr (HI-04)"
fi

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' "${ROOT}/installer" "${ISO_INST}" 2>/dev/null; then
  fail "installer contains -Syu (L-20)"
fi

if grep -R -q -- 'synthesi' "${ROOT}/installer" 2>/dev/null; then
  grep -R -q 'HI-15' "${ROOT}/installer" \
    || fail "installer mentions synthesis without HI-15"
fi

if grep -q 'u operator' "${AIROOTFS}/usr/lib/sysusers.d/aios.conf" 2>/dev/null; then
  fail "operator must not be a sysuser in aios.conf (L-13)"
fi

if [ -e "${AIROOTFS}/etc/systemd/system/multi-user.target.wants/aios-installer.service" ]; then
  fail "aios-installer.service must not be enabled on the live ISO (L-09)"
fi

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

python3 -m py_compile \
  "${MAIN}" \
  "${QUESTIONS}" \
  "${LOGIN}" \
  "${ROOT}/installer/aios_installer/compiler.py" \
  "${ROOT}/installer/aios_installer/recover.py" \
  || fail "py_compile failed"

_pyct=$(mktemp -d)
cp -a "${ISO_INST}/aios_installer/." "${_pyct}/" \
  || fail "copy ISO python for py_compile"
python3 -m py_compile \
  "${_pyct}/main.py" \
  "${_pyct}/questions.py" \
  "${_pyct}/login.py" \
  "${_pyct}/compiler.py" \
  "${_pyct}/recover.py" \
  || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${0}" || fail "sh -n p5-operator-login.sh"

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

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
_live_existed=0
[ -e "${LIVE_BIP}" ] && _live_existed=1
WR_BEFORE=0
if [ -e /srv/aios/src/work-runtime ]; then
  WR_BEFORE=1
fi

drive() {
  _boot=$1
  _dest=$2
  shift 2
  mkdir -p "${_boot}" "${_dest}"
  printf '%s\n' "$@" | AIOS_BOOTSTRAP="${_boot}" AIOS_ROOT="${_dest}" \
    AIOS_HI="${HI}" python3 -u "${MAIN}"
}

has_alice() {
  _tree=$1
  [ -f "${_tree}/etc/passwd" ] || return 1
  grep -E '^alice:' "${_tree}/etc/passwd" >/dev/null
}

expect_alice() {
  _label=$1
  _tree=$2
  _boot=$3
  [ -f "${_tree}/etc/passwd" ] || fail "${_label}: missing etc/passwd"
  [ -f "${_tree}/etc/shadow" ] || fail "${_label}: missing etc/shadow"
  [ -f "${_tree}/etc/group" ] || fail "${_label}: missing etc/group"
  grep -E '^alice:' "${_tree}/etc/passwd" >/dev/null \
    || fail "${_label}: passwd missing alice"
  grep -E '^alice:' "${_tree}/etc/shadow" >/dev/null \
    || fail "${_label}: shadow missing alice"
  grep -E '^alice:' "${_tree}/etc/group" >/dev/null \
    || fail "${_label}: group missing alice"
  grep -E '^alice:[^:]*:[0-9]+:[0-9]+:' "${_tree}/etc/passwd" >/dev/null \
    || fail "${_label}: alice is not a passwd record"
  grep -E 'nologin' "${_tree}/etc/passwd" | grep -E '^alice:' >/dev/null \
    && fail "${_label}: alice must be a human login, not nologin" || true
  [ -d "${_tree}/home/alice" ] || fail "${_label}: missing home/alice"
  _drop="${_tree}/srv/aios/state/brake.d"
  [ -d "${_drop}" ] || fail "${_label}: missing brake drop dir (L-12)"
  _dmode=$(stat -c '%a' "${_drop}")
  [ "${_dmode}" = 1731 ] \
    || fail "${_label}: brake drop must be 1731, got ${_dmode}"
  _state=$(dirname "${_drop}")
  _smode=$(stat -c '%a' "${_state}")
  case "${_smode}" in
    *777*) fail "${_label}: must not chmod 0777 /srv/aios/state" ;;
  esac
  _tty1="${_tree}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
  _ser="${_tree}/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf"
  [ -f "${_tty1}" ] || fail "${_label}: missing tty1 autologin drop-in"
  [ -f "${_ser}" ] || fail "${_label}: missing serial autologin drop-in"
  grep -q -- '--autologin alice' "${_tty1}" \
    || fail "${_label}: tty1 autologin is not alice"
  grep -q -- '--autologin alice' "${_ser}" \
    || fail "${_label}: serial autologin is not alice"
  grep -q -- '--autologin root' "${_tty1}" "${_ser}" \
    && fail "${_label}: autologin must not be root" || true
  grep -q -- 'aios-agent' "${_tty1}" "${_ser}" \
    && fail "${_label}: autologin must not name aios-agent" || true
  grep -q -- 'firstboot' "${_tty1}" "${_ser}" \
    && fail "${_label}: operator getty must not exec firstboot" || true
  if [ -e "${_tree}/etc/systemd/system/multi-user.target.wants/aios-installer.service" ]; then
    fail "${_label}: installer must not stay enabled after accept (L-09)"
  fi
  _mask="${_tree}/etc/systemd/system/aios-installer.service"
  [ -L "${_mask}" ] || fail "${_label}: installer unit must be masked"
  [ "$(readlink "${_mask}")" = /dev/null ] \
    || fail "${_label}: installer mask must be /dev/null"
  [ ! -e "${_tree}/usr/lib/systemd/system/aios-installer.service" ] \
    || fail "${_label}: must not copy the unit under /usr (HI-04)"
  [ -f "${_tree}/etc/aios/operator" ] || fail "${_label}: missing /etc/aios/operator"
  grep -qx 'alice' "${_tree}/etc/aios/operator" \
    || fail "${_label}: /etc/aios/operator must be alice"
  if [ -d "${_tree}/etc/sudoers.d" ] || [ -f "${_tree}/etc/sudoers" ]; then
    if grep -R -E '^[[:space:]]*alice[[:space:]]' \
      "${_tree}/etc/sudoers" "${_tree}/etc/sudoers.d" 2>/dev/null | grep -q .
    then
      fail "${_label}: operator must not have a sudoers line"
    fi
    if grep -R -q 'NOPASSWD: ALL' "${_tree}/etc/sudoers" "${_tree}/etc/sudoers.d" 2>/dev/null
    then
      fail "${_label}: sudoers must not grant ALL"
    fi
    if grep -R -q 'enact' "${_tree}/etc/sudoers" "${_tree}/etc/sudoers.d" 2>/dev/null
    then
      fail "${_label}: operator must not sudo enact (L-13)"
    fi
  fi
  python3 - "${_boot}/answers.json" <<'PY' || fail "${_label}: answers.json"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("operator") != "alice":
    raise SystemExit("operator not alice: %r" % data.get("operator"))
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots key must be absent or false")
if data.get("bots") is True:
    raise SystemExit("bots must not be true")
if data.get("accepted") is not True:
    raise SystemExit("accepted must be JSON true, got %r" % data.get("accepted"))
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime must stay false (HI-15)")
PY
}

expect_refused() {
  _label=$1
  _out=$2
  _tree=$3
  if printf '%s\n' "${_out}" | grep -q Traceback; then
    fail "${_label}: traceback-exited: ${_out}"
  fi
  printf '%s\n' "${_out}" | grep -q 'accept refused' \
    || fail "${_label}: must refuse accept: ${_out}"
  printf '%s\n' "${_out}" | grep -q 'L-13' \
    || fail "${_label}: refuse must quote L-13: ${_out}"
  printf '%s\n' "${_out}" | grep -q 'envelope-decision: accepted' \
    && fail "${_label}: must not record accepted: ${_out}" || true
  printf '%s\n' "${_out}" | grep -q 'view: questions' \
    || fail "${_label}: must stay on questions: ${_out}"
  if has_alice "${_tree}"; then
    fail "${_label}: created alice despite refuse"
  fi
}

# Happy path: asked alice, accept, one human login, no enact sudo.
BOOT_OK="${TMP}/boot-ok"
ROOT_OK="${TMP}/root-ok"
_ok=$(
  drive "${BOOT_OK}" "${ROOT_OK}" \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit'
) || true
if printf '%s\n' "${_ok}" | grep -q Traceback; then
  fail "alice accept traceback: ${_ok}"
fi
printf '%s\n' "${_ok}" | grep -q 'envelope-decision: accepted' \
  || fail "alice accept missing: ${_ok}"
printf '%s\n' "${_ok}" | grep -q 'work-runtime: false' \
  || fail "skip work-runtime must stay false: ${_ok}"
expect_alice "alice-accept" "${ROOT_OK}" "${BOOT_OK}"

# Resume with the same snapshot must not create a second human login.
_ok2=$(
  drive "${BOOT_OK}" "${ROOT_OK}" 'view recovery' 'quit'
) || true
if printf '%s\n' "${_ok2}" | grep -q Traceback; then
  fail "resume traceback: ${_ok2}"
fi
_n=$(grep -cE '^alice:' "${ROOT_OK}/etc/passwd" || true)
[ "${_n}" -eq 1 ] || fail "resume duplicated alice passwd lines: ${_n}"
_humans=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /nologin|false$/ {print $1}' \
  "${ROOT_OK}/etc/passwd")
_hc=$(printf '%s\n' "${_humans}" | grep -c . || true)
[ "${_hc}" -eq 1 ] || fail "must be exactly one human login: ${_humans}"

# Skip / empty / reserved names: refuse, no user.
BOOT_SKIP="${TMP}/boot-skip"
ROOT_SKIP="${TMP}/root-skip"
_skip=$(
  drive "${BOOT_SKIP}" "${ROOT_SKIP}" \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    'skip operator' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "skip" "${_skip}" "${ROOT_SKIP}"

BOOT_EMPTY="${TMP}/boot-empty"
ROOT_EMPTY="${TMP}/root-empty"
_empty=$(
  drive "${BOOT_EMPTY}" "${ROOT_EMPTY}" \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    'answer operator' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "empty" "${_empty}" "${ROOT_EMPTY}"

for _case in root aios-agent aios-checker aios-work; do
  _b="${TMP}/boot-${_case}"
  _r="${TMP}/root-${_case}"
  _out=$(
    drive "${_b}" "${_r}" \
      'answer purpose a lab vm' \
      'skip work-runtime' \
      "answer operator ${_case}" \
      'view envelope' \
      'accept' \
      'quit'
  ) || true
  expect_refused "${_case}" "${_out}" "${_r}"
done

# Purpose text is not a username.
BOOT_PURP="${TMP}/boot-purpose"
ROOT_PURP="${TMP}/root-purpose"
_purp=$(
  drive "${BOOT_PURP}" "${ROOT_PURP}" \
    'answer purpose alice' \
    'skip work-runtime' \
    'skip operator' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "purpose-as-username" "${_purp}" "${ROOT_PURP}"
if [ -f "${BOOT_PURP}/answers.json" ]; then
  python3 - "${BOOT_PURP}/answers.json" <<'PY' || fail "purpose must not become operator"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("operator"):
    raise SystemExit("operator derived from purpose: %r" % data.get("operator"))
if data.get("purpose") != "alice":
    raise SystemExit("purpose not persisted: %r" % data.get("purpose"))
if data.get("accepted") is True:
    raise SystemExit("purpose-as-username must not accept")
PY
fi

# Uppercase / leading digit are not POSIX portable.
BOOT_BAD="${TMP}/boot-bad"
ROOT_BAD="${TMP}/root-bad"
_bad=$(
  drive "${BOOT_BAD}" "${ROOT_BAD}" \
    'answer operator Alice' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "uppercase" "${_bad}" "${ROOT_BAD}"

BOOT_DIG="${TMP}/boot-dig"
ROOT_DIG="${TMP}/root-dig"
_dig=$(
  drive "${BOOT_DIG}" "${ROOT_DIG}" \
    'answer operator 1alice' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "leading-digit" "${_dig}" "${ROOT_DIG}"

# One human login: a pre-existing human blocks a second.
BOOT_TWO="${TMP}/boot-two"
ROOT_TWO="${TMP}/root-two"
mkdir -p "${ROOT_TWO}/etc" "${ROOT_TWO}/home/bob"
printf '%s\n' 'bob:x:1000:1000::/home/bob:/bin/bash' > "${ROOT_TWO}/etc/passwd"
printf '%s\n' 'bob:!:0:0:99999:7:::' > "${ROOT_TWO}/etc/shadow"
printf '%s\n' 'bob:x:1000:' > "${ROOT_TWO}/etc/group"
_two=$(
  drive "${BOOT_TWO}" "${ROOT_TWO}" \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "second-human" "${_two}" "${ROOT_TWO}"
grep -E '^bob:' "${ROOT_TWO}/etc/passwd" >/dev/null \
  || fail "second-human: clobbered bob"
grep -E '^alice:' "${ROOT_TWO}/etc/passwd" >/dev/null \
  && fail "second-human: created alice beside bob" || true

# Existing nologin/system account is not the operator (L-13).
BOOT_DAE="${TMP}/boot-daemon"
ROOT_DAE="${TMP}/root-daemon"
mkdir -p "${ROOT_DAE}/etc"
printf '%s\n' 'daemon:x:2:2:daemon:/:/usr/bin/nologin' > "${ROOT_DAE}/etc/passwd"
printf '%s\n' 'daemon:!:0:0:99999:7:::' > "${ROOT_DAE}/etc/shadow"
printf '%s\n' 'daemon:x:2:' > "${ROOT_DAE}/etc/group"
_dae=$(
  drive "${BOOT_DAE}" "${ROOT_DAE}" \
    'answer operator daemon' \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "service-uid" "${_dae}" "${ROOT_DAE}"
grep -E '^daemon:[^:]*:2:' "${ROOT_DAE}/etc/passwd" >/dev/null \
  || fail "service-uid: clobbered daemon"
_tty_dae="${ROOT_DAE}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
if [ -f "${_tty_dae}" ] && grep -q -- '--autologin daemon' "${_tty_dae}"; then
  fail "service-uid: must not autologin daemon"
fi

# Passwd-only human record must be completed (shadow/group/home).
BOOT_INC="${TMP}/boot-inc"
ROOT_INC="${TMP}/root-inc"
mkdir -p "${ROOT_INC}/etc"
printf '%s\n' 'alice:x:1000:1000::/home/alice:/bin/bash' > "${ROOT_INC}/etc/passwd"
_inc=$(
  drive "${BOOT_INC}" "${ROOT_INC}" \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit'
) || true
if printf '%s\n' "${_inc}" | grep -q Traceback; then
  fail "incomplete-user traceback: ${_inc}"
fi
printf '%s\n' "${_inc}" | grep -q 'envelope-decision: accepted' \
  || fail "incomplete-user accept missing: ${_inc}"
expect_alice "incomplete-user" "${ROOT_INC}" "${BOOT_INC}"

# archisobasedir=arch is a live ISO (not a bare token).
python3 - "${ROOT}/installer/aios_installer" <<'PY' || fail "cmdline archisobasedir= was not matched"
import sys

sys.path.insert(0, sys.argv[1])
import login

if not login.cmdline_is_archiso("BOOT archisobasedir=arch quiet"):
    raise SystemExit("archisobasedir=arch must count as live ISO")
if not login.cmdline_is_archiso("archisobasedir"):
    raise SystemExit("bare archisobasedir must count as live ISO")
if login.cmdline_is_archiso("BOOT quiet"):
    raise SystemExit("unrelated cmdline must not count as live ISO")
PY

# Host-safety: AIOS_ROOT unset must not mutate the workstation.
HOST_PASS="${TMP}/host.passwd"
HOST_GROUP="${TMP}/host.group"
cp -a /etc/passwd "${HOST_PASS}"
cp -a /etc/group "${HOST_GROUP}" 2>/dev/null || true
_had_home=0
[ -e /home/alice ] && _had_home=1
BOOT_HOST="${TMP}/boot-host"
mkdir -p "${BOOT_HOST}"
_host=$(
  printf '%s\n' \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit' | AIOS_BOOTSTRAP="${BOOT_HOST}" AIOS_HI="${HI}" python3 -u "${MAIN}"
) || true
if printf '%s\n' "${_host}" | grep -q Traceback; then
  fail "host-safety traceback: ${_host}"
fi
printf '%s\n' "${_host}" | grep -q 'envelope-decision: accepted' \
  && fail "accept without AIOS_ROOT must not succeed on the workstation: ${_host}" || true
cmp -s /etc/passwd "${HOST_PASS}" \
  || fail "accept without AIOS_ROOT mutated /etc/passwd"
if [ -f "${HOST_GROUP}" ]; then
  cmp -s /etc/group "${HOST_GROUP}" \
    || fail "accept without AIOS_ROOT mutated /etc/group"
fi
if [ "${_had_home}" -eq 0 ] && [ -e /home/alice ]; then
  fail "accept without AIOS_ROOT created /home/alice"
fi

# Malformed input must not traceback-exit the TTY unit.
BOOT_MAL="${TMP}/boot-mal"
ROOT_MAL="${TMP}/root-mal"
_long=$(python3 -c 'print("a" * 80)')
_mal=$(
  drive "${BOOT_MAL}" "${ROOT_MAL}" \
    "answer operator ${_long}" \
    'view envelope' \
    'accept' \
    'quit'
) || true
expect_refused "overlong" "${_mal}" "${ROOT_MAL}"

# ISO copy: same accept path.
BOOT_ISO="${TMP}/boot-iso"
ROOT_ISO="${TMP}/root-iso"
_iso=$(
  mkdir -p "${BOOT_ISO}" "${ROOT_ISO}"
  printf '%s\n' \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    'answer operator alice' \
    'view envelope' \
    'accept' \
    'quit' | AIOS_BOOTSTRAP="${BOOT_ISO}" AIOS_ROOT="${ROOT_ISO}" \
      AIOS_HI="${HI}" python3 -u "${ISO_INST}/aios_installer/main.py"
) || true
if printf '%s\n' "${_iso}" | grep -q Traceback; then
  fail "ISO accept traceback: ${_iso}"
fi
printf '%s\n' "${_iso}" | grep -q 'envelope-decision: accepted' \
  || fail "ISO accept missing: ${_iso}"
expect_alice "iso-accept" "${ROOT_ISO}" "${BOOT_ISO}"

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src/work-runtime ]; then
  fail "operator login created /srv/aios/src/work-runtime (HI-15)"
fi
if [ "${_live_existed}" -eq 0 ] && [ -e "${LIVE_BIP}" ]; then
  fail "oracle created ${LIVE_BIP} (HI-09)"
fi

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

while IFS= read -r line || [ -n "${line}" ]; do
  [ -n "${line}" ] || continue
  case "${line}" in
    \#*) continue ;;
  esac
  hash=${line%% *}
  path=${line#* }
  path=${path# }
  case "${path}" in
    /*) f="${AIROOTFS}${path}" ;;
    *) f="${AIROOTFS}/usr/lib/aios/${path}" ;;
  esac
  [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
  printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
    || fail "ISO hash mismatch: ${path}"
done < "${ISO_HASHES}"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p5-operator-login failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p5-operator-login\n'
exit 0
