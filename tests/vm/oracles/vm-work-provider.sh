#!/bin/sh
# P8.14 / P8.10: own fixture/token isolation. Must not require a live Grok token.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  command -v sudo >/dev/null 2>&1 || die "sudo missing; OS token isolation cannot fail closed"
  id -u aios-work >/dev/null 2>&1 || die "aios-work uid missing; OS token isolation cannot fail closed"
  _token=/srv/aios/state/provider/os.token
  if sudo -u aios-work test -r "${_token}"; then
    die "aios-work can read OS token (L-16)"
  fi
  printf 'ok: vm-work-provider (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-provider
p814_payload_no_src
p814_drive_installer
p814_drive_tui os os_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^view: login$' \
  || die "login view missing: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -Eqi 'xai-|sk-live|GROK_API' \
  && die "login view leaked a live token: ${P814_TUI_OUT}" || true
p814_must_close provider
p814_wrap_host_required "${P814_ROOT}/tests/oracles/p4-provider.sh"
p814_finish
