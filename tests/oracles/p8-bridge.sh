#!/bin/sh
# P8.9: operator bridge approval view. Verbatim copy, not a mount.
# Host-only. Isolation destroot is required; never write live /srv/aios/src.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
SEED="${ROOT}/seed/work-runtime"
ISO_SEED="${ROOT}/payload/profile/airootfs/srv/aios/seeds/work-runtime"
HASHES="${ROOT}/payload/hashes.txt"
ISO_HASHES="${ROOT}/payload/profile/airootfs/usr/lib/aios/hashes.txt"
failed=0
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

fail() {
  printf 'error: %s\n' "$*" >&2
  failed=$((failed + 1))
}

WR_BEFORE=0
if [ -e /srv/aios/src ]; then
  WR_BEFORE=1
fi
LIVE_SYS_BEFORE=0
if [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  LIVE_SYS_BEFORE=1
fi
# Probe real /home only for accidental creation of a unique name we never own.
HOME_SENTINEL="/home/aios-oracle-must-not-create"

TMP=$(mktemp -d)
BRIDGE_KEY=""
cleanup() {
  rm -rf "${TMP}"
  if [ -n "${BRIDGE_KEY}" ]; then
    rm -rf "/tmp/aios-bridge-${BRIDGE_KEY}"
  fi
}
trap cleanup EXIT

[ -f "${SEED}/bridge.py" ] || fail "missing seed/work-runtime/bridge.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/bridge.py" ] || fail "missing ISO seed bridge.py"
cmp -s "${SEED}/bridge.py" "${ISO_SEED}/bridge.py" \
  || fail "ISO bridge.py != seed bridge.py"
cmp -s "${SEED}/main.py" "${ISO_SEED}/main.py" \
  || fail "ISO main.py != seed main.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'copy is verbatim, not a mount' "${SEED}/bridge.py" \
  || fail "bridge.py missing verbatim-copy rule"
grep -q 'not operator-computer work' "${SEED}/bridge.py" \
  || fail "bridge.py missing login/2FA refusal"
grep -q 'path_visible' "${SEED}/bridge.py" \
  || fail "bridge.py missing path_visible"
grep -q 'view = "bridge"' "${SEED}/main.py" \
  || fail "main.py missing bridge approval view"
grep -q 'approval is an operator view, not a model tool' "${SEED}/bridge.py" \
  || fail "bridge.py missing operator-view approval split"
grep -q 'bridge grant mismatch' "${SEED}/bridge.py" \
  || fail "bridge.py missing grant freeze"
grep -q 'copy from workspace is client-mediated' "${SEED}/bridge.py" \
  || fail "bridge.py missing copy-from fail-closed"
if grep -nE '^(import|from)[[:space:]]+(urllib|aios_agent|http\.client)\b' \
  "${SEED}/bridge.py" >/dev/null; then
  fail "bridge must not import urllib/aios_agent/http.client"
fi
if grep -q -- '-Syu' "${SEED}/bridge.py"; then
  fail "bridge.py contains -Syu (L-20)"
fi
if grep -nE 'os\.symlink|os\.link\(' "${SEED}/bridge.py" >/dev/null; then
  fail "bridge.py must not mount or symlink"
fi

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}"
cp -a "${SEED}/main.py" "${SEED}/wake.py" "${SEED}/skills.py" \
  "${SEED}/provider.py" "${SEED}/workers.py" "${SEED}/routines.py" \
  "${SEED}/bridge.py" "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/main.py" "${_pyct}/wake.py" "${_pyct}/skills.py" \
  "${_pyct}/provider.py" "${_pyct}/workers.py" "${_pyct}/routines.py" \
  "${_pyct}/bridge.py" \
  || fail "py_compile seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-bridge.sh"

SRC="${TMP}/src"
OP="${TMP}/op"
mkdir -p "${SRC}" "${OP}" "${SRC}/notes"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope" "${SRC}/notes"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
printf '%s\n' 'UNIQUE-BRIDGE-SECRET-BYTES' > "${OP}/secret.txt"
printf '%s\n' 'UNIQUE-BRIDGE-READ-BODY' > "${OP}/private.txt"
printf '%s\n' 'workspace-note' > "${SRC}/notes/outbox.txt"
printf '%s\n' "{\"responses\":[{\"bridge_copy\":{\"id\":\"c1\",\"src\":\"${OP}/secret.txt\",\"dst\":\"notes/copied.txt\",\"direction\":\"to_workspace\"}}]}" \
  > "${TMP}/copy.json"
printf '%s\n' "{\"responses\":[{\"actions\":[{\"tool\":\"bridge_copy\",\"id\":\"csame\",\"src\":\"${OP}/secret.txt\",\"dst\":\"notes/same-turn.txt\",\"direction\":\"to_workspace\"},{\"tool\":\"bridge_approve\",\"id\":\"csame\"}]}]}" \
  > "${TMP}/same-turn.json"
printf '%s\n' '{"responses":[{"bridge_approve":"c1"}]}' > "${TMP}/approve.json"
printf '%s\n' "{\"responses\":[{\"bridge_read\":{\"id\":\"r1\",\"path\":\"${OP}/private.txt\"}}]}" \
  > "${TMP}/read.json"
printf '%s\n' "{\"responses\":[{\"bridge_shell\":{\"id\":\"s1\",\"command\":\"echo ran-ok > ${TMP}/shell-ran.txt\"}}]}" \
  > "${TMP}/shell.json"
printf '%s\n' "{\"responses\":[{\"bridge_copy\":{\"id\":\"cfhome\",\"src\":\"notes/outbox.txt\",\"dst\":\"${HOME_SENTINEL}\",\"direction\":\"from_workspace\"}}]}" \
  > "${TMP}/copy-from-home.json"
printf '%s\n' "{\"responses\":[{\"bridge_copy\":{\"id\":\"cftmp\",\"src\":\"notes/outbox.txt\",\"dst\":\"${TMP}/dropbox.txt\",\"direction\":\"from_workspace\"}}]}" \
  > "${TMP}/copy-from-tmp.json"
printf '%s\n' 'OTHER-PRIVATE' > "${OP}/other.txt"
printf '%s\n' '{"responses":[{"bridge_shell":{"id":"login1","command":"login"}}]}' \
  > "${TMP}/login.json"
printf '%s\n' '{"responses":[{"bridge_shell":{"id":"tfa","op":"2fa"}}]}' \
  > "${TMP}/tfa.json"
printf '%s\n' '{"responses":[{"bridge_shell":{"id":"cap","command":"solve captcha"}}]}' \
  > "${TMP}/captcha.json"
printf '%s\n' '{"responses":[{"bridge_shell":{"id":"pay","op":"payment"}}]}' \
  > "${TMP}/pay.json"
printf '%s\n' "{\"responses\":[{\"bridge_copy\":{\"id\":\"home1\",\"src\":\"${HOME_SENTINEL}\",\"dst\":\"notes/x.txt\",\"direction\":\"to_workspace\"}}]}" \
  > "${TMP}/livehome.json"

run_turn() {
  _fix=$1
  shift
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OPERATOR_HOME="${OP}" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${_fix}" \
    python3 "${SRC}/main.py" turn "$@"
}

run_approve() {
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OPERATOR_HOME="${OP}" \
    python3 "${SRC}/main.py" approve "$@"
}

run_deny() {
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_OPERATOR_HOME="${OP}" \
    python3 "${SRC}/main.py" deny "$@"
}

grant_of() {
  printf '%s\n' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("bridge_operator") or {}).get("grant") or "")'
}

BRIDGE_KEY=$(python3 -c 'import hashlib,os,sys; print(hashlib.sha256(os.path.abspath(sys.argv[1]).encode("utf-8")).hexdigest()[:12])' "${SRC}")

_copy=$(run_turn "${TMP}/copy.json" "copy private") || true
printf '%s\n' "${_copy}" | python3 -c '
import json, os, sys
d = json.load(sys.stdin)
src, dest, secret = sys.argv[1], sys.argv[2], sys.argv[3]
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if d.get("view") != "bridge":
    raise SystemExit("view %s" % d.get("view"))
b = d.get("bridge") or {}
if b.get("status") != "pending":
    raise SystemExit("status %s" % b.get("status"))
if "approve" not in (b.get("actions") or []):
    raise SystemExit("actions %s" % b.get("actions"))
if b.get("path_visible"):
    raise SystemExit("path visible before approval")
blob = json.dumps({k: v for k, v in d.items() if k not in ("model_text", "prompt", "asked", "bridge_operator")})
if src in blob:
    raise SystemExit("operator path visible on work surface")
opv = d.get("bridge_operator") or {}
if not opv.get("path_visible"):
    raise SystemExit("operator view must show the path")
if src not in (opv.get("path") or ""):
    raise SystemExit("operator view missing path")
if not opv.get("grant"):
    raise SystemExit("operator view missing grant")
if secret in (d.get("delivered") or "") or secret in (d.get("surface") or ""):
    raise SystemExit("secret delivered before approval")
if os.path.isfile(dest):
    raise SystemExit("copy ran before approval")
' "${OP}/secret.txt" "${SRC}/notes/copied.txt" "UNIQUE-BRIDGE-SECRET-BYTES" \
  || fail "copy must wait for approval: ${_copy}"
[ ! -e "${SRC}/notes/copied.txt" ] || fail "copy dest exists before approval"
if grep -R -F "${OP}/secret.txt" "${SRC}" >/dev/null 2>&1; then
  fail "operator path visible in the workspace before approval"
fi
GRANT_C1=$(grant_of "${_copy}")
[ -n "${GRANT_C1}" ] || fail "missing grant on copy request"

_same=$(run_turn "${TMP}/same-turn.json" "same turn copy approve") || true
printf '%s\n' "${_same}" | python3 -c '
import json, os, sys
d = json.load(sys.stdin)
dest = sys.argv[1]
err = d.get("error") or ""
if "operator view" not in err:
    raise SystemExit("same-turn approve not refused: %s" % err)
if os.path.isfile(dest):
    raise SystemExit("same-turn copy ran")
b = d.get("bridge") or {}
if b.get("status") and b.get("status") != "pending":
    raise SystemExit("same-turn status %s" % b.get("status"))
' "${SRC}/notes/same-turn.txt" \
  || fail "same-turn copy+approve must stay pending: ${_same}"
[ ! -e "${SRC}/notes/same-turn.txt" ] || fail "same-turn dest exists"

_model=$(run_turn "${TMP}/approve.json" "model approve") || true
printf '%s\n' "${_model}" | grep -q 'approval is an operator view' \
  || fail "model approve must be refused: ${_model}"
[ ! -e "${SRC}/notes/copied.txt" ] || fail "model approve copied"

printf '%s\n' 'TAMPER-OTHER' > "${OP}/other.txt"
python3 - "${TMP}/root/bridge-state/c1.json" "${OP}/other.txt" <<'PY'
import json, sys
path, src = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    rec = json.load(fh)
rec["src"] = src
with open(path, "w", encoding="utf-8") as fh:
    json.dump(rec, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
_tamper=$(run_approve c1 "${GRANT_C1}") || true
printf '%s\n' "${_tamper}" | grep -q 'bridge grant mismatch' \
  || fail "tampered src must fail approve: ${_tamper}"
[ ! -e "${SRC}/notes/copied.txt" ] || fail "tampered approve copied"
[ ! -e "${SRC}/notes/copied.txt" ] || fail "tampered dest exists"
if grep -q 'TAMPER-OTHER' "${SRC}/notes/copied.txt" 2>/dev/null; then
  fail "tampered src was used as the grant"
fi

python3 - "${TMP}/root/bridge-state/c1.json" "${OP}/secret.txt" <<'PY'
import json, sys
path, src = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    rec = json.load(fh)
rec["src"] = src
with open(path, "w", encoding="utf-8") as fh:
    json.dump(rec, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

_ok=$(run_approve c1 "${GRANT_C1}") || true
printf '%s\n' "${_ok}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if d.get("view") != "bridge":
    raise SystemExit("view %s" % d.get("view"))
b = d.get("bridge") or {}
if b.get("status") != "approved":
    raise SystemExit("status %s" % b.get("status"))
if b.get("path_visible"):
    raise SystemExit("path visible after copy")
if "UNIQUE-BRIDGE-SECRET-BYTES" in (d.get("delivered") or ""):
    raise SystemExit("copy dumped bytes onto the surface")
' || fail "approve copy failed: ${_ok}"
[ -f "${SRC}/notes/copied.txt" ] || fail "copy dest missing after approval"
[ ! -L "${SRC}/notes/copied.txt" ] || fail "copy dest is a symlink (mount)"
cmp -s "${OP}/secret.txt" "${SRC}/notes/copied.txt" \
  || fail "copy is not verbatim"
if grep -R -F "${OP}/secret.txt" "${SRC}" >/dev/null 2>&1; then
  fail "operator path visible in the workspace after copy"
fi
printf '%s\n' 'CHANGED-SRC' > "${OP}/secret.txt"
if cmp -s "${OP}/secret.txt" "${SRC}/notes/copied.txt"; then
  fail "copy tracked the source (a mount, not a copy)"
fi
printf '%s\n' 'CHANGED-DST' > "${SRC}/notes/copied.txt"
grep -q 'CHANGED-SRC' "${OP}/secret.txt" \
  || fail "src lost its mutation"
if grep -q 'CHANGED-DST' "${OP}/secret.txt"; then
  fail "mutating dest changed src (a mount)"
fi

printf '%s\n' 'DENY-SECRET' > "${OP}/deny.txt"
printf '%s\n' "{\"responses\":[{\"bridge_copy\":{\"id\":\"c2\",\"src\":\"${OP}/deny.txt\",\"dst\":\"notes/denied.txt\",\"direction\":\"to_workspace\"}}]}" \
  > "${TMP}/copy2.json"
_c2=$(run_turn "${TMP}/copy2.json" "copy deny") || true
printf '%s\n' "${_c2}" | grep -q '"status": "pending"' \
  || fail "second copy not pending: ${_c2}"
_d2=$(run_deny c2) || true
printf '%s\n' "${_d2}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if (d.get("bridge") or {}).get("status") != "denied":
    raise SystemExit("status %s" % d.get("bridge"))
' || fail "deny failed: ${_d2}"
[ ! -e "${SRC}/notes/denied.txt" ] || fail "denied copy still ran"

_rd=$(run_turn "${TMP}/read.json" "read private") || true
printf '%s\n' "${_rd}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if d.get("view") != "bridge":
    raise SystemExit("view %s" % d.get("view"))
if "UNIQUE-BRIDGE-READ-BODY" in (d.get("delivered") or ""):
    raise SystemExit("read ran before approval")
if (d.get("bridge") or {}).get("path_visible"):
    raise SystemExit("read path visible")
' || fail "read must wait: ${_rd}"
GRANT_R1=$(grant_of "${_rd}")
_ra=$(run_approve r1 "${GRANT_R1}") || true
printf '%s\n' "${_ra}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if "UNIQUE-BRIDGE-READ-BODY" not in (d.get("delivered") or ""):
    raise SystemExit("approved read missing body")
' || fail "approved read failed: ${_ra}"

_sh=$(run_turn "${TMP}/shell.json" "shell private") || true
printf '%s\n' "${_sh}" | grep -q '"status": "pending"' \
  || fail "shell not pending: ${_sh}"
[ ! -e "${TMP}/shell-ran.txt" ] || fail "shell ran before approval"
GRANT_S1=$(grant_of "${_sh}")
_sa=$(run_approve s1 "${GRANT_S1}") || true
printf '%s\n' "${_sa}" | grep -q '"status": "approved"' \
  || fail "shell approve failed: ${_sa}"
[ -f "${TMP}/shell-ran.txt" ] || fail "approved shell did not run"
grep -q 'ran-ok' "${TMP}/shell-ran.txt" || fail "shell output missing"

_cfh=$(run_turn "${TMP}/copy-from-home.json" "copy from home") || true
printf '%s\n' "${_cfh}" | grep -q 'client-mediated' \
  || fail "copy_from /home must fail closed: ${_cfh}"
[ ! -e "${HOME_SENTINEL}" ] || fail "copy_from wrote ${HOME_SENTINEL}"

_cft=$(run_turn "${TMP}/copy-from-tmp.json" "copy from tmp") || true
printf '%s\n' "${_cft}" | grep -q '"status": "pending"' \
  || fail "copy_from tmp not pending: ${_cft}"
[ ! -e "${TMP}/dropbox.txt" ] || fail "copy_from ran before approval"
GRANT_CF=$(grant_of "${_cft}")
_cfa=$(run_approve cftmp "${GRANT_CF}") || true
printf '%s\n' "${_cfa}" | grep -q '"status": "approved"' \
  || fail "copy_from tmp approve failed: ${_cfa}"
[ -f "${TMP}/dropbox.txt" ] || fail "copy_from tmp dest missing"
case "${TMP}/dropbox.txt" in
  /home/*) fail "copy_from dest is under /home" ;;
esac
cmp -s "${SRC}/notes/outbox.txt" "${TMP}/dropbox.txt" \
  || fail "copy_from tmp is not verbatim"

for pair in "login:${TMP}/login.json" "2fa:${TMP}/tfa.json" "captcha:${TMP}/captcha.json" "payment:${TMP}/pay.json"; do
  name=${pair%%:*}
  fix=${pair#*:}
  _bad=$(run_turn "${fix}" "${name}") || true
  printf '%s\n' "${_bad}" | grep -q 'not operator-computer work' \
    || fail "${name} must be refused: ${_bad}"
done

_home=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK -u AIOS_OPERATOR_HOME \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${TMP}/livehome.json" \
    python3 "${SRC}/main.py" turn "live home" 2>/dev/null || true
)
printf '%s\n' "${_home}" | grep -q 'AIOS_OPERATOR_HOME' \
  || fail "live /home must be refused: ${_home}"
[ ! -e "${HOME_SENTINEL}" ] || fail "oracle created ${HOME_SENTINEL}"

_mod=$(
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK -u AIOS_ROOT -u AIOS_BRIDGE_STATE \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_OPERATOR_HOME="${OP}" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${TMP}/copy.json" \
    python3 "${SRC}/main.py" turn "tmp modes" 2>/dev/null || true
)
BDIR="/tmp/aios-bridge-${BRIDGE_KEY}"
if [ -d "${BDIR}" ]; then
  BDIR_MODE=$(stat -c %a "${BDIR}")
  BFILE=$(printf '%s\n' "${BDIR}"/*.json)
  BFILE_MODE=$(stat -c %a "${BFILE}")
  [ "${BDIR_MODE}" = "700" ] || fail "bridge state dir mode ${BDIR_MODE}, want 700"
  [ "${BFILE_MODE}" = "600" ] || fail "bridge state file mode ${BFILE_MODE}, want 600"
  rm -rf "${BDIR}"
else
  fail "unset AIOS_ROOT did not create ${BDIR}: ${_mod}"
fi
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_ROOT bridge turn created /srv/aios/src"
fi

env -u AIOS_WORK_SRC env -u AIOS_ROOT env -u AIOS_OPERATOR_HOME \
  python3 "${SRC}/main.py" turn bridge >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC bridge turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/bridge.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed bridge.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/bridge.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed bridge.py"
grep -Fq '/srv/aios/seeds/work-runtime/bridge.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed bridge.py"

(cd "${ROOT}" && grep -E '^[0-9a-f]{64} ' "${HASHES}" | sha256sum -c --strict - >/dev/null) \
  || fail "sha256sum -c payload/hashes.txt --strict"

while IFS= read -r line || [ -n "${line}" ]; do
  [ -n "${line}" ] || continue
  case "${line}" in
    \#*) continue ;;
  esac
  hash=${line%% *}
  path=${line#* }
  path=${path# }
  case "${path}" in
    /*) f="${ROOT}/payload/profile/airootfs${path}" ;;
    *) f="${ROOT}/payload/profile/airootfs/usr/lib/aios/${path}" ;;
  esac
  [ -f "${f}" ] || fail "ISO hashed path missing: ${path}"
  printf '%s  %s\n' "${hash}" "${f}" | sha256sum -c --strict - >/dev/null \
    || fail "ISO hash mismatch: ${path}"
done < "${ISO_HASHES}"

if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "oracle created /srv/aios/src (HI-15)"
fi
if [ "${LIVE_SYS_BEFORE}" -eq 0 ] \
  && [ -e /etc/systemd/system/aios-work-runtime.service ]; then
  fail "oracle wrote live system aios-work-runtime.service"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'error: p8-bridge failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-bridge\n'
exit 0
