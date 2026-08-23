#!/bin/sh
# First envelope compiler. Skip ≠ yes. Canonical HI file + derived clauses.
# Envelope: HI-05, HI-15, L-01, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
COMPILER="${ROOT}/installer/aios_installer/compiler.py"
MAIN="${ROOT}/installer/aios_installer/main.py"
HI="${ROOT}/docs/envelope/hard-invariants.md"
ISO_INST="${ROOT}/payload/profile/airootfs/usr/lib/aios/installer"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${COMPILER}" ] || fail "missing ${COMPILER}"
[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${HI}" ] || fail "missing ${HI}"
[ -f "${ISO_INST}/aios_installer/compiler.py" ] || fail "missing ISO compiler.py"
grep -q 'p5.2' "${COMPILER}" || fail "compiler.py must note compiler is p5.2"
grep -q 'HI-05' "${COMPILER}" || fail "compiler.py must quote HI-05"
grep -q 'HI-15' "${COMPILER}" || fail "compiler.py must quote HI-15"
grep -q 'HI-01' "${HI}" || fail "canonical HI file missing HI-01"
grep -q 'HI-15' "${HI}" || fail "canonical HI file missing HI-15"

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' "${ROOT}/installer" "${ISO_INST}" 2>/dev/null; then
  fail "installer contains -Syu (L-20)"
fi

if grep -E 'makedirs|mkdir' "${COMPILER}" | grep -q 'work-runtime'; then
  fail "compiler must not mkdir work-runtime (HI-15)"
fi

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

python3 -m py_compile \
  "${COMPILER}" \
  "${ROOT}/installer/aios_installer/questions.py" \
  "${MAIN}" \
  || fail "py_compile failed"
# Compile ISO bytes in a temp tree so py_compile cannot leave pyc under airootfs.
_pyct=$(mktemp -d)
cp -a "${ISO_INST}/aios_installer/compiler.py" \
  "${ISO_INST}/aios_installer/questions.py" \
  "${ISO_INST}/aios_installer/main.py" \
  "${ISO_INST}/aios_installer/login.py" \
  "${_pyct}/" \
  || fail "copy ISO python for py_compile"
python3 -m py_compile \
  "${_pyct}/compiler.py" \
  "${_pyct}/questions.py" \
  "${_pyct}/main.py" \
  "${_pyct}/login.py" \
  || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${0}" || fail "sh -n p5-envelope-compiler.sh"

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

if git -C "${ROOT}" ls-files -z -- \
  'payload/profile/airootfs/usr/lib/aios/installer' \
  | tr '\0' '\n' | grep -E '__pycache__|\.pyc$' | grep -q .
then
  fail "ISO installer copy must not track __pycache__ or pyc"
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
WR_BEFORE=0
if [ -e /srv/aios/src/work-runtime ]; then
  WR_BEFORE=1
fi

python3 - "${TMP}" <<'PY' || fail "failed to write answer fixtures"
import json
import os
import sys

dest = sys.argv[1]
base = {
    "purpose": "a lab vm",
    "operator": "operator",
    "vetoes": {
        "never_do": "format the disk",
        "networks": "lan only",
        "remotes": False,
    },
}


def dump(name, extra):
    data = dict(base)
    data.update(extra)
    path = os.path.join(dest, name)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh)


dump("false.json", {"work_runtime": False})
dump("omitted.json", {})
dump("skip.json", {"work_runtime": "skip"})
dump("strtrue.json", {"work_runtime": "true"})
dump("on.json", {"work_runtime": "on"})
dump("please.json", {"work_runtime": "yes please"})
dump("int1.json", {"work_runtime": 1})
dump("yes.json", {"work_runtime": True})
PY

compile() {
  _in=$1
  _out=$2
  AIOS_HI="${HI}" AIOS_ENVELOPE_DRAFT="${_out}.draft" \
    python3 "${COMPILER}" "${_in}" > "${_out}"
}

derived_of() {
  awk '/^derived:/,/^canonical-hard-invariants:/' "$1"
}

expect_off() {
  _label=$1
  _file=$2
  _der=$(derived_of "${_file}")
  printf '%s\n' "${_der}" | grep -Eqi 'work-runtime:[[:space:]]*(no|false|off)' \
    || fail "${_label}: derived work-runtime must be no/false/off"
  printf '%s\n' "${_der}" | grep -Eqi 'work-runtime:[[:space:]]*yes' \
    && fail "${_label}: derived must not say work-runtime yes" || true
  printf '%s\n' "${_der}" | grep -Ei 'work[- ]runtime[[:space:]]+(is[[:space:]]+)?enabled' \
    && fail "${_label}: derived must not say work runtime is enabled" || true
  grep -qF '## HI-01' "${_file}" \
    || fail "${_label}: canonical HI-01 heading missing"
  grep -qF '## HI-15' "${_file}" \
    || fail "${_label}: canonical HI-15 heading missing"
  grep -q 'canonical-hard-invariants:' "${_file}" \
    || fail "${_label}: missing canonical HI inclusion"
  grep -q '"bots"[[:space:]]*:[[:space:]]*true' "${_file}" \
    && fail "${_label}: compiled text must not enable bots" || true
  if grep -q 'bots' "${_file}"; then
    printf '%s\n' "${_der}" | grep -Eq 'bots:[[:space:]]*false' \
      || fail "${_label}: bots must be false if mentioned"
  fi
  cmp -s "${_file}" "${_file}.draft" \
    || fail "${_label}: AIOS_ENVELOPE_DRAFT must match compiled stdout"
}

expect_purpose_vetoes() {
  _label=$1
  _file=$2
  _der=$(derived_of "${_file}")
  printf '%s\n' "${_der}" | grep -qF 'purpose: a lab vm' \
    || fail "${_label}: purpose missing as derived clause"
  printf '%s\n' "${_der}" | grep -qF 'vetoes.never-do: format the disk' \
    || fail "${_label}: never-do veto missing as derived clause"
  printf '%s\n' "${_der}" | grep -qF 'vetoes.networks: lan only' \
    || fail "${_label}: networks veto missing as derived clause"
  printf '%s\n' "${_der}" | grep -Eq 'vetoes.remotes:[[:space:]]*false' \
    || fail "${_label}: remotes veto missing as derived clause"
}

compile "${TMP}/false.json" "${TMP}/false.out" \
  || fail "compile work_runtime false failed"
expect_off "false" "${TMP}/false.out"
expect_purpose_vetoes "false" "${TMP}/false.out"

compile "${TMP}/omitted.json" "${TMP}/omitted.out" \
  || fail "compile omitted work_runtime failed"
expect_off "omitted" "${TMP}/omitted.out"
expect_purpose_vetoes "omitted" "${TMP}/omitted.out"

compile "${TMP}/skip.json" "${TMP}/skip.out" \
  || fail "compile skip work_runtime failed"
expect_off "skip" "${TMP}/skip.out"

compile "${TMP}/strtrue.json" "${TMP}/strtrue.out" \
  || fail "compile string true failed"
expect_off "string-true" "${TMP}/strtrue.out"

compile "${TMP}/on.json" "${TMP}/on.out" \
  || fail "compile on failed"
expect_off "on" "${TMP}/on.out"

compile "${TMP}/please.json" "${TMP}/please.out" \
  || fail "compile yes please failed"
expect_off "yes-please" "${TMP}/please.out"

compile "${TMP}/int1.json" "${TMP}/int1.out" \
  || fail "compile integer 1 failed"
expect_off "int1" "${TMP}/int1.out"

compile "${TMP}/yes.json" "${TMP}/yes.out" \
  || fail "compile explicit true failed"
_yesder=$(derived_of "${TMP}/yes.out")
printf '%s\n' "${_yesder}" | grep -Eqi 'work-runtime:[[:space:]]*yes' \
  || fail "explicit yes: derived must say work-runtime yes"
printf '%s\n' "${_yesder}" | grep -Eqi 'work-runtime:[[:space:]]*no' \
  && fail "explicit yes: derived must not say work-runtime no" || true
grep -qF '## HI-01' "${TMP}/yes.out" || fail "explicit yes: missing canonical HI-01"
grep -qF '## HI-15' "${TMP}/yes.out" || fail "explicit yes: missing canonical HI-15"
grep -qF 'Do not synthesise /srv/aios/src/work-runtime' "${TMP}/yes.out" \
  || fail "explicit yes must still refuse synthesis here (HI-15)"
expect_purpose_vetoes "yes" "${TMP}/yes.out"

printf '%s\n' '{' > "${TMP}/bad.json"
_bad_rc=0
AIOS_HI="${HI}" python3 "${COMPILER}" "${TMP}/bad.json" \
  > "${TMP}/bad.out" 2> "${TMP}/bad.err" || _bad_rc=$?
[ "${_bad_rc}" -eq 1 ] \
  || fail "malformed JSON must exit 1, got ${_bad_rc}"
if grep -q Traceback "${TMP}/bad.err" "${TMP}/bad.out" 2>/dev/null; then
  fail "malformed JSON must not print Traceback"
fi
grep -q '^error:' "${TMP}/bad.err" \
  || fail "malformed JSON must print error on stderr"

# Default-path compile (no AIOS_HI): still finds a canonical file.
AIOS_ENVELOPE_DRAFT="${TMP}/default.out.draft" \
  python3 "${COMPILER}" "${TMP}/omitted.json" > "${TMP}/default.out" \
  || fail "compile without AIOS_HI failed"
expect_off "default-hi-path" "${TMP}/default.out"
grep -q 'hard-invariants.md' "${TMP}/default.out" \
  || fail "default compile must record the HI path"

# ISO copy compiles the same envelope when HI path is pinned.
AIOS_HI="${HI}" python3 "${ISO_INST}/aios_installer/compiler.py" \
  "${TMP}/false.json" > "${TMP}/iso.out" \
  || fail "ISO compiler failed"
cmp -s "${TMP}/false.out" "${TMP}/iso.out" \
  || fail "ISO compiler output differs from source compiler"

# Envelope view shows the compiled document.
LIVE_BIP="/srv/aios/state/bootstrap-in-progress"
_live_existed=0
[ -e "${LIVE_BIP}" ] && _live_existed=1
mkdir -p "${TMP}/tui-boot"
_tui=$(
  printf '%s\n' \
    'answer purpose a lab vm' \
    'skip work-runtime' \
    'answer never-do format the disk' \
    'answer networks lan only' \
    'view envelope' \
    'quit' | AIOS_BOOTSTRAP="${TMP}/tui-boot" python3 -u "${MAIN}"
) || true
printf '%s\n' "${_tui}" | grep -q 'view: envelope' \
  || fail "envelope view missing: ${_tui}"
printf '%s\n' "${_tui}" | grep -q 'compiler: p5.2' \
  || fail "envelope view missing compiler marker: ${_tui}"
printf '%s\n' "${_tui}" | grep -qF '## HI-01' \
  || fail "envelope view missing canonical HI-01: ${_tui}"
printf '%s\n' "${_tui}" | grep -qF '## HI-15' \
  || fail "envelope view missing canonical HI-15: ${_tui}"
printf '%s\n' "${_tui}" | grep -qF 'purpose: a lab vm' \
  || fail "envelope view missing purpose: ${_tui}"
printf '%s\n' "${_tui}" | grep -qF 'vetoes.never-do: format the disk' \
  || fail "envelope view missing vetoes: ${_tui}"
printf '%s\n' "${_tui}" | grep -Eqi 'work-runtime:[[:space:]]*(no|false|off)' \
  || fail "envelope view skip must leave work-runtime off: ${_tui}"
printf '%s\n' "${_tui}" | grep -q 'envelope-decision: accepted' \
  && fail "compile must not accept the envelope: ${_tui}" || true

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src/work-runtime ]; then
  fail "compiler created /srv/aios/src/work-runtime (HI-15)"
fi
_found=$(find "${TMP}" -name work-runtime -print 2>/dev/null || true)
[ -z "${_found}" ] || fail "compiler created work-runtime under TMP: ${_found}"

if [ "${_live_existed}" -eq 0 ] && [ -e "${LIVE_BIP}" ]; then
  fail "oracle created ${LIVE_BIP} (HI-09)"
fi

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
  printf 'error: p5-envelope-compiler failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p5-envelope-compiler\n'
exit 0
