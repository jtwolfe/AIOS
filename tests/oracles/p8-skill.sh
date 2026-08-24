#!/bin/sh
# P8.5: follow a skill only after reading its body this turn.
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

TMP=$(mktemp -d)
cleanup() {
  rm -rf "${TMP}"
}
trap cleanup EXIT

[ -f "${SEED}/skills.py" ] || fail "missing seed/work-runtime/skills.py"
[ -f "${SEED}/main.py" ] || fail "missing seed/work-runtime/main.py"
[ -f "${ISO_SEED}/skills.py" ] || fail "missing ISO seed skills.py"
cmp -s "${SEED}/skills.py" "${ISO_SEED}/skills.py" \
  || fail "ISO skills.py != seed skills.py"
cmp -s "${SEED}/main.py" "${ISO_SEED}/main.py" \
  || fail "ISO main.py != seed main.py"
diff -qr -x '__pycache__' -x '*.pyc' "${SEED}" "${ISO_SEED}" \
  || fail "ISO work-runtime seed != seed/work-runtime"

grep -q 'following a skill without reading its body this turn fails' \
  "${SEED}/main.py" \
  || fail "main.py missing this-turn read rule"
if grep -n 'AIOS_SKILLS' "${SEED}/main.py" "${SEED}/skills.py" >/dev/null; then
  fail "work runtime must not honour AIOS_SKILLS (OS skills are not a back door)"
fi

_pyct="${TMP}/pycompile"
mkdir -p "${_pyct}"
cp -a "${SEED}/main.py" "${SEED}/skills.py" "${SEED}/wake.py" \
  "${SEED}/provider.py" "${SEED}/live.py" "${SEED}/connectors.py" \
  "${_pyct}/"
python3 -m py_compile \
  "${_pyct}/main.py" "${_pyct}/skills.py" "${_pyct}/wake.py" \
  "${_pyct}/provider.py" "${_pyct}/live.py" "${_pyct}/connectors.py" \
  || fail "py_compile seed work-runtime failed"
sh -n "${0}" || fail "sh -n p8-skill.sh"

SRC="${TMP}/src"
mkdir -p "${SRC}"
cp -a "${SEED}/." "${SRC}/"
mkdir -p "${SRC}/envelope"
printf '%s\n' 'enabled: yes' > "${SRC}/envelope/compiled.md"
cat > "${SRC}/skills/sample.md" <<'EOF'
---
name: sample
description: Catalog-only line for the sample skill.
---
UNIQUE-SAMPLE-BODY-MUST-NOT-BE-IN-CATALOG
EOF
printf '%s\n' '{"responses":[{"skill_follow":"sample"}]}' > "${TMP}/follow.json"
printf '%s\n' '{"responses":[{"skill_read":"sample"},{"skill_follow":"sample","send":"followed-sample"}]}' \
  > "${TMP}/read.json"
printf '%s\n' '{"responses":[{"send":"catalog-only"}]}' > "${TMP}/send.json"
mkdir -p "${TMP}/os-skills/pacman"
cat > "${TMP}/os-skills/pacman/SKILL.md" <<'EOF'
---
name: pacman
description: OS privileged skill
---
This is an OS skill body and must not load.
EOF

run_turn() {
  _fix=$1
  shift
  env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
    AIOS_WORK_SRC="${SRC}" \
    AIOS_ROOT="${TMP}/root" \
    AIOS_SKILLS="${TMP}/os-skills" \
    AIOS_PROVIDER=fixture \
    AIOS_FIXTURE="${_fix}" \
    python3 "${SRC}/main.py" turn "$@"
}

_cat=$(run_turn "${TMP}/send.json" "list skills") || true
printf '%s\n' "${_cat}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
p = d.get("prompt") or ""
i2 = p.find("[inject 2] skills catalog")
i3 = p.find("[inject 3] tools")
if i2 < 0 or i3 < 0 or i3 <= i2:
    raise SystemExit("catalog section missing")
catalog = p[i2:i3]
if "- sample: Catalog-only line for the sample skill." not in catalog:
    raise SystemExit("catalog missing sample name+description")
if "UNIQUE-SAMPLE-BODY-MUST-NOT-BE-IN-CATALOG" in catalog:
    raise SystemExit("skill body leaked into catalog")
if "OS privileged skill" in p or "- pacman:" in catalog:
    raise SystemExit("OS skill loaded through AIOS_SKILLS")
' || fail "catalog must be name+description this tree only: ${_cat}"

_bad=$(run_turn "${TMP}/follow.json" "follow sample") || true
printf '%s\n' "${_bad}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("outcome") != "failed":
    raise SystemExit("outcome %s" % d.get("outcome"))
err = d.get("error") or ""
if "without reading its body this turn" not in err:
    raise SystemExit("error %s" % err)
if d.get("skills_followed"):
    raise SystemExit("followed without read")
if d.get("delivered"):
    raise SystemExit("delivered on failed follow")
' || fail "follow without read must fail: ${_bad}"

_ok=$(run_turn "${TMP}/read.json" "follow sample after read") || true
printf '%s\n' "${_ok}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    raise SystemExit("error %s" % d.get("error"))
if "sample" not in (d.get("skills_read") or []):
    raise SystemExit("skills_read %s" % d.get("skills_read"))
if "sample" not in (d.get("skills_followed") or []):
    raise SystemExit("skills_followed %s" % d.get("skills_followed"))
if d.get("delivered") != "followed-sample":
    raise SystemExit("delivered %s" % d.get("delivered"))
body = "UNIQUE-SAMPLE-BODY-MUST-NOT-BE-IN-CATALOG"
if body not in (d.get("context") or ""):
    raise SystemExit("skill body missing from follow-up context")
p = d.get("prompt") or ""
i2 = p.find("[inject 2] skills catalog")
i3 = p.find("[inject 3] tools")
if i2 < 0 or i3 <= i2:
    raise SystemExit("catalog section missing")
if body in p[i2:i3]:
    raise SystemExit("skill body leaked into inject 2")
' || fail "read then follow must pass: ${_ok}"

env -u AIOS_WORK_SRC env -u AIOS_ROOT env -u AIOS_SKILLS \
  python3 "${SRC}/main.py" turn follow >/dev/null 2>"${TMP}/unset.err" || true
if [ "${WR_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
  fail "unset AIOS_WORK_SRC skill turn created /srv/aios/src"
fi

grep -Fq 'seed/work-runtime/skills.py' "${HASHES}" \
  || fail "payload/hashes.txt must pin seed skills.py"
grep -Fq 'payload/profile/airootfs/srv/aios/seeds/work-runtime/skills.py' \
  "${HASHES}" \
  || fail "payload/hashes.txt must pin ISO seed skills.py"
grep -Fq '/srv/aios/seeds/work-runtime/skills.py' "${ISO_HASHES}" \
  || fail "ISO hashes.txt must pin seed skills.py"

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
  printf 'error: p8-skill failed (%s check(s))\n' "${failed}" >&2
  exit 1
fi
printf 'ok: p8-skill\n'
exit 0
