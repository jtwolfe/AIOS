#!/bin/sh
# P8.14 / P8.6: token-in-chat fails; OS key unreadable. MCP preferred.
# Fixture provider. No live Grok token. HI-16 L-16.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  _token=/srv/aios/state/provider/os.token
  if [ -e "${_token}" ] && command -v sudo >/dev/null 2>&1; then
    if id -u aios-work >/dev/null 2>&1 && sudo -u aios-work test -r "${_token}"; then
      die "aios-work can read OS token (L-16)"
    fi
  fi
  printf 'ok: vm-work-connector (guest). L-16.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-connector
p814_payload_no_src
[ -f "${SEED}/skills/connectors.md" ] || die "missing skills/connectors.md"
grep -q 'If a Connector exists for a service, use it' \
  "${SEED}/skills/connectors.md" \
  || die "connectors.md must prefer MCP"
grep -q 'Do not ask for tokens in chat' "${SEED}/skills/connectors.md" \
  || die "connectors.md must refuse token-in-chat"
grep -q 'OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"' \
  "${P814_ROOT}/agent/aios_agent/provider/base.py" \
  || die "OS token path lock drifted"
_hit=$(python3 "${P814_ROOT}/agent/aios_agent/main.py" provider path)
[ "${_hit}" = "/srv/aios/state/provider/os.token" ] \
  || die "provider path is ${_hit}, not the L-16 lock"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: connectors$' \
  || die "connectors view missing: ${P814_TUI_OUT}"

p814_wrap_p8 connector
p814_wrap_p8 connectors
p814_wrap_host "${P814_ROOT}/tests/oracles/p4-provider.sh"
p814_finish
