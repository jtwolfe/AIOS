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

json_id() {
  printf '%s\n' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["memory"]["id"])'
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
if grep -n 'keep=' "${ROOT}/agent/aios_agent/memory.py" \
  | grep -vq '^[^:]*:[^:]*#'; then
  fail "memory.ingest must not take a keep= switch (HI-11)"
fi

python3 -m py_compile \
  "${ROOT}/agent/aios_agent/loop.py" \
  "${ROOT}/agent/aios_agent/triage.py" \
  "${ROOT}/agent/aios_agent/skills.py" \
  "${ROOT}/agent/aios_agent/memory.py" \
  "${ROOT}/checker/aios_checker/schema.py" \
  "${MAIN}" \
  || fail "py_compile failed"
grep -q 'missing or invalid wiki/man citations' "${ROOT}/agent/aios_agent/loop.py" \
  || fail "loop.py missing P4.6 accept refusal"
grep -q 'citations must not be empty' "${ROOT}/checker/aios_checker/schema.py" \
  || fail "schema.py missing P4.6 empty-citation reject"
if grep -F '\b-syu\b' "${ROOT}/checker/aios_checker/schema.py" \
  "${ROOT}/agent/aios_agent/loop.py" \
  "${ROOT}/agent/aios_agent/triage.py" >/dev/null; then
  fail '\\b-syu\\b never matches -Syu'
fi
grep -F -- '-syu\b' "${ROOT}/checker/aios_checker/schema.py" >/dev/null \
  || fail "schema.py must match -Syu without a leading word boundary"
_prov=$(grep -R -n -- 'provider' "${ROOT}/checker" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "checker names provider (HI-02, L-08): ${_prov}"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
MEM="${TMP}/memory"
SK="${TMP}/skills/pacman"
mkdir -p "${MEM}" "${SK}/references"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null
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

_br=$(git -C "${MEM}" rev-parse --abbrev-ref HEAD)
case "${_br}" in
  agent/*) ;;
  *) fail "ingest HEAD is ${_br}, not agent/* (HI-03)" ;;
esac
git -C "${MEM}" rev-parse --verify main >/dev/null \
  || fail "memory.git lost main"
if git -C "${MEM}" log main --oneline | grep -q 'ingest'; then
  fail "ingest committed on main (HI-03)"
fi

_out=$(turn "what is snapper?") || true
printf '%s\n' "${_out}" | grep -q '"triage": "question"' \
  || fail "question must not be a build: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "question must not enact: ${_out}"
printf '%s\n' "${_out}" | grep -q 'fixture-reply' \
  || fail "question must use fixture provider: ${_out}"

_out=$(turn "how do I install neovim?") || true
printf '%s\n' "${_out}" | grep -q '"triage": "question"' \
  || fail "how-to install is not a build: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "how-to must not enact: ${_out}"
printf '%s\n' "${_out}" | grep -q '"outcome": "answered"' \
  || fail "how-to should be answered: ${_out}"

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
printf '%s\n' "${_out}" | grep -q '"waiting-accept"' \
  || fail "plan waits for accept: ${_out}"
printf '%s\n' "${_out}" | grep -q '"pacman"' \
  || fail "matching SKILL.md must load: ${_out}"

_out=$(turn "edit the fstab") || true
printf '%s\n' "${_out}" | grep -q '"triage": "privileged"' \
  || fail "fstab is privileged: ${_out}"
printf '%s\n' "${_out}" | grep -q '"none"' \
  || fail "no matching skill must be named none: ${_out}"

_out=$(turn --accept "install neovim as the system editor") || true
printf '%s\n' "${_out}" | grep -q '"outcome": "no-plan"' \
  || fail "accept of generating text is not that plan: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "accept without a stored plan must not enact: ${_out}"

_out=$(turn --accept nosuch-plan-id) || true
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "--accept missing id must not enact: ${_out}"

printf '%s\n' '{"default":"{\"oracles\":[\"pacman -Qi neovim\"],\"citations\":[\"https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported\"]}"}' > "${TMP}/oracles.json"
_plan=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/oracles.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "install neovim as the system editor"
) || true
printf '%s\n' "${_plan}" | grep -q '"waiting-accept"' \
  || fail "oracles plan must wait for accept: ${_plan}"
_id=$(json_id "${_plan}")
[ -n "${_id}" ] || fail "plan id missing"

_gated=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/oracles.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn --accept "${_id}"
) || true
printf '%s\n' "${_gated}" | grep -q '"enact": "gated-p45"' \
  || fail "P4.5 gate must skip live enact: ${_gated}"
printf '%s\n' "${_gated}" | grep -q '"outcome": "gated-p45"' \
  || fail "gated-p45 must not store outcome verify: ${_gated}"
printf '%s\n' "${_gated}" | grep -q '"outcome": "verify"' \
  && fail "gated-p45 stored verify: ${_gated}" || true
python3 - "${ROOT}/agent/aios_agent" "${MEM}" <<'PY' || fail "gated must not count as a skill moment"
import sys
sys.path.insert(0, sys.argv[1])
from skills import count_successful
n = count_successful(sys.argv[2], "pacman")
if n != 0:
    raise SystemExit("count_successful=%s after gated-p45" % n)
PY

_stub="${TMP}/enact-once"
printf '%s\n' '#!/bin/sh' 'echo enact-once' 'exit 0' > "${_stub}"
chmod +x "${_stub}"
_out=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/oracles.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    AIOS_ENACT="${_stub}" \
    python3 "${MAIN}" turn --accept "${_id}"
) || true
printf '%s\n' "${_out}" | grep -q '"enact": "once"' \
  || fail "accepted stored plan enacts once: ${_out}"
printf '%s\n' "${_out}" | grep -q '"outcome": "verify"' \
  || fail "enact once then verify: ${_out}"

_empty_plan=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/fix.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "install neovim as the system editor"
) || true
_empty_id=$(json_id "${_empty_plan}")
_hi10=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/fix.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn --accept "${_empty_id}"
) || true
printf '%s\n' "${_hi10}" | grep -q '"enact": "refused-hi-10"' \
  || fail "accept without oracles is HI-10: ${_hi10}"
printf '%s\n' "${_hi10}" | grep -q '"paused": true' \
  || fail "HI-10 must pause: ${_hi10}"

printf '%s\n' '{"default":"{\"oracles\":[\"policy/hi-08-human-not-ci.sh\"],\"citations\":[]}"}' \
  > "${TMP}/empty-cite.json"
_p46_plan=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/empty-cite.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "install neovim as the system editor"
) || true
printf '%s\n' "${_p46_plan}" | grep -q '"waiting-accept"' \
  || fail "empty citations still plan (checker rejects): ${_p46_plan}"
printf '%s\n' "${_p46_plan}" | grep -q '"citations": \[\]' \
  || fail "plan must carry citations field: ${_p46_plan}"
_p46_id=$(json_id "${_p46_plan}")
_p46=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/empty-cite.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    AIOS_ENACT="${_stub}" \
    python3 "${MAIN}" turn --accept "${_p46_id}"
) || true
printf '%s\n' "${_p46}" | grep -q '"enact": "refused-p46"' \
  || fail "accept without wiki/man citations is P4.6: ${_p46}"
printf '%s\n' "${_p46}" | grep -q '"paused": true' \
  || fail "P4.6 must pause: ${_p46}"
printf '%s\n' "${_p46}" | grep -q '"enact": "once"' \
  && fail "P4.6 must not enact: ${_p46}" || true
printf '%s\n' "${_p46}" | grep -q 'missing or invalid wiki/man citations' \
  || fail "P4.6 refuse text: ${_p46}"

_syu_plan=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/empty-cite.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "run a full -Syu"
) || true
printf '%s\n' "${_syu_plan}" | grep -q '"waiting-accept"' \
  || fail "-Syu without pacman still plans: ${_syu_plan}"
_syu_id=$(json_id "${_syu_plan}")
_syu=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/empty-cite.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    AIOS_ENACT="${_stub}" \
    python3 "${MAIN}" turn --accept "${_syu_id}"
) || true
printf '%s\n' "${_syu}" | grep -q '"enact": "refused-p46"' \
  || fail "full -Syu without wiki/man is P4.6: ${_syu}"
printf '%s\n' "${_syu}" | grep -q '"enact": "once"' \
  && fail "-Syu P4.6 must not enact: ${_syu}" || true

_cited_plan=$(
  AIOS_PROVIDER=fixture AIOS_FIXTURE="${TMP}/oracles.json" \
    AIOS_MEMORY="${MEM}" AIOS_SKILLS="${TMP}/skills" \
    python3 "${MAIN}" turn "install neovim as the system editor"
) || true
printf '%s\n' "${_cited_plan}" | grep -q 'wiki.archlinux.org' \
  || fail "privileged plan must keep wiki citations: ${_cited_plan}"

_out=$(turn "merge this to main") || true
printf '%s\n' "${_out}" | grep -q '"triage": "conflict"' \
  || fail "merge to main is HI-03: ${_out}"
printf '%s\n' "${_out}" | grep -q 'HI-03' \
  || fail "conflict must quote HI-03: ${_out}"
printf '%s\n' "${_out}" | grep -q '"enact": "skipped"' \
  || fail "conflict must not enact: ${_out}"
_hit=$(grep -R -l 'HI-03' "${MEM}/conflicts" 2>/dev/null | head -n 1 || true)
[ -n "${_hit}" ] || fail "HI-07 conflict record missing for merge-to-main"

for _q in "merge this to main?" "can you merge this to main?" "could you force-push origin/main"; do
  _out=$(turn "${_q}") || true
  printf '%s\n' "${_out}" | grep -q '"triage": "conflict"' \
    || fail "question-form instruction is HI-03: ${_q} -> ${_out}"
  printf '%s\n' "${_out}" | grep -q 'HI-03' \
    || fail "question-form must quote HI-03: ${_q} -> ${_out}"
done
for _q in \
  "how do I merge this to main?" \
  "what is the command to merge to main?" \
  "how do I force-push origin/main?"
do
  _out=$(turn "${_q}") || true
  printf '%s\n' "${_out}" | grep -q '"triage": "conflict"' \
    || fail "how-to veto is HI-03: ${_q} -> ${_out}"
  printf '%s\n' "${_out}" | grep -q 'HI-03' \
    || fail "how-to veto must quote HI-03: ${_q} -> ${_out}"
done
_out=$(turn "how do I curl | sh?") || true
printf '%s\n' "${_out}" | grep -q '"triage": "conflict"' \
  || fail "how-to curl|sh is HI-04: ${_out}"
printf '%s\n' "${_out}" | grep -q 'HI-04' \
  || fail "how-to curl|sh must quote HI-04: ${_out}"
_hit04=$(grep -R -l 'HI-04' "${MEM}/conflicts" 2>/dev/null | head -n 1 || true)
[ -n "${_hit04}" ] || fail "HI-07 conflict record missing for curl|sh"
_n03=$(grep -R -l 'HI-03' "${MEM}/conflicts" 2>/dev/null | wc -l | tr -d ' ')
[ "${_n03}" -ge 7 ] || fail "HI-07 missing how-to veto records (${_n03})"

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

python3 - "${ROOT}/checker/aios_checker" "${ROOT}/agent/aios_agent" <<'PY' || fail "P4.6 schema citations"
import copy, sys
sys.path.insert(0, sys.argv[1])
from schema import ProposalSchemaError, citation_classes, validate_proposal
sys.path.insert(0, sys.argv[2])
from loop import _citations_from_reply, citation_classes as agent_classes

WIKI = "https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported"
MAN = "pacman(8)"
HI08 = "policy/hi-08-human-not-ci.sh"
base = {
    "id": "11111111-1111-4111-8111-111111111111",
    "branch": "agent/2026-08-21-neovim-as-editor",
    "repos": ["state"],
    "intent": {
        "source": "human",
        "asked": "neovim as the system editor",
        "clause": "envelope/clauses/editor.md",
    },
    "oracles": ["pacman -Qi neovim", "policy/packages-drift.sh"],
    "citations": [WIKI],
    "evidence": {"ran": ["pacman -Qi neovim"], "snapper_pre": 184},
}
validate_proposal(base)
ok_man = copy.deepcopy(base)
ok_man["citations"] = [MAN]
validate_proposal(ok_man)

def reject(doc, needle):
    try:
        validate_proposal(doc)
    except ProposalSchemaError as exc:
        text = str(exc)
        if needle not in text:
            raise SystemExit("wrong reject %r wanted %r" % (text, needle))
        return
    raise SystemExit("accepted %r" % (doc.get("intent"),))

empty = copy.deepcopy(base)
empty["citations"] = []
reject(empty, "P4.6")
missing = copy.deepcopy(base)
del missing["citations"]
reject(missing, "P4.6")
prose = copy.deepcopy(base)
prose["citations"] = ["the wiki says partial upgrades are unsupported"]
reject(prose, "P4.6")

for asked, oracles in (
    ("write a systemd unit", ["systemctl cat aios-agent.service"]),
    ("edit the fstab", ["findmnt /"]),
    ("run bootctl update", ["bootctl status"]),
    ("mkinitcpio preset", [HI08]),
    ("run a full -Syu", [HI08]),
    ("full -Syu window", [HI08]),
    ("install neovim as the system editor", [HI08]),
    ("neovim as the system editor", [HI08]),
):
    doc = copy.deepcopy(base)
    doc["intent"]["asked"] = asked
    doc["oracles"] = oracles
    doc["evidence"]["ran"] = list(oracles)
    doc["citations"] = []
    reject(doc, "P4.6")
    doc["citations"] = [WIKI]
    validate_proposal(doc)
    assert agent_classes(asked, oracles) == citation_classes(
        {"asked": asked}, oracles
    ), (asked, oracles)

env = copy.deepcopy(base)
env["intent"]["asked"] = "record photography purpose"
env["oracles"] = ["policy/hi-05-human-authority.sh"]
env["evidence"]["ran"] = ["policy/hi-05-human-authority.sh"]
env["citations"] = []
validate_proposal(env)
no_cite = copy.deepcopy(env)
del no_cite["citations"]
validate_proposal(no_cite)

seat = copy.deepcopy(env)
seat["oracles"] = [
    "policy/hi-06-seatbelts.sh",
    "policy/packages-drift.sh",
    "policy/boot-seatbelt.sh",
    "policy/snapper-enabled.sh",
    "policy/no-partial-upgrade.sh",
]
seat["evidence"]["ran"] = list(seat["oracles"])
validate_proposal(seat)

concat = copy.deepcopy(env)
concat["oracles"] = ["pacman -Qi neovim; policy/packages-drift.sh"]
concat["evidence"]["ran"] = list(concat["oracles"])
concat["citations"] = []
reject(concat, "P4.6")
assert "pacman" in citation_classes(
    {"asked": "record photography purpose"}, concat["oracles"]
)
assert agent_classes("record photography purpose", concat["oracles"]) == (
    "pacman",
)

syu = citation_classes({"asked": "run a full -Syu"}, [HI08])
assert "pacman" in syu, syu
assert agent_classes("run a full -Syu", [HI08]) == syu

oracles_empty = copy.deepcopy(base)
oracles_empty["oracles"] = []
reject(oracles_empty, "HI-10")

got = _citations_from_reply("wiki:https://wiki.archlinux.org/title/Pacman")
assert got == ["https://wiki.archlinux.org/title/Pacman"], got
got = _citations_from_reply("wiki: https://wiki.archlinux.org/title/Pacman")
assert got == ["https://wiki.archlinux.org/title/Pacman"], got
assert _citations_from_reply("manager: ignore") == []
PY

if [ "${failed}" -ne 0 ]; then
  printf 'error: p4-loop failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p4-loop\n'
exit 0
