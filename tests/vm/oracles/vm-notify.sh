#!/bin/sh
# P7.2 VM: dummy unit fail → HI-14 payload on notify + OS conversation.
# Fail closed without ISO. Do not skip green (HI-08). Dummy unit fail is guest-only.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)
DIST="${ROOT}/dist"
NOTIFY="${ROOT}/operator-client/tty/notify.py"
POLICY="${ROOT}/checker/policy/hi-14-failure-handoff.sh"
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ -f "${NOTIFY}" ] || die "missing ${NOTIFY}"
[ -f "${POLICY}" ] || die "missing ${POLICY}"
grep -q 'HI-14' "${NOTIFY}" || die "notify.py must quote HI-14"
grep -q 'not a coding CLI' "${NOTIFY}" || die "notify.py must say not a coding CLI"
if grep -Eiq 'four-field|four field' "${NOTIFY}"; then
  die "must not call HI-14 four-field"
fi

_iso=
_n=0
for _f in "${DIST}"/aios-*.iso; do
  [ -f "${_f}" ] || continue
  _iso=${_f}
  _n=$((_n + 1))
done
[ "${_n}" -gt 0 ] || die "no dist/aios-*.iso; fail closed (do not skip green)"
[ "${_n}" -eq 1 ] || die "multiple dist/aios-*.iso; leave one"

if [ "${AIOS_VM_BOOT:-0}" != 1 ]; then
  die "AIOS_VM_BOOT=1 required for dummy unit fail; fail closed (do not skip green)"
fi

die "dummy unit fail on ${_iso} is not claimed without a guest boot; fail closed (do not skip green)"
