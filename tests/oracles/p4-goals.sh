#!/bin/sh
# P4.4: idle default, event-driven repair, stall pause (L-21).
# Envelope: P4.4, L-21, L-19, L-20, HI-03, HI-08, HI-10, HI-14, HI-15.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/agent/aios_agent/main.py"
GOALS="${ROOT}/agent/aios_agent/goals.py"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${GOALS}" ] || fail "missing goals.py"

grep -q 'L-21' "${GOALS}" || fail "goals.py must quote L-21"
grep -q 'HI-15' "${GOALS}" || fail "goals.py must quote HI-15"
grep -q 'HI-17' "${GOALS}" || fail "goals.py must quote HI-17"
grep -q 'HI-10' "${GOALS}" || fail "goals.py must quote HI-10"
grep -q 'HI-14' "${GOALS}" || fail "goals.py must quote HI-14"
grep -q 'HI-03' "${GOALS}" || fail "goals.py must quote HI-03"
grep -q 'HI-08' "${GOALS}" || fail "goals.py must quote HI-08"
grep -q 'L-19' "${GOALS}" || fail "goals.py must quote L-19"
grep -q 'SAME_GAP = 2' "${GOALS}" || fail "goals.py missing SAME_GAP = 2"
grep -q 'idle is the default' "${GOALS}" || fail "goals.py missing idle default"
grep -q 'time.sleep(POLL_S)' "${MAIN}" \
  || fail "no-arg serve() must still idle (L-21)"
grep -q 'cmd_goals' "${MAIN}" || fail "main.py must wire goals CLI"

if grep -n 'git merge\|merge_to_main\|checkout main' "${GOALS}" >/dev/null; then
  fail "goals.py must not merge to main (HI-03)"
fi
if grep -nE 'shutil|copytree|systemctl' "${GOALS}" | grep -v '^[^:]*:[[:space:]]*#' >/dev/null; then
  fail "goals.py must not copy trees or call systemctl (L-20)"
fi
if grep -n 'work.runtime' "${GOALS}" | grep -qi 'synthesi'; then
  grep -q 'work_runtime_yes' "${GOALS}" \
    || fail "goals.py synthesis must be gated on work_runtime_yes (HI-15)"
fi
if grep -Eq 'oracles.*=.*\["true"\]|oracles.*=.*\("true"\)' "${GOALS}"; then
  fail "goals.py must not invent true as an oracle (HI-08, HI-10)"
fi

python3 -m py_compile "${GOALS}" "${MAIN}" \
  || fail "py_compile failed"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
MEM="${TMP}/memory"
mkdir -p "${MEM}" "${TMP}/notify"
git -C "${MEM}" init -b main >/dev/null
git -C "${MEM}" config user.name aios
git -C "${MEM}" config user.email aios@localhost
printf '%s\n' '# memory' > "${MEM}/README.md"
git -C "${MEM}" add README.md
git -C "${MEM}" -c user.name=aios -c user.email=aios@localhost \
  commit -m 'chore(memory): initialise tree' >/dev/null

goals() {
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    python3 "${MAIN}" goals "$@"
}

_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "empty events must idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": false' \
  || fail "empty events must not pause: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "empty events invent no proposal: ${_out}"
printf '%s\n' "${_out}" | grep -q '"invented": false' \
  || fail "empty events invented=false: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "empty events must not synthesise work-runtime: ${_out}"
[ ! -f "${TMP}/goals.json" ] \
  || fail "idle with no file must not persist a self-driving state"

_out=$(goals tick) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "restart with empty events must idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "restart with empty events invents no proposal: ${_out}"

printf '%s\n' 'not-json' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "corrupt goals must restore paused: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "corrupt goals must pause: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "corrupt restore must not propose: ${_out}"
printf '%s\n' "${_out}" | grep -q 'L-21' \
  || fail "corrupt restore must quote L-21: ${_out}"
python3 - "${TMP}/goals.json" <<'PY' || fail "corrupt file not rewritten paused"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("status") == "paused", doc
PY

printf '%s\n' '{"status":"self-driving","declared":[]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "unknown status must restore paused: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "unknown status must not propose: ${_out}"

printf '%s\n' '{"status":"idle","declared":["hobbyist"]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "unknown declared goal must restore paused: ${_out}"

printf '%s\n' '{"status":"idle","declared":["sysupgrade"],"rounds":"nope"}' > "${TMP}/goals.json"
_out=$(goals 2>"${TMP}/err") || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "corrupt rounds must restore paused: ${_out}"
printf '%s\n' "${_out}" | grep -q Traceback \
  && fail "corrupt rounds traceback: ${_out}" || true
if grep -q Traceback "${TMP}/err"; then
  fail "corrupt rounds traceback on stderr"
fi
python3 - "${TMP}/goals.json" <<'PY' || fail "corrupt rounds file not rewritten paused"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("status") == "paused", doc
PY

printf '%s\n' '{"status":"waiting-accept","last_gap":"fp1","gap_count":"x","proposal":{"oracles":["policy/packages-drift.sh"]}}' > "${TMP}/goals.json"
_out=$(goals gap fp1 2>"${TMP}/err") || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "corrupt gap_count must restore paused: ${_out}"
if grep -q Traceback "${TMP}/err"; then
  fail "corrupt gap_count traceback on stderr"
fi

printf '%s\n' '{"status":"idle","declared":[],"proposal":["not-a-dict"]}' > "${TMP}/goals.json"
_out=$(goals '{"kind":"unit-failed","unit":"x.service"}' 2>"${TMP}/err") || true
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "corrupt proposal must restore paused: ${_out}"
if grep -q Traceback "${TMP}/err"; then
  fail "corrupt proposal traceback on stderr"
fi

rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"unit-failed","unit":"aios-checker.service","journal":"slice","commit":"abc","snapper_id":1,"clause":"HI-14"}') || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "unit-failed is event-driven repair: ${_out}"
printf '%s\n' "${_out}" | grep -q 'machine-goal' \
  || fail "repair intent source machine-goal: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/hi-14-failure-handoff.sh' \
  || fail "unit-failed must use named HI-14 oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q 'not-while-planning' \
  || fail "repair must not enact while planning: ${_out}"
printf '%s\n' "${_out}" | grep -q '"invented": false' \
  || fail "repair invented=false: ${_out}"
printf '%s\n' "${_out}" | grep -q '"true"' \
  && fail "repair invented true oracle: ${_out}" || true
_resume=$(goals tick) || true
printf '%s\n' "${_resume}" | grep -q '"status": "waiting-accept"' \
  || fail "empty restart must resume the plan, not invent: ${_resume}"
printf '%s\n' "${_resume}" | grep -q 'policy/hi-14-failure-handoff.sh' \
  || fail "resume must keep original oracles: ${_resume}"
printf '%s\n' "${_resume}" | grep -q '"invented": false' \
  || fail "resume invented=false: ${_resume}"

_out=$(goals gap oracle-gap-1) || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  && fail "first gap must not pause: ${_out}" || true

_out=$(goals gap oracle-gap-1) || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "same-gap twice must pause: ${_out}"
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "same-gap twice status paused: ${_out}"
printf '%s\n' "${_out}" | grep -q 'rollback' \
  || fail "stall must offer rollback: ${_out}"
printf '%s\n' "${_out}" | grep -q 'L-19' \
  || fail "rollback must quote L-19: ${_out}"
printf '%s\n' "${_out}" | grep -q 'L-21' \
  || fail "stall must quote L-21: ${_out}"
printf '%s\n' "${_out}" | grep -q '"unit"' \
  || fail "stall notify missing unit: ${_out}"
printf '%s\n' "${_out}" | grep -q '"journal"' \
  || fail "stall notify missing journal: ${_out}"
printf '%s\n' "${_out}" | grep -q '"clause"' \
  || fail "stall notify missing clause: ${_out}"
_n=$(find "${TMP}/notify" -type f | wc -l | tr -d ' ')
[ "${_n}" -ge 1 ] || fail "stall must write an HI-14 notify file"
python3 - "${TMP}/notify" <<'PY' || fail "notify missing HI-14 fields"
import json, os, sys
root = sys.argv[1]
found = 0
for name in os.listdir(root):
    path = os.path.join(root, name)
    if not os.path.isfile(path):
        continue
    doc = json.load(open(path, encoding="utf-8"))
    journal = doc.get("journal") or doc.get("journal_slice")
    commit = doc.get("commit") or doc.get("state_commit")
    snapper = doc.get("snapper")
    if snapper is None:
        snapper = doc.get("snapper_id")
    unit = doc.get("unit") or doc.get("executable")
    clause = doc.get("clause")
    if unit and journal and commit and snapper not in (None, 0, "0", "") and clause:
        found += 1
if found < 1:
    raise SystemExit("no complete HI-14 payload")
PY

_third=$(goals gap oracle-gap-1) || true
printf '%s\n' "${_third}" | grep -q '"paused": true' \
  || fail "third gap must stay paused: ${_third}"
printf '%s\n' "${_third}" | grep -q '"status": "paused"' \
  || fail "third attempt status paused: ${_third}"
# No new proposal / no oracle rewrite to pass.
printf '%s\n' "${_third}" | grep -q 'true' \
  && printf '%s\n' "${_third}" | grep -q '"oracles": \["true"\]' \
  && fail "third attempt rewrote oracles to true: ${_third}" || true
python3 - "${TMP}/goals.json" <<'PY' || fail "stalled oracles rewritten"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
oracles = (doc.get("proposal") or {}).get("oracles") or []
assert "true" not in oracles, oracles
assert doc.get("status") == "paused"
PY

rm -f "${TMP}/goals.json"
_out=$(goals infra mirror) || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "infra must pause: ${_out}"
printf '%s\n' "${_out}" | grep -q 'rollback' \
  || fail "infra must offer rollback: ${_out}"
printf '%s\n' "${_out}" | grep -q 'L-21' \
  || fail "infra must quote L-21: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "infra must not invent a proposal: ${_out}"
printf '%s\n' "${_out}" | grep -q '"notify": null' \
  || fail "infra without handoff must not write a placeholder notify: ${_out}"
python3 - "${TMP}/goals.json" <<'PY' || fail "infra left proposal on disk"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("proposal") is None, doc
assert doc.get("status") == "paused", doc
PY

rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"work-runtime"}') || true
printf '%s\n' "${_out}" | grep -q 'HI-15' \
  || fail "work-runtime event must quote HI-15: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "work-runtime must not propose synthesis: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "work-runtime synthesis flag: ${_out}"

rm -f "${TMP}/goals.json"
printf '%s\n' '{"status":"idle","declared":["sysupgrade"]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "declared sysupgrade is a bounded window: ${_out}"
printf '%s\n' "${_out}" | grep -q 'gated-p45' \
  || fail "sysupgrade is gated-p45 (P4.5): ${_out}"
printf '%s\n' "${_out}" | grep -q 'no-partial-upgrade.sh' \
  || fail "sysupgrade must name no-partial-upgrade oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q 'boot-seatbelt.sh' \
  || fail "sysupgrade must name boot-seatbelt oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q 'not-while-planning' \
  || fail "sysupgrade must not enact while planning: ${_out}"

rm -f "${TMP}/goals.json"
printf '%s\n' '{"status":"idle","declared":["reconstruct"]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "reconstruct without an event stays idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "reconstruct without an event invents no proposal: ${_out}"

rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"hi-failed"}') || true
printf '%s\n' "${_out}" | grep -q 'HI-10' \
  || fail "hi-failed without clause/oracles is HI-10: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "HI-10 must pause rather than invent oracles: ${_out}"

rm -f "${TMP}/goals.json"
_out=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    python3 "${MAIN}" goals '{"kind":"unit-failed","unit":"x.service"}'
) || true
touch "${TMP}/brake"
_br=$(
  AIOS_GOALS="${TMP}/goals.json" \
    AIOS_NOTIFY="${TMP}/notify" \
    AIOS_MEMORY="${MEM}" \
    AIOS_BRAKE="${TMP}/brake" \
    AIOS_ANSWERS="${TMP}/answers.json" \
    AIOS_ENVELOPE_WORK="${TMP}/envelope-work.md" \
    AIOS_WORK_SRC="${TMP}/work-src" \
    python3 "${MAIN}" goals
) || true
printf '%s\n' "${_br}" | grep -q 'L-12' \
  || fail "brake must freeze goals (L-12): ${_br}"
printf '%s\n' "${_br}" | grep -q '"proposal": null' \
  || fail "brake must not propose: ${_br}"
rm -f "${TMP}/brake"

# Same-gap must not accept rewritten oracles to pass.
rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"packages-drift","oracles":["policy/packages-drift.sh"]}') || true
printf '%s\n' "${_out}" | grep -q 'packages-drift.sh' \
  || fail "packages-drift uses named oracle: ${_out}"
_out=$(goals '{"kind":"gap","gap":"drift-1","oracles":["true"]}') || true
_out=$(goals '{"kind":"gap","gap":"drift-1","oracles":["true"]}') || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "rewritten-true gap still stalls: ${_out}"
python3 - "${TMP}/goals.json" <<'PY' || fail "oracles rewritten to true to pass"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
oracles = (doc.get("proposal") or {}).get("oracles") or []
assert oracles == ["policy/packages-drift.sh"], oracles
assert "true" not in oracles
PY

rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"unit-failed","unit":"x.service","oracles":["/usr/bin/true"]}') || true
printf '%s\n' "${_out}" | grep -q '/usr/bin/true' \
  && fail "/usr/bin/true is not an oracle: ${_out}" || true
printf '%s\n' "${_out}" | grep -q 'policy/hi-14-failure-handoff.sh' \
  || fail "/usr/bin/true must fall through to named oracles: ${_out}"
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "/usr/bin/true must not block named repair: ${_out}"
rm -f "${TMP}/goals.json"
_out=$(goals '{"kind":"unit-failed","unit":"x.service","oracles":["True"]}') || true
printf '%s\n' "${_out}" | grep -q '"True"' \
  && fail "True is not an oracle: ${_out}" || true
printf '%s\n' "${_out}" | grep -q 'policy/hi-14-failure-handoff.sh' \
  || fail "True must fall through to named oracles: ${_out}"

rm -f "${TMP}/goals.json"
printf '%s\n' '{"status":"waiting-accept","proposal":{"oracles":[]}}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q 'HI-10' \
  || fail "resume empty oracles is HI-10: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "resume empty oracles must pause: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "resume empty oracles must clear proposal: ${_out}"

printf '%s\n' '{"status":"waiting-accept","proposal":{"oracles":["true"]}}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q 'HI-10' \
  || fail "resume true-oracle is HI-10: ${_out}"
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "resume true-oracle must pause: ${_out}"

printf '%s\n' '{"status":"verify","proposal":{"oracles":["policy/packages-drift.sh"]}}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  && fail "verify must not idle-and-wipe: ${_out}" || true
printf '%s\n' "${_out}" | grep -q 'policy/packages-drift.sh' \
  || fail "verify must keep oracles: ${_out}"
python3 - "${TMP}/goals.json" <<'PY' || fail "verify wiped oracles on disk"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
oracles = (doc.get("proposal") or {}).get("oracles") or []
assert "policy/packages-drift.sh" in oracles, doc
assert doc.get("status") != "idle", doc
PY

rm -f "${TMP}/goals.json"
printf '%s\n' '{"status":"idle","declared":["sysupgrade"]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "declared sysupgrade must plan: ${_out}"
_out=$(goals '{"kind":"work-runtime"}') || true
printf '%s\n' "${_out}" | grep -q 'HI-15' \
  || fail "work-runtime skip after sysupgrade: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "work-runtime skip must drop the plan: ${_out}"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  && fail "work-runtime skip must not SAME_GAP stall sysupgrade: ${_out}" || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "empty tick after HI-15 skip must re-plan sysupgrade: ${_out}"
printf '%s\n' "${_out}" | grep -q 'gated-p45' \
  || fail "re-planned sysupgrade still gated-p45: ${_out}"

rm -f "${TMP}/goals.json"
_evt='{"kind":"unit-failed","unit":"flap.service","journal":"j","commit":"c","snapper_id":3,"clause":"HI-14"}'
_out=$(goals "${_evt}") || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "first unit-failed plans: ${_out}"
_out=$(goals "${_evt}") || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "second identical unit-failed must pause: ${_out}"
_out=$(goals "${_evt}") || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  || fail "third identical unit-failed stays paused: ${_out}"
printf '%s\n' "${_out}" | grep -q '"status": "paused"' \
  || fail "third identical unit-failed status paused: ${_out}"

rm -f "${TMP}/goals.json" "${TMP}/answers.json"
printf '%s\n' '{"status":"idle","declared":["work-runtime"]}' > "${TMP}/goals.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "declared work-runtime with bit off must idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "declared work-runtime with bit off must not propose: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "declared work-runtime with bit off work_runtime false: ${_out}"

rm -f "${TMP}/goals.json"
printf '%s\n' '{"accepted":true,"work_runtime":true}' > "${TMP}/answers.json"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "answers work_runtime true must plan synthesis: ${_out}"
printf '%s\n' "${_out}" | grep -q 'not-while-planning' \
  || fail "synthesis plan must not enact while planning: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/hi-17-seeds-local.sh' \
  || fail "synthesis plan must name hi-17-seeds-local oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/work-runtime-git.sh' \
  || fail "synthesis plan must name work-runtime-git oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "plan tick must keep work_runtime false: ${_out}"
printf '%s\n' "${_out}" | grep -q '"true"' \
  && fail "synthesis plan invented true oracle: ${_out}" || true
[ ! -e "${TMP}/work-src" ] \
  || fail "planner must not materialise the live work tree"
python3 - "${TMP}/goals.json" <<'PY' || fail "synthesis plan oracles on disk"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
oracles = (doc.get("proposal") or {}).get("oracles") or []
assert "policy/hi-17-seeds-local.sh" in oracles, oracles
assert "policy/work-runtime-git.sh" in oracles, oracles
assert "true" not in oracles, oracles
assert (doc.get("proposal") or {}).get("enact") == "not-while-planning"
assert doc.get("status") == "waiting-accept"
PY

_out=$(goals '{"kind":"work-runtime"}') || true
printf '%s\n' "${_out}" | grep -q '"paused": true' \
  && fail "work-runtime event must not SAME_GAP the empty-tick plan: ${_out}" || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "work-runtime event while waiting-accept must resume: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/work-runtime-git.sh' \
  || fail "resumed synthesis plan must keep oracles: ${_out}"

mkdir -p "${TMP}/work-src"
git -C "${TMP}/work-src" init -b main >/dev/null 2>&1
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "empty tick after live git must idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "empty tick after live git must drop the plan: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "idle after live git work_runtime false: ${_out}"
python3 - "${TMP}/goals.json" <<'PY' || fail "live git left a synthesis plan on disk"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("status") == "idle", doc
assert doc.get("proposal") is None, doc
PY

_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "idle"' \
  || fail "second empty tick with live git must stay idle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "second empty tick with live git must not propose: ${_out}"

rm -rf "${TMP}/work-src"
mkdir -p "${TMP}/work-src/.git"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "empty .git dir must not count as synthesised: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/work-runtime-git.sh' \
  || fail "empty .git dir must still plan synthesis: ${_out}"
rm -rf "${TMP}/work-src"

rm -f "${TMP}/goals.json" "${TMP}/answers.json"
printf '%s\n' 'enabled = yes' > "${TMP}/envelope-work.md"
_out=$(goals) || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "enabled = yes must plan synthesis: ${_out}"
rm -f "${TMP}/envelope-work.md"

rm -f "${TMP}/goals.json"
printf '%s\n' '{"accepted":true,"work_runtime":true}' > "${TMP}/answers.json"
_out=$(goals '{"kind":"work-runtime"}') || true
printf '%s\n' "${_out}" | grep -q '"status": "waiting-accept"' \
  || fail "work-runtime event with bit on must plan: ${_out}"
printf '%s\n' "${_out}" | grep -q 'policy/hi-17-seeds-local.sh' \
  || fail "work-runtime event must name hi-17 oracle: ${_out}"
printf '%s\n' "${_out}" | grep -q '"work_runtime": false' \
  || fail "work-runtime event plan tick work_runtime false: ${_out}"
[ ! -e "${TMP}/work-src" ] \
  || fail "event planner must not materialise the live work tree"

rm -f "${TMP}/goals.json" "${TMP}/answers.json"
_out=$(goals '{"kind":"work-runtime"}') || true
printf '%s\n' "${_out}" | grep -q 'HI-15' \
  || fail "work-runtime event after clearing answers is HI-15 skip: ${_out}"
printf '%s\n' "${_out}" | grep -q '"proposal": null' \
  || fail "cleared-bit work-runtime skip must not propose: ${_out}"

python3 - "${ROOT}/agent/aios_agent" "${MAIN}" <<'PY' || fail "constants / idle serve"
import sys
sys.path.insert(0, sys.argv[1])
from goals import SAME_GAP, MAX_ROUNDS, MAX_EVENTS, KNOWN_STATUS
assert SAME_GAP == 2
assert MAX_ROUNDS >= 2
assert MAX_EVENTS == 1
assert "idle" in KNOWN_STATUS and "paused" in KNOWN_STATUS
src = open(sys.argv[2], encoding="utf-8").read()
assert "def serve" in src and "time.sleep" in src
assert "from goals import" in src
PY

_br=$(git -C "${MEM}" rev-parse --abbrev-ref HEAD)
case "${_br}" in
  agent/*|main) ;;
  *) fail "memory HEAD is ${_br}" ;;
esac
if git -C "${MEM}" log main --oneline | grep -q 'ingest'; then
  fail "goals ingest committed on main (HI-03)"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p4-goals failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p4-goals\n'
exit 0
