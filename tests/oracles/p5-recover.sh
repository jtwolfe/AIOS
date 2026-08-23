#!/bin/sh
# P5.3: bootstrap-in-progress recovery. Kill/resume. Skip ≠ yes. Fail-closed.
# Envelope: P5.3, L-18, L-19, L-20, HI-09, HI-15.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/installer/aios_installer/main.py"
RECOVER="${ROOT}/installer/aios_installer/recover.py"
HI="${ROOT}/docs/envelope/hard-invariants.md"
ISO_INST="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer"
FIRSTBOOT="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/firstboot"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${RECOVER}" ] || fail "missing ${RECOVER}"
[ -f "${ISO_INST}/aios_installer/recover.py" ] || fail "missing ISO recover.py"

grep -q 'L-18' "${RECOVER}" || fail "recover.py must quote L-18"
grep -q 'HI-09' "${RECOVER}" || fail "recover.py must quote HI-09"
grep -q 'L-19' "${RECOVER}" || fail "recover.py must quote L-19"
grep -q 'AIOS_BOOTSTRAP' "${RECOVER}" || fail "recover.py must honor AIOS_BOOTSTRAP"
grep -q 'os.replace' "${RECOVER}" || fail "recover.py must atomic-write with os.replace"
grep -q 'HI-09' "${MAIN}" || fail "main.py must quote HI-09 on recovery/reject"
grep -q 'L-19' "${MAIN}" || fail "main.py must quote L-19 on reject"
grep -q 'writes_frozen' "${MAIN}" || fail "persist must gate on writes_frozen (L-12)"
grep -q 'persist failed' "${MAIN}" || fail "persist failure must set note_text"
[ -f "${FIRSTBOOT}" ] || fail "missing firstboot"
grep -q '/srv/aios/state/snapper_pre' "${FIRSTBOOT}" \
  || fail "firstboot must write /srv/aios/state/snapper_pre (HI-09)"

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' "${ROOT}/installer" "${ISO_INST}" 2>/dev/null; then
  fail "installer contains -Syu (L-20)"
fi

if grep -R -q -- 'envelope-accepted' "${ROOT}/installer" "${ISO_INST}" 2>/dev/null; then
  fail "installer must not write envelope-accepted"
fi

if grep -R -q -- 'undochange' "${ROOT}/installer" "${ISO_INST}" 2>/dev/null; then
  fail "installer must not call snapper undochange (L-19)"
fi

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

python3 -m py_compile \
  "${MAIN}" \
  "${ROOT}/installer/aios_installer/questions.py" \
  "${ROOT}/installer/aios_installer/compiler.py" \
  "${RECOVER}" \
  "${ROOT}/installer/aios_installer/login.py" \
  || fail "py_compile failed"

_pyct=$(mktemp -d)
cp -a "${ISO_INST}/aios_installer/compiler.py" \
  "${ISO_INST}/aios_installer/questions.py" \
  "${ISO_INST}/aios_installer/main.py" \
  "${ISO_INST}/aios_installer/recover.py" \
  "${ISO_INST}/aios_installer/login.py" \
  "${_pyct}/" \
  || fail "copy ISO python for py_compile"
python3 -m py_compile \
  "${_pyct}/compiler.py" \
  "${_pyct}/questions.py" \
  "${_pyct}/main.py" \
  "${_pyct}/recover.py" \
  "${_pyct}/login.py" \
  || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${0}" || fail "sh -n p5-recover.sh"

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
BOOT="${TMP}/bootstrap"
SNAP=7
mkdir -p "${BOOT}"

drive() {
  AIOS_BOOTSTRAP="${BOOT}" \
    AIOS_SNAPPER_PRE="${SNAP}" \
    AIOS_HI="${HI}" \
    AIOS_BRAKE="${TMP}/brake" \
    python3 -u "${MAIN}"
}

_out1=$(
  printf '%s\n' \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    | drive
) || true

if printf '%s\n' "${_out1}" | grep -q Traceback; then
  fail "first run traceback: ${_out1}"
fi
printf '%s\n' "${_out1}" | grep -q 'purpose: a lab vm' \
  || fail "first run missing purpose: ${_out1}"
printf '%s\n' "${_out1}" | grep -q 'skip: not-yes' \
  || fail "skip work-runtime must be not-yes: ${_out1}"
printf '%s\n' "${_out1}" | grep -q 'work-runtime: true' \
  && fail "skip work-runtime must not set the bit true: ${_out1}" || true
printf '%s\n' "${_out1}" | grep -q 'work-runtime: false' \
  || fail "skip work-runtime must leave the bit false: ${_out1}"

for _f in answers.json envelope.draft.md snapper_pre step; do
  [ -f "${BOOT}/${_f}" ] || fail "missing ${_f} under bootstrap-in-progress"
done
_tmp_left=$(find "${BOOT}" -name '*.tmp' -print)
[ -z "${_tmp_left}" ] || fail "tmp leftover after persist: ${_tmp_left}"

grep -qx "${SNAP}" "${BOOT}/snapper_pre" \
  || fail "snapper_pre file must record AIOS_SNAPPER_PRE: $(cat "${BOOT}/snapper_pre")"
grep -qx 'questions' "${BOOT}/step" \
  || fail "step file must record questions: $(cat "${BOOT}/step")"
grep -q 'purpose: a lab vm' "${BOOT}/envelope.draft.md" \
  || fail "envelope.draft.md missing purpose"
grep -q 'compiler: p5.2' "${BOOT}/envelope.draft.md" \
  || fail "envelope.draft.md missing compiler marker"

python3 - "${BOOT}/answers.json" <<'PY' || fail "answers.json schema"
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
if not isinstance(data, dict):
    raise SystemExit("answers.json is not an object")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots key must be absent or false")
if data.get("bots") is True:
    raise SystemExit("bots must not be true")
if data.get("work_runtime") is True:
    raise SystemExit("skip must not persist work_runtime true")
if data.get("work_runtime") is not False:
    raise SystemExit("work_runtime must be JSON false, got %r" % data.get("work_runtime"))
if data.get("purpose") != "a lab vm":
    raise SystemExit("purpose not persisted: %r" % data.get("purpose"))
if "operator" not in data:
    raise SystemExit("TUI key operator missing")
if data.get("accepted") is True:
    raise SystemExit("accepted must not be true before envelope accept")
PY

# Kill is EOF after persist. Restart with the same snapshot.
_out2=$(
  printf '%s\n' \
    'view recovery' \
    'quit' \
    | drive
) || true

if printf '%s\n' "${_out2}" | grep -q Traceback; then
  fail "resume traceback: ${_out2}"
fi
printf '%s\n' "${_out2}" | grep -q 'purpose: a lab vm' \
  || fail "purpose must reappear on resume: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'work-runtime: true' \
  && fail "resume must not turn skip into yes: ${_out2}" || true
printf '%s\n' "${_out2}" | grep -q 'work-runtime: false' \
  || fail "work-runtime must stay false on resume: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'view: recovery' \
  || fail "recovery view not reachable: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'last-step:' \
  || fail "recovery missing last-step: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'snapper-id: 7' \
  || fail "recovery missing snapper id: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'resume:' \
  || fail "recovery missing resume action: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'L-19' \
  || fail "recovery must offer L-19 rollback: ${_out2}"
printf '%s\n' "${_out2}" | grep -q 'HI-09' \
  || fail "recovery must quote HI-09: ${_out2}"
printf '%s\n' "${_out2}" | grep -q '"bots"' \
  && fail "TUI must not print a bots key: ${_out2}" || true

# Reject records the decision and keeps the snapshot; does not enact rollback.
BOOT_REJ="${TMP}/reject"
ROOT_REJ="${TMP}/root-reject"
mkdir -p "${BOOT_REJ}" "${ROOT_REJ}"
_rej=$(
  AIOS_BOOTSTRAP="${BOOT_REJ}" \
    AIOS_ROOT="${ROOT_REJ}" \
    AIOS_SNAPPER_PRE="${SNAP}" \
    AIOS_HI="${HI}" \
    python3 -u "${MAIN}" <<'EOF'
answer operator alice
view envelope
reject
quit
EOF
) || true
[ ! -e "${ROOT_REJ}/etc/passwd" ] \
  || fail "reject must not create operator login (L-13)"
printf '%s\n' "${_rej}" | grep -q 'envelope-decision: rejected' \
  || fail "reject missing: ${_rej}"
printf '%s\n' "${_rej}" | grep -q 'L-19' \
  || fail "reject must quote L-19: ${_rej}"
[ -f "${BOOT_REJ}/answers.json" ] || fail "reject must keep answers.json"
python3 - "${BOOT_REJ}/answers.json" <<'PY' || fail "reject answers.json"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("accepted") is True:
    raise SystemExit("reject must not persist accepted true")
if data.get("decision") != "rejected":
    raise SystemExit("reject must persist decision rejected")
if "bots" in data and data.get("bots") is not False:
    raise SystemExit("bots key must be absent or false")
PY

# Malformed snapshot: fail closed to questions; do not traceback-exit.
printf '%s\n' '{' > "${BOOT}/answers.json"
_bad=$(
  printf '%s\n' 'view recovery' 'quit' | drive
) || _bad_rc=$?
_bad_rc=${_bad_rc:-0}
[ "${_bad_rc}" -eq 0 ] || fail "malformed snapshot must not exit nonzero, got ${_bad_rc}"
if printf '%s\n' "${_bad}" | grep -q Traceback; then
  fail "malformed snapshot traceback-exited: ${_bad}"
fi
printf '%s\n' "${_bad}" | grep -q 'view: questions' \
  || fail "malformed snapshot must fail closed to questions: ${_bad}"
printf '%s\n' "${_bad}" | grep -q 'purpose: a lab vm' \
  && fail "malformed snapshot must not keep stale purpose: ${_bad}" || true
printf '%s\n' "${_bad}" | grep -q 'malformed' \
  || fail "malformed snapshot must note fail-closed: ${_bad}"

printf '%s\n' '[]' > "${BOOT}/answers.json"
_bad2=$(
  printf '%s\n' 'quit' | drive
) || true
if printf '%s\n' "${_bad2}" | grep -q Traceback; then
  fail "array snapshot traceback-exited: ${_bad2}"
fi
printf '%s\n' "${_bad2}" | grep -q 'view: questions' \
  || fail "array snapshot must fail closed to questions: ${_bad2}"

# Typed-field mismatch: work_runtime: 1 / accepted: 1 fail closed (is True, not ==).
BOOT_TYPED="${TMP}/typed"
mkdir -p "${BOOT_TYPED}"
python3 - "${BOOT_TYPED}/answers.json" <<'PY' || fail "failed to write typed snapshot"
import json
import sys

doc = {
    "purpose": "stale",
    "work_runtime": 1,
    "operator": None,
    "operator_login": None,
    "vetoes": {"never_do": None, "networks": None, "remotes": False},
    "accepted": 1,
    "decision": None,
    "step": "accept",
    "snapper_pre": 7,
    "qindex": 2,
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(doc, fh)
PY
_load_typed=$(
  AIOS_BOOTSTRAP="${BOOT_TYPED}" python3 - "${ROOT}/installer/aios_installer" <<'PY'
import os
import sys

sys.path.insert(0, sys.argv[1])
import recover

loaded = recover.load()
if loaded is not None:
    raise SystemExit("typed snapshot must not load: %r" % (loaded,))
PY
) || fail "recover.load of work_runtime:1 / accepted:1 must return None: ${_load_typed}"
_typed=$(
  AIOS_BOOTSTRAP="${BOOT_TYPED}" \
    AIOS_SNAPPER_PRE="${SNAP}" \
    AIOS_HI="${HI}" \
    python3 -u "${MAIN}" <<'EOF'
view recovery
quit
EOF
) || true
if printf '%s\n' "${_typed}" | grep -q Traceback; then
  fail "typed snapshot traceback-exited: ${_typed}"
fi
printf '%s\n' "${_typed}" | grep -q 'view: questions' \
  || fail "typed snapshot must fail closed to questions: ${_typed}"
printf '%s\n' "${_typed}" | grep -q 'malformed' \
  || fail "typed snapshot must note fail-closed: ${_typed}"
printf '%s\n' "${_typed}" | grep -q 'purpose: stale' \
  && fail "typed snapshot must not keep stale purpose: ${_typed}" || true
printf '%s\n' "${_typed}" | grep -q 'work-runtime: true' \
  && fail "work_runtime: 1 must not load as yes: ${_typed}" || true
printf '%s\n' "${_typed}" | grep -q 'work-runtime: false' \
  || fail "work_runtime: 1 must fail closed to false: ${_typed}"
printf '%s\n' "${_typed}" | grep -q 'envelope-decision: accepted' \
  && fail "accepted: 1 must not load as accepted: ${_typed}" || true
python3 - "${BOOT_TYPED}/answers.json" <<'PY' || fail "typed snapshot persist after fail-closed"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime is True after fail-closed")
if data.get("work_runtime") is not False:
    raise SystemExit("work_runtime must be JSON false, got %r" % data.get("work_runtime"))
if data.get("accepted") is True:
    raise SystemExit("accepted is True after fail-closed")
if data.get("accepted") is not False:
    raise SystemExit("accepted must be JSON false, got %r" % data.get("accepted"))
if data.get("purpose") == "stale":
    raise SystemExit("stale purpose survived fail-closed")
PY

# Persist failure must surface (HI-09).
printf x > "${TMP}/notdir"
_pf=$(
  AIOS_BOOTSTRAP="${TMP}/notdir/boot" \
    AIOS_SNAPPER_PRE="${SNAP}" \
    AIOS_HI="${HI}" \
    python3 -u "${MAIN}" <<'EOF'
answer purpose a lab vm
quit
EOF
) || true
printf '%s\n' "${_pf}" | grep -q 'persist failed' \
  || fail "persist OSError must set note: ${_pf}"
printf '%s\n' "${_pf}" | grep -q 'HI-09' \
  || fail "persist failure must quote HI-09: ${_pf}"
if printf '%s\n' "${_pf}" | grep -q Traceback; then
  fail "persist failure traceback-exited: ${_pf}"
fi

# Brake freezes snapshot writes (L-12).
BOOT_BR="${TMP}/brake-persist"
mkdir -p "${BOOT_BR}"
_brp=$(
  AIOS_BOOTSTRAP="${BOOT_BR}" \
    AIOS_SNAPPER_PRE="${SNAP}" \
    AIOS_HI="${HI}" \
    AIOS_BRAKE="${TMP}/brakeflag" \
    python3 -u "${MAIN}" <<'EOF'
answer purpose a lab vm
brake
answer purpose mutated
quit
EOF
) || true
printf '%s\n' "${_brp}" | grep -q 'writes: frozen' \
  || fail "brake must freeze writes: ${_brp}"
printf '%s\n' "${_brp}" | grep -q 'refused: writes frozen' \
  || fail "answer after brake must refuse: ${_brp}"
python3 - "${BOOT_BR}/answers.json" <<'PY' || fail "brake must not persist mutated purpose"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("purpose") != "a lab vm":
    raise SystemExit("purpose mutated while frozen: %r" % data.get("purpose"))
if data.get("work_runtime") is True:
    raise SystemExit("work_runtime became true while frozen")
PY

# ISO copy resumes the same snapshot bytes.
BOOT_ISO="${TMP}/iso"
mkdir -p "${BOOT_ISO}"
AIOS_BOOTSTRAP="${BOOT_ISO}" AIOS_SNAPPER_PRE="${SNAP}" AIOS_HI="${HI}" \
  python3 -u "${ISO_INST}/aios_installer/main.py" <<'EOF' >/dev/null
answer purpose a lab vm
skip work-runtime
EOF
_iso=$(
  AIOS_BOOTSTRAP="${BOOT_ISO}" AIOS_SNAPPER_PRE="${SNAP}" AIOS_HI="${HI}" \
    python3 -u "${ISO_INST}/aios_installer/main.py" <<'EOF'
view recovery
quit
EOF
) || true
printf '%s\n' "${_iso}" | grep -q 'purpose: a lab vm' \
  || fail "ISO resume missing purpose: ${_iso}"
printf '%s\n' "${_iso}" | grep -q 'work-runtime: false' \
  || fail "ISO resume work-runtime not false: ${_iso}"

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

AIROOTFS="${ROOT}/payload/profile/airootfs"
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
  printf 'error: p5-recover failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p5-recover\n'
exit 0
