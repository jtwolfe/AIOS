#!/bin/sh
# P8.14 / P8.10: own fixture/token isolation. L-16 L-17 L-08.
# Must not require a live Grok token.
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
  printf 'ok: vm-work-provider (guest). L-16 L-17.\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-provider
p814_payload_no_src
grep -q 'OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"' \
  "${P814_ROOT}/agent/aios_agent/provider/base.py" \
  || die "OS token path lock drifted"
grep -q 'FixtureProvider' \
  "${P814_ROOT}/agent/aios_agent/provider/fixture.py" \
  || die "missing fixture provider"
_hit=$(grep -R -n -- 'provider' "${P814_ROOT}/checker" 2>/dev/null | head -n 1 || true)
[ -z "${_hit}" ] || die "checker names provider (HI-02, L-08): ${_hit}"
_path=$(python3 "${P814_ROOT}/agent/aios_agent/main.py" provider path)
[ "${_path}" = "/srv/aios/state/provider/os.token" ] \
  || die "provider path is ${_path}"

p814_drive_installer
p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: login$' \
  || die "login view missing: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'L-17' \
  || die "login view must quote L-17: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -Eqi 'xai-|sk-live|GROK_API' \
  && die "login view leaked a live token: ${P814_TUI_OUT}" || true

p814_wrap_p8 provider
p814_wrap_host "${P814_ROOT}/tests/oracles/p4-provider.sh"
p814_finish
