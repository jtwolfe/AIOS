#!/bin/sh
# P4.1: deny.py and enact must refuse the same seatbelt/self/path fixtures.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
DENY="${ROOT}/agent/aios_agent/main.py"
ENACT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

need_tag() {
  _out=$1
  _tag=$2
  _what=$3
  printf '%s\n' "${_out}" | grep -q "${_tag}" \
    || fail "${_what} missing ${_tag}"
}

run_deny() {
  python3 "${DENY}" deny "$@" 2>&1 || true
}

run_enact() {
  "${ENACT}" "$@" 2>&1 || true
}

deny_rc() {
  python3 "${DENY}" deny "$@" >/dev/null 2>&1 && printf 0 || printf 1
}

enact_rc() {
  "${ENACT}" "$@" >/dev/null 2>&1 && printf 0 || printf 1
}

[ -f "${DENY}" ] || fail "missing ${DENY}"
[ -x "${ENACT}" ] || fail "missing executable ${ENACT}"

# argv: ACTION UNIT TAG
# Both must exit non-zero and mention TAG.
while IFS= read -r _line; do
  [ -n "${_line}" ] || continue
  case "${_line}" in
    \#*) continue ;;
  esac
  _act=${_line%% *}
  _rest=${_line#* }
  _unit=${_rest%% *}
  _tag=${_rest#* }
  _d_out=$(run_deny unit "${_act}" "${_unit}")
  _e_out=$(run_enact unit "${_act}" "${_unit}")
  _d_rc=$(deny_rc unit "${_act}" "${_unit}")
  _e_rc=$(enact_rc unit "${_act}" "${_unit}")
  [ "${_d_rc}" != 0 ] || fail "deny.py allowed unit ${_act} ${_unit}"
  [ "${_e_rc}" != 0 ] || fail "enact allowed unit ${_act} ${_unit}"
  need_tag "${_d_out}" "${_tag}" "deny.py unit ${_act} ${_unit}"
  need_tag "${_e_out}" "${_tag}" "enact unit ${_act} ${_unit}"
done <<'EOF'
disable aios-checker.service HI-06
restart aios-checker.service HI-06
kill aios-checker.service HI-06
reload aios-checker.service HI-06
disable /etc/systemd/system/aios-checker.service HI-06
restart /etc/systemd/system/aios-checker.service HI-06
disable snapper-timeline.timer HI-06
mask snapper-cleanup.timer HI-06
disable etckeeper.timer HI-06
stop etckeeper.service HI-06
stop aios-agent.service L-12
restart aios-agent.service L-12
kill aios-agent.service L-12
enable aios-work-runtime.service L-23
disable sshd.service aios-*
EOF

_d_out=$(run_deny unit start aios-installer.service)
_d_rc=$(deny_rc unit start aios-installer.service)
[ "${_d_rc}" = 0 ] || fail "deny.py refused unit start aios-installer.service: ${_d_out}"

_e_out=$(run_enact pacman -S foo)
need_tag "${_e_out}" "L-04" "enact pacman"

_e_out=$(run_enact -Syu)
need_tag "${_e_out}" "L-04" "enact -Syu"

_e_out=$(run_enact syu)
need_tag "${_e_out}" "L-04" "enact syu as non-root"
[ "$(enact_rc syu)" != 0 ] || fail "enact syu allowed as non-root"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p4-enact-deny failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p4-enact-deny\n'
exit 0
