#!/bin/sh
# P7.5: L-18 OS catalog bodies. Keyboard-complete. Notify stays stubbed.
# Envelope: P7.5, L-18, L-12, HI-15, L-09, L-20.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
MAIN="${ROOT}/operator-client/tty/aios.py"
ISO_OC="${ROOT}/payload/profile/airootfs/usr/lib/aios/operator-client"
ISO_BIN="${ROOT}/payload/profile/airootfs/usr/lib/aios/bin/aios"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
HI="${ROOT}/docs/envelope/hard-invariants.md"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

[ -f "${MAIN}" ] || fail "missing ${MAIN}"
[ -f "${ISO_OC}/tty/aios.py" ] || fail "missing ISO operator-client aios.py"
[ -f "${HI}" ] || fail "missing ${HI}"

grep -q 'P7.5' "${MAIN}" || fail "aios.py must quote P7.5"
grep -q 'L-18' "${MAIN}" || fail "aios.py must quote L-18"
grep -q 'L-17' "${MAIN}" || fail "aios.py must quote L-17"

for _id in chrome conversation envelope intents notify snapper packages login
do
  grep -q "${_id}" "${MAIN}" || fail "aios.py missing view id ${_id} (L-18)"
done

python3 - "${MAIN}" <<'PY' || fail "VIEWS catalog drifted (L-18)"
import ast
import sys

src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
views = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for t in node.targets:
            if getattr(t, "id", None) == "VIEWS":
                views = ast.literal_eval(node.value)
if views is None:
    raise SystemExit("VIEWS missing")
need = (
    "chrome",
    "conversation",
    "envelope",
    "intents",
    "notify",
    "snapper",
    "packages",
    "login",
)
if tuple(views) != need:
    raise SystemExit("VIEWS %s" % (views,))
if "brake" in views:
    raise SystemExit("brake is a view id")
PY

_pyct=$(mktemp -d)
cp -a "${MAIN}" "${_pyct}/aios.py" || fail "copy aios.py for py_compile"
python3 -m py_compile "${_pyct}/aios.py" || fail "py_compile aios.py failed"
cp -a "${ISO_OC}/tty/aios.py" "${_pyct}/iso-aios.py" \
  || fail "copy ISO aios.py for py_compile"
python3 -m py_compile "${_pyct}/iso-aios.py" || fail "ISO py_compile failed"
rm -rf "${_pyct}"

sh -n "${ISO_BIN}" || fail "sh -n bin/aios"
sh -n "${0}" || fail "sh -n p7-os-views.sh"

while IFS= read -r rel; do
  [ -n "${rel}" ] || continue
  cmp -s "${ROOT}/operator-client/${rel}" "${ISO_OC}/${rel}" \
    || fail "ISO operator-client ${rel} bytes differ"
done <<EOF
$(cd "${ROOT}/operator-client" && find . -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort)
EOF

_prov=$(grep -RIn -- 'provider' "${ROOT}/installer" 2>/dev/null | head -n 1 || true)
[ -z "${_prov}" ] || fail "installer names provider (HI-02): ${_prov}"

if grep -R -q -- '-Syu' \
  "${ROOT}/operator-client" \
  "${ISO_BIN}" \
  "${ISO_OC}" \
  "${ROOT}/installer" 2>/dev/null
then
  fail "operator-client/installer contains -Syu (L-20)"
fi

if grep -REin -- 'hyprland|gnome|kwin|keybind|key.?chord|bindsym' \
  "${ROOT}/operator-client" "${ISO_BIN}" "${ISO_OC}" 2>/dev/null
then
  fail "key chord / DE bind in operator-client or bin/aios"
fi

if grep -En -- '[[:space:]]sudo[[:space:]]|sudo$|NOPASSWD' \
  "${ROOT}/operator-client/tty/aios.py" 2>/dev/null
then
  fail "operator-client must not sudo (L-17)"
fi

grep -E '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin operator-client/tty/aios.py"
grep -E '^[0-9a-f]{64}  payload/profile/airootfs/usr/lib/aios/operator-client/tty/aios.py$' \
  "${HASHES}" >/dev/null \
  || fail "payload/hashes.txt must pin ISO operator-client aios.py"
grep -Eq '^[0-9a-f]{64}  operator-client/tty/aios.py$' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin operator-client/tty/aios.py"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
LIVE_BRAKE="/srv/aios/state/brake.d/stamp"
LIVE_TOKEN="/srv/aios/state/provider/os.token"
_live_brake=0
_live_token=0
[ -e "${LIVE_BRAKE}" ] && _live_brake=1
[ -e "${LIVE_TOKEN}" ] && _live_token=1

mkdir -p "${TMP}/root/etc/aios" \
  "${TMP}/boot" \
  "${TMP}/intents" \
  "${TMP}/pin" \
  "${TMP}/live"
printf '%s\n' '{"purpose":"a lab vm","work_runtime":false,"operator":"alice","vetoes":{"never_do":"format the disk","networks":"lan only","remotes":false}}' \
  > "${TMP}/boot/answers.json"
printf '%s\n' 'linux' 'linux-lts' 'git' > "${TMP}/pin/packages.txt"
printf '%s\n' 'linux' 'linux-lts' 'git' > "${TMP}/live/packages.txt"
printf '%s\n' '1 /boot/aios-gen/1' '2 /boot/aios-gen/2' > "${TMP}/snapper.list"
printf '%s\n' 'explain failed unit' > "${TMP}/intents/unit-fail"

drive() {
  printf '%s\n' "$@" | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_BOOTSTRAP="${TMP}/boot" \
    AIOS_HI="${HI}" \
    AIOS_PACKAGES="${TMP}/pin/packages.txt" \
    AIOS_LIVE_PACKAGES="${TMP}/live/packages.txt" \
    AIOS_SNAPPER_LIST="${TMP}/snapper.list" \
    AIOS_INTENTS="${TMP}/intents-empty" \
    python3 -u "${MAIN}"
}

_ch=$(drive 'view chrome' 'quit') || true
printf '%s\n' "${_ch}" | grep -q '^mode: os$' \
  || fail "chrome must be mode os: ${_ch}"
printf '%s\n' "${_ch}" | grep -q '^view: chrome$' \
  || fail "view chrome missing: ${_ch}"
printf '%s\n' "${_ch}" | grep -q '^actions: view brake send mode$' \
  || fail "chrome actions missing: ${_ch}"

_env=$(drive 'view envelope' 'inspect' 'quit') || true
printf '%s\n' "${_env}" | grep -q '^view: envelope$' \
  || fail "envelope view missing: ${_env}"
printf '%s\n' "${_env}" | grep -q 'not this PR' \
  && fail "envelope must not be a stub: ${_env}" || true
printf '%s\n' "${_env}" | grep -q 'compiler: p5.2' \
  || fail "envelope inspect missing compiler: ${_env}"
printf '%s\n' "${_env}" | grep -qF '## HI-01' \
  || fail "envelope inspect missing HI-01: ${_env}"
printf '%s\n' "${_env}" | grep -qF 'purpose: a lab vm' \
  || fail "envelope inspect missing purpose: ${_env}"
printf '%s\n' "${_env}" | grep -q 'actions: inspect view brake' \
  || fail "envelope inspect action missing: ${_env}"

_e=$(drive 'e' 'quit') || true
printf '%s\n' "${_e}" | grep -q '^view: envelope$' \
  || fail "letter e must open envelope: ${_e}"
_ve=$(drive 'v e' 'quit') || true
printf '%s\n' "${_ve}" | grep -q '^view: envelope$' \
  || fail "v e must open envelope: ${_ve}"

_int=$(drive 'view intents' 'quit') || true
printf '%s\n' "${_int}" | grep -q '^view: intents$' \
  || fail "intents view missing: ${_int}"
printf '%s\n' "${_int}" | grep -q 'not this PR' \
  && fail "intents must not be a stub: ${_int}" || true
printf '%s\n' "${_int}" | grep -q '(empty)' \
  || fail "empty intents list missing: ${_int}"

_open=$(
  printf '%s\n' 'view intents' 'open unit-fail' 'quit' | \
    AIOS_BRAKE="${TMP}/unused-brake" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_INTENTS="${TMP}/intents" \
    python3 -u "${MAIN}"
) || true
printf '%s\n' "${_open}" | grep -q '^view: conversation$' \
  || fail "open intent must switch to conversation: ${_open}"
printf '%s\n' "${_open}" | grep -q 'operator: explain failed unit' \
  || fail "open intent must send the body: ${_open}"

_pkg=$(drive 'view packages' 'inspect' 'quit') || true
printf '%s\n' "${_pkg}" | grep -q '^view: packages$' \
  || fail "packages view missing: ${_pkg}"
printf '%s\n' "${_pkg}" | grep -q 'not this PR' \
  && fail "packages must not be a stub: ${_pkg}" || true
printf '%s\n' "${_pkg}" | grep -q 'pin: linux' \
  || fail "packages pin missing linux: ${_pkg}"
printf '%s\n' "${_pkg}" | grep -q 'live: match' \
  || fail "packages live match missing: ${_pkg}"
_vp=$(drive 'v p' 'quit') || true
printf '%s\n' "${_vp}" | grep -q '^view: packages$' \
  || fail "v p must open packages: ${_vp}"

_sn=$(drive 'view snapper' 'inspect' 'quit') || true
printf '%s\n' "${_sn}" | grep -q '^view: snapper$' \
  || fail "snapper view missing: ${_sn}"
printf '%s\n' "${_sn}" | grep -q 'not this PR' \
  && fail "snapper inspect must not be a stub: ${_sn}" || true
printf '%s\n' "${_sn}" | grep -q 'aios-gen/1' \
  || fail "snapper list missing generation: ${_sn}"
_rb=$(drive 'view snapper' 'rollback' 'quit') || true
printf '%s\n' "${_rb}" | grep -q 'not this PR' \
  && fail "snapper rollback must not stay stubbed: ${_rb}" || true
printf '%s\n' "${_rb}" | grep -q 'L-19' \
  || fail "snapper rollback must quote L-19: ${_rb}"
if printf '%s\n' "${_rb}" | grep -Eq 'subvolume snapshot|btrfs '
then
  fail "snapper rollback enacted L-19 restore: ${_rb}"
fi
printf '%s\n' "${_rb}" | grep -Eq 'select N|requested|rendezvous missing|refused' \
  || fail "snapper rollback must be a keyboard path: ${_rb}"

_conv=$(drive 'view conversation' 'send is the envelope a view?' 'quit') || true
printf '%s\n' "${_conv}" | grep -q '^view: conversation$' \
  || fail "conversation view missing: ${_conv}"
printf '%s\n' "${_conv}" | grep -q 'turn-ended: question' \
  || fail "questions must end the turn: ${_conv}"
printf '%s\n' "${_conv}" | grep -q 'operator: is the envelope a view?' \
  || fail "conversation send missing: ${_conv}"
_cs=$(drive 'c' 'send hello catalog' 'quit') || true
printf '%s\n' "${_cs}" | grep -q 'operator: hello catalog' \
  || fail "letter c send missing: ${_cs}"
printf '%s\n' "${_cs}" | grep -q '^note: sent$' \
  || fail "conversation send must be real: ${_cs}"

_lg=$(drive 'view login' 'quit') || true
printf '%s\n' "${_lg}" | grep -q '^view: login$' \
  || fail "login view missing: ${_lg}"
printf '%s\n' "${_lg}" | grep -q 'not this PR' \
  && fail "login must not be a stub: ${_lg}" || true
printf '%s\n' "${_lg}" | grep -q 'actions: start cancel poll view brake' \
  || fail "login actions missing: ${_lg}"
printf '%s\n' "${_lg}" | grep -q 'L-17' \
  || fail "login view must quote L-17: ${_lg}"
_vl=$(drive 'v l' 'quit') || true
printf '%s\n' "${_vl}" | grep -q '^view: login$' \
  || fail "v l must open login: ${_vl}"

_stub=$(drive 'view notify' 'quit') || true
printf '%s\n' "${_stub}" | grep -q 'not this PR' \
  || fail "notify must stay stubbed: ${_stub}"
printf '%s\n' "${_stub}" | grep -q '^view: notify$' \
  || fail "notify view id must be reachable: ${_stub}"

_keys=$(drive 'h' 'c' 'e' 'i' 'n' 's' 'p' 'l' 'quit') || true
printf '%s\n' "${_keys}" | grep -q '^view: chrome$' \
  || fail "letter h missing chrome: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: conversation$' \
  || fail "letter c missing conversation: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: envelope$' \
  || fail "letter e missing envelope: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: intents$' \
  || fail "letter i missing intents: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: notify$' \
  || fail "letter n missing notify: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: snapper$' \
  || fail "letter s missing snapper: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: packages$' \
  || fail "letter p missing packages: ${_keys}"
printf '%s\n' "${_keys}" | grep -q '^view: login$' \
  || fail "letter l missing login: ${_keys}"

if [ "${_live_brake}" -eq 0 ] && [ -e "${LIVE_BRAKE}" ]; then
  rm -f "${LIVE_BRAKE}"
  fail "oracle created ${LIVE_BRAKE}"
fi
if [ "${_live_token}" -eq 0 ] && [ -e "${LIVE_TOKEN}" ]; then
  rm -f "${LIVE_TOKEN}"
  fail "oracle created ${LIVE_TOKEN}"
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
    operator-client/*)
      f="${AIROOTFS}/usr/lib/aios/${path}"
      [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
      printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
        || fail "ISO hash mismatch: ${path}"
      ;;
  esac
done < "${ISO_HASHES}"

if [ "${failed}" -ne 0 ]; then
  printf 'error: p7-os-views failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p7-os-views\n'
exit 0
