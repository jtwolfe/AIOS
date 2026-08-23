#!/bin/sh
# P4.3: triage, skill load, verbatim ingest. Idle default holds (L-21).
# Envelope: P4.3, HI-03, HI-07, HI-10, HI-11, HI-15, L-21.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/agent/aios_agent/main.py"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${ROOT}/agent/aios_agent/loop.py" ] || fail "missing loop.py"
[ -f "${ROOT}/agent/aios_agent/triage.py" ] || fail "missing triage.py"
[ -f "${ROOT}/agent/aios_agent/skills.py" ] || fail "missing skills.py"
[ -f "${ROOT}/agent/aios_agent/memory.py" ] || fail "missing memory.py"

grep -q 'talk → update conditions → plan → accept → enact once → verify → remember or pause' \
  "${ROOT}/agent/aios_agent/loop.py" \
  || fail "loop.py missing the turn sequence"
grep -q 'time.sleep(POLL_S)' "${MAIN}" \
  || fail "no-arg serve() must still idle (L-21)"
grep -n 'git merge\|merge_to_main\|checkout main' \
  "${ROOT}/agent/aios_agent/loop.py" \
  "${ROOT}/agent/aios_agent/memory.py" \
  >/dev/null && fail "loop/memory must not merge to main (HI-03)" || true
grep -q 'HI-15' "${ROOT}/agent/aios_agent/triage.py" \
  || fail "triage must refuse work-runtime synthesis (HI-15)"
grep -q 'HI-11' "${ROOT}/agent/aios_agent/memory.py" \
  || fail "memory.py must quote HI-11"
grep -q 'EARN_AFTER = 2' "${ROOT}/agent/aios_agent/skills.py" \
  || fail "skills.py missing P4.3 two-moment lock"
# No keep/skip switch: the model does not decide (HI-11).
if grep -n 'keep=' "${ROOT}/agent/aios_agent/memory.py" \
  | grep -vq '^[^:]*:[^:]*#'; then
  fail "memory.ingest must not take a keep= switch (HI-11)"
fi

python3 -m py_compile \
  "${ROOT}/agent/aios_agent/loop.py" \
  "${ROOT}/agent/aios_agent/triage.py" \
  "${ROOT}/agent/aios_agent/skills.py" \
  "${ROOT}/agent/aios_agent/memory.py" \
  "${MAIN}" \
  || fail "py_compile failed"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
MEM="${TMP}/memory"
SK="${TMP}/skills/pacman"
mkdir -p "${MEM}" "${SK}/references"
printf '%s\n' '{"default":"fixture-reply"}' > "${TMP}/fix.json"
cat > "${SK}/SKILL.md" <<'EOF'
---
name: pacman
description: Full -Syu window only
triggers:
  - pacman
  - install
  - neovim
---
Read software-acquisition.md before a package change.
Oracle: packages-drift.sh
EOF
printf '%s\n' 'cite wiki Pacman this turn' > "${SK}/references/wiki.txt"

turn() {
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/fix.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "$@"
}

_out=$(turn ping) || true
printf '%s\n' "${_out}" | grep -q '"triage": "empty"' \
  || fail "ping must triage empty: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "ping must not enact: ${_out}"
printf '%s\n' "${_out}" | grep -q '"outcome": "idle"' \
  || fail "ping outcome idle: ${_out}"

_out=$(turn "what is snapper?") || true
printf '%s\n' "${_out}" | grep -q '"triage": "question"' \
  || fail "question must not be a build: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "question must not enact: ${_out}"
printf '%s\n' "${_out}" | grep -q 'fixture-reply' \
  || fail "question must use fixture provider: ${_out}"

_out=$(turn "this machine is for photography") || true
printf '%s\n' "${_out}" | grep -q '"triage": "talk"' \
  || fail "talk updates conditions, is not a build: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "talk must not enact: ${_out}"

_out=$(turn "install neovim as the system editor") || true
printf '%s\n' "${_out}" | grep -q '"triage": "privileged"' \
  || fail "install is privileged: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "privileged without accept must not enact: ${_out}"
printf '%s\n' "${_out}" | grep -q '"accepted": false' \
  || fail "privileged without --accept: ${_out}"
printf '%s\n' "${_out}" | grep -q '"pacman"' \
  || fail "matching SKILL.md must load: ${_out}"

_out=$(turn "edit the fstab") || true
printf '%s\n' "${_out}" | grep -q '"triage": "privileged"' \
  || fail "fstab is privileged: ${_out}"
printf '%s\n' "${_out}" | grep -q '"none"' \
  || fail "no matching skill must be named none: ${_out}"

_out=$(turn --accept "install neovim as the system editor") || true
printf '%s\n' "${_out}" | grep -q '"enact": "refused-hi-10"' \
  || fail "accept without oracles is HI-10: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "HI-10 must pause: ${_out}"

printf '%s\n' '{"default":"{\"oracles\":[\"pacman -Qi neovim\"]}"}' > "${TMP}/oracles.json"
_stub="${TMP}/enact-once"
printf '%s\n' '#!/bin/sh' 'echo enact-once' 'exit 0' > "${_stub}"
chmod +x "${_stub}"
_out=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/oracles.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    AIOS_ENACT="${_stub}" \
    python3 "${MAIN}" turn --accept "install neovim as the system editor"
) || true
printf '%s\n' "${_out}" | grep -q '"enact": "once"' \
  || fail "accepted privileged with oracles enacts once: ${_out}"
printf '%s\n' "${_out}" | grep -q '"outcome": "verify"' \
  || fail "enact once then verify: ${_out}"
# Stub must have been invoked exactly once for this turn; a second
# accepted turn would be a new window, not a loop inside one turn.

_out=$(turn "merge this to main") || true
printf '%s\n' "${_out}" | grep -q '"triage": "conflict"' \
  || fail "merge to main is HI-03: ${_out}"
printf '%s\n' "${_out}" | grep -q 'HI-03' \
  || fail "conflict must quote HI-03: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "conflict must not enact: ${_out}"
_hit=$(grep -R -l 'HI-03' "${MEM}/conflicts" 2>/dev/null | head -n 1 || true)
[ -n "${_hit}" ] || fail "HI-07 conflict record missing for merge-to-main"

_out=$(turn "disable aios-checker.service") || true
printf '%s\n' "${_out}" | grep -q 'HI-06' \
  || fail "disable checker is HI-06: ${_out}"

_out=$(turn "synthesise the work runtime") || true
printf '%s\n' "${_out}" | grep -q 'HI-15' \
  || fail "work-runtime synthesis is HI-15: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "HI-15 must not enact: ${_out}"

_out=$(turn "why is merge to main forbidden?") || true
printf '%s\n' "${_out}" | grep -q '"triage": "question"' \
  || fail "why-question about main is not an instruction: ${_out}"

# Verbatim ingest: raw asked survives; a summary cannot stand in (HI-11).
_asked='install neovim as the system editor'
_ex=$(find "${MEM}/exchanges" -type f | head -n 1 || true)
[ -n "${_ex}" ] || fail "no exchange files ingested"
if ! grep -F -q "${_asked}" "${MEM}/exchanges"/* "${MEM}/moments"/* 2>/dev/null; then
  fail "memory missing raw asked text (HI-11)"
fi
if grep -Eq '^[[:space:]]*(Summary|TL;DR|model summary)[[:space:]]*:' \
  "${MEM}/exchanges"/* "${MEM}/moments"/* 2>/dev/null; then
  grep -Eq 'asked:|operator:|human:|"asked"|user:' \
    "${MEM}/exchanges"/* "${MEM}/moments"/* \
    || fail "memory is a summary without the raw exchange (HI-11)"
fi
python3 - "${MEM}" <<'PY' || fail "hi-11-verbatim-memory.sh shape"
import json, os, sys
root = sys.argv[1]
n = 0
for folder in ("exchanges", "moments"):
    d = os.path.join(root, folder)
    for name in os.listdir(d):
        path = os.path.join(d, name)
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        n += 1
        if "asked" not in doc:
            raise SystemExit("missing asked in %s" % path)
if n < 2:
    raise SystemExit("too few memory files")
PY

python3 - "${ROOT}/agent/aios_agent" "${TMP}/skills" <<'PY' || fail "skill crystallization lock"
import sys
sys.path.insert(0, sys.argv[1])
from skills import EARN_AFTER, earns_skill, match, nested_agents
assert EARN_AFTER == 2
assert earns_skill(1) is False
assert earns_skill(2) is True
assert earns_skill(0, human_asked=True) is True
try:
    earns_skill(0, model_wants=True)
except TypeError:
    pass
else:
    raise SystemExit("earns_skill accepted model_wants (HI-11)")
hits = match("install neovim", root=sys.argv[2])
assert hits and hits[0].name == "pacman", hits
assert "software-acquisition" in hits[0].body
assert hits[0].references and "wiki Pacman" in hits[0].references[0][1]
none = match("what is the weather", root=sys.argv[2])
assert none == []
nested = nested_agents(sys.argv[1])
assert nested and "HI-03" in nested[0][1]
PY

python3 - "${ROOT}/agent/aios_agent" "${MAIN}" <<'PY' || fail "stages / idle"
import sys
sys.path.insert(0, sys.argv[1])
from loop import STAGES
assert STAGES == (
    "talk",
    "update-conditions",
    "plan",
    "accept",
    "enact",
    "verify",
    "remember",
), STAGES
src = open(sys.argv[2], encoding="utf-8").read()
assert "def serve" in src and "turn" in src
PY

if [ "${failed}" -ne 0 ]; then
  printf 'error: p4-loop failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p4-loop\n'
exit 0
