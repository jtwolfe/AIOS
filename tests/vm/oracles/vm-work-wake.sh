#!/bin/sh
# P8.14 / P8.4: wake inject order; explicit send; question ends the turn.
# Fixture provider. No live Grok token.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/common.sh"

guest_oracle() {
  [ -f /srv/aios/src/work-runtime/wake.py ] \
    || [ -f /srv/aios/seeds/work-runtime/skills/wake.md ] \
    || die "guest missing wake surface"
  printf 'ok: vm-work-wake (guest).\n'
}

if p814_is_guest; then
  p814_refuse_worktree
  guest_oracle
  exit 0
fi

p814_begin work-wake
p814_payload_no_src
[ -f "${SEED}/skills/wake.md" ] || die "missing seed skills/wake.md"
grep -q 'This tree'\''s `AGENTS.md`' "${SEED}/skills/wake.md" \
  || die "wake.md must inject AGENTS.md first"
grep -q 'Skills catalog' "${SEED}/skills/wake.md" \
  || die "wake.md must inject skills catalog"
grep -q 'Tools from' "${SEED}/skills/wake.md" \
  || die "wake.md must inject tools"
grep -q 'Operational notes' "${SEED}/skills/wake.md" \
  || die "wake.md must inject operational notes"
grep -q 'Envelope bit' "${SEED}/skills/wake.md" \
  || die "wake.md must inject envelope bit"
grep -q 'Do not inject a personality' "${SEED}/skills/wake.md" \
  || die "wake.md must refuse psyche"
grep -q 'explicit send' "${SEED}/boundaries/interfaces.md" \
  || die "interfaces.md must require explicit send"
grep -q 'Ends the turn' "${SEED}/boundaries/interfaces.md" \
  || die "interfaces.md must end the turn on a question"

p814_drive_installer
p814_drive_tui work work_commands
printf '%s\n' "${P814_TUI_OUT}" | grep -q '^mode: work$' \
  || die "wake work session missing: ${P814_TUI_OUT}"
printf '%s\n' "${P814_TUI_OUT}" | grep -q 'turn-ended: question' \
  || die "question must end the turn: ${P814_TUI_OUT}"

p814_wrap_p8 wake
p814_finish
