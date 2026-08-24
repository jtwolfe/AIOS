#!/bin/sh
# P8.14 album helpers. Sourced by vm-work-* / vm-bots-*.
# Host: fixture drive + wrap p8-* when present. Isolation destroot is
# required; never write live /etc, /usr, /srv/aios when unset.
# QEMU only through tests/vm/run.sh and only if AIOS_VM_BOOT=1.
# Incomplete if any named surface fixture or vm oracle is missing.

# shellcheck disable=SC2034
P814_SURFACES='work-yes
work-no
work-write-set
work-surface
work-wake
work-skill
work-connector
work-worker
work-routine
work-bridge
work-store
work-provider
work-disable
bots-off
bots-job'

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

p814_root() {
  if [ -n "${P814_ROOT:-}" ]; then
    printf '%s\n' "${P814_ROOT}"
    return 0
  fi
  # $0 is the caller when this file is sourced. Walk up to the repo root.
  _d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  while [ -n "${_d}" ] && [ "${_d}" != / ]; do
    if [ -f "${_d}/tests/vm/oracles/common.sh" ] && [ -f "${_d}/AGENTS.md" ]; then
      P814_ROOT=${_d}
      printf '%s\n' "${P814_ROOT}"
      return 0
    fi
    _d=$(CDPATH= cd -- "${_d}/.." && pwd)
  done
  die "cannot resolve AIOS root from $0"
}

p814_is_guest() {
  [ "${AIOS_VM_GUEST:-0}" = 1 ]
}

p814_refuse_worktree() {
  _root=$(p814_root)
  if [ -f "${_root}/payload/profile/airootfs/etc/systemd/system/aios-work.slice" ]; then
    die "AIOS_VM_GUEST=1 in the worktree; refuse (do not mutate the workstation)"
  fi
}

p814_snapshot_live() {
  P814_SRC_BEFORE=0
  [ -e /srv/aios/src ] && P814_SRC_BEFORE=1
  P814_MEM_BEFORE=0
  [ -e /srv/aios/memory ] && P814_MEM_BEFORE=1
  P814_BIP_BEFORE=0
  [ -e /srv/aios/state/bootstrap-in-progress ] && P814_BIP_BEFORE=1
  P814_ANS_BEFORE=0
  [ -e /srv/aios/state/bootstrap-in-progress/answers.json ] && P814_ANS_BEFORE=1
  P814_CLAUSE_BEFORE=0
  [ -e /srv/aios/envelope/work-runtime.md ] && P814_CLAUSE_BEFORE=1
  P814_BOTS_CLAUSE_BEFORE=0
  [ -e /srv/aios/envelope/work-runtime-bots.md ] && P814_BOTS_CLAUSE_BEFORE=1
  P814_WANTS_BEFORE=0
  [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ] \
    && P814_WANTS_BEFORE=1
  P814_BOTS_WANTS_BEFORE=0
  [ -e /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service ] \
    && P814_BOTS_WANTS_BEFORE=1
  P814_SYS_BEFORE=0
  [ -e /etc/systemd/system/aios-work-runtime.service ] && P814_SYS_BEFORE=1
  P814_SYS_BOTS_BEFORE=0
  [ -e /etc/systemd/system/aios-work-runtime-bots.service ] \
    && P814_SYS_BOTS_BEFORE=1
  P814_UNIT_BEFORE=0
  [ -e /usr/lib/systemd/user/aios-work-runtime.service ] && P814_UNIT_BEFORE=1
  P814_BOTS_UNIT_BEFORE=0
  [ -e /usr/lib/systemd/user/aios-work-runtime-bots.service ] \
    && P814_BOTS_UNIT_BEFORE=1
  P814_LINGER_BEFORE=0
  [ -e /var/lib/systemd/linger/aios-work ] && P814_LINGER_BEFORE=1
  P814_ETC_AIOS_BEFORE=0
  [ -e /etc/aios ] && P814_ETC_AIOS_BEFORE=1
  return 0
}

p814_assert_isolation() {
  if [ "${P814_SRC_BEFORE}" -eq 0 ] && [ -e /srv/aios/src ]; then
    die "oracle created /srv/aios/src (HI-15)"
  fi
  if [ "${P814_MEM_BEFORE}" -eq 0 ] && [ -e /srv/aios/memory ]; then
    die "oracle created /srv/aios/memory"
  fi
  if [ "${P814_BIP_BEFORE}" -eq 0 ] \
    && [ -e /srv/aios/state/bootstrap-in-progress ]; then
    die "oracle created /srv/aios/state/bootstrap-in-progress (HI-09)"
  fi
  if [ "${P814_ANS_BEFORE}" -eq 0 ] \
    && [ -e /srv/aios/state/bootstrap-in-progress/answers.json ]; then
    die "oracle created live answers.json (HI-09)"
  fi
  if [ "${P814_CLAUSE_BEFORE}" -eq 0 ] \
    && [ -e /srv/aios/envelope/work-runtime.md ]; then
    die "oracle wrote live envelope/work-runtime.md"
  fi
  if [ "${P814_BOTS_CLAUSE_BEFORE}" -eq 0 ] \
    && [ -e /srv/aios/envelope/work-runtime-bots.md ]; then
    die "oracle wrote live envelope/work-runtime-bots.md"
  fi
  if [ "${P814_WANTS_BEFORE}" -eq 0 ] \
    && [ -e /etc/systemd/user/default.target.wants/aios-work-runtime.service ]; then
    die "oracle wrote live user-unit wants"
  fi
  if [ "${P814_BOTS_WANTS_BEFORE}" -eq 0 ] \
    && [ -e /etc/systemd/user/default.target.wants/aios-work-runtime-bots.service ]; then
    die "oracle wrote live bots wants"
  fi
  if [ "${P814_SYS_BEFORE}" -eq 0 ] \
    && [ -e /etc/systemd/system/aios-work-runtime.service ]; then
    die "oracle wrote live system aios-work-runtime.service"
  fi
  if [ "${P814_SYS_BOTS_BEFORE}" -eq 0 ] \
    && [ -e /etc/systemd/system/aios-work-runtime-bots.service ]; then
    die "oracle wrote live system bots unit"
  fi
  if [ "${P814_UNIT_BEFORE}" -eq 0 ] \
    && [ -e /usr/lib/systemd/user/aios-work-runtime.service ]; then
    die "oracle wrote live aios-work-runtime.service"
  fi
  if [ "${P814_BOTS_UNIT_BEFORE}" -eq 0 ] \
    && [ -e /usr/lib/systemd/user/aios-work-runtime-bots.service ]; then
    die "oracle wrote live bots user unit"
  fi
  if [ "${P814_LINGER_BEFORE}" -eq 0 ] \
    && [ -e /var/lib/systemd/linger/aios-work ]; then
    die "oracle wrote live linger/aios-work"
  fi
  if [ "${P814_ETC_AIOS_BEFORE}" -eq 0 ] && [ -e /etc/aios ]; then
    die "oracle wrote live /etc/aios"
  fi
}

p814_album_complete() {
  _root=$(p814_root)
  _missing=0
  for _s in ${P814_SURFACES}
  do
    if [ ! -f "${_root}/tests/vm/fixtures/${_s}.json" ]; then
      printf 'error: missing tests/vm/fixtures/%s.json (P8.14 incomplete)\n' \
        "${_s}" >&2
      _missing=$((_missing + 1))
    fi
    if [ ! -f "${_root}/tests/vm/oracles/vm-${_s}.sh" ]; then
      printf 'error: missing tests/vm/oracles/vm-%s.sh (P8.14 incomplete)\n' \
        "${_s}" >&2
      _missing=$((_missing + 1))
    elif [ ! -x "${_root}/tests/vm/oracles/vm-${_s}.sh" ]; then
      printf 'error: tests/vm/oracles/vm-%s.sh must be executable\n' "${_s}" >&2
      _missing=$((_missing + 1))
    fi
  done
  [ -f "${_root}/tests/vm/fixtures/smoke.json" ] \
    || { printf 'error: missing smoke.json\n' >&2; _missing=$((_missing + 1)); }
  [ -f "${_root}/tests/vm/fixtures/recover.json" ] \
    || { printf 'error: missing recover.json\n' >&2; _missing=$((_missing + 1)); }
  [ "${_missing}" -eq 0 ] || die "P8.14 album incomplete (${_missing} missing)"
}

p814_json_list() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
val = data.get(key)
if val is None:
    raise SystemExit("missing %s" % key)
if not isinstance(val, list):
    raise SystemExit("%s must be a list" % key)
for item in val:
    if not isinstance(item, str) or not item.strip():
        raise SystemExit("command must be a non-empty string")
    sys.stdout.write("%s\n" % item)
PY
}

p814_check_fixture() {
  _root=$(p814_root)
  python3 - "${_root}/tests/vm/fixtures" "$1" <<'PY' || die "fixture schema $1"
import json
import sys

fixtures, surface = sys.argv[1], sys.argv[2]
path = "%s/%s.json" % (fixtures, surface)
INSTALLER = (
    "view",
    "answer",
    "skip",
    "accept",
    "reject",
    "resume",
    "quit",
    "brake",
    "send",
    "mode",
)
WORK = INSTALLER + (
    "enact",
    "rollback",
    "inspect",
    "bots",
    "attach",
    "start",
    "cancel",
    "poll",
    "open",
    "stop",
    "help",
)
NEED_YES = (
    "work-yes",
    "work-write-set",
    "work-surface",
    "work-wake",
    "work-skill",
    "work-connector",
    "work-worker",
    "work-routine",
    "work-bridge",
    "work-store",
    "work-provider",
    "work-disable",
    "bots-off",
    "bots-job",
)
INJECTS = (
    "AGENTS.md",
    "skills catalog",
    "tools",
    "operational notes",
    "envelope bit",
)
WRITE_SET = (
    "/tmp",
    "/var/tmp",
    "/srv/aios/src/work-runtime",
)


def load(p):
    with open(p, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit("%s is not an object" % p)
    return data


def cmds(path, data, key, allowed):
    val = data.get(key)
    if val is None:
        return []
    if not isinstance(val, list) or not val:
        raise SystemExit("%s %s must be a non-empty list" % (path, key))
    for item in val:
        if not isinstance(item, str) or not item.strip():
            raise SystemExit("%s %s command empty" % (path, key))
        cmd = item.split(None, 1)[0].lower()
        if cmd not in allowed:
            raise SystemExit("%s unknown command %s" % (path, cmd))
    return val


data = load(path)
want_name = "vm-%s" % surface
if data.get("name") != want_name:
    raise SystemExit("%s name must be %s" % (path, want_name))
operator = data.get("operator")
if not isinstance(operator, str) or not operator.strip():
    raise SystemExit("%s operator must be asked (L-13)" % path)
if data.get("bots") is True:
    raise SystemExit("%s answers.json bots must never be a yes" % path)
vetoes = data.get("vetoes")
if not isinstance(vetoes, dict):
    raise SystemExit("%s vetoes must be an object" % path)
if vetoes.get("remotes") is True:
    raise SystemExit("%s remotes must not be yes" % path)
if data.get("provider") == "live":
    raise SystemExit("%s must not require a live Grok token" % path)
blob = json.dumps(data)
for tok in ("xai-", "sk-live", "auth.x.ai", "GROK_API"):
    if tok.lower() in blob.lower():
        raise SystemExit("%s looks like a live token" % path)
joined = "\n".join(cmds(path, data, "commands", INSTALLER))
cmds(path, data, "work_commands", WORK) if "work_commands" in data else None
cmds(path, data, "os_commands", WORK) if "os_commands" in data else None
if surface in NEED_YES:
    if data.get("work_runtime") is not True:
        raise SystemExit("%s work_runtime must be JSON true" % path)
    if "answer work-runtime yes" not in joined:
        raise SystemExit("%s must answer work-runtime yes" % path)
    if "skip work-runtime" in joined:
        raise SystemExit("%s skip is not a yes (HI-15)" % path)
elif surface == "work-no":
    if data.get("work_runtime") is True:
        raise SystemExit("%s work_runtime must not be yes (HI-15)" % path)
    if data.get("work_runtime") is not False:
        raise SystemExit("%s work_runtime must be JSON false" % path)
    if "skip work-runtime" not in joined:
        raise SystemExit("%s must skip work-runtime (HI-15)" % path)
    if "work-runtime yes" in joined:
        raise SystemExit("%s skip is not a yes (HI-15)" % path)
if "answer operator" not in joined:
    raise SystemExit("%s must answer operator (L-13)" % path)
if "accept" not in joined:
    raise SystemExit("%s must accept" % path)
if surface == "work-write-set":
    ws = data.get("write_set")
    if not isinstance(ws, list):
        raise SystemExit("%s write_set must be a list" % path)
    for item in WRITE_SET:
        if item not in ws:
            raise SystemExit("%s write_set missing %s" % (path, item))
    if "/home" in ws or "~/src" in ws:
        raise SystemExit("%s write_set must not include home" % path)
if surface == "work-surface":
    work = "\n".join(data.get("work_commands") or [])
    if "view packages" not in work or "enact" not in work:
        raise SystemExit("%s must probe mixed-privilege tools" % path)
if surface == "work-wake":
    got = data.get("injects")
    if got != list(INJECTS):
        raise SystemExit("%s injects must be the wake order" % path)
    if data.get("provider") != "fixture":
        raise SystemExit("%s provider must be fixture" % path)
if surface == "work-skill":
    work = "\n".join(data.get("work_commands") or [])
    blob_l = (work + blob).lower()
    if "without reading" not in blob_l and "skill_follow" not in blob_l:
        raise SystemExit("%s must script follow-without-read" % path)
if surface == "work-connector":
    if "token" not in blob.lower():
        raise SystemExit("%s must script token-in-chat fail" % path)
if surface == "work-worker":
    if "voice" not in blob.lower():
        raise SystemExit("%s must name no user voice" % path)
    if "enact" not in blob.lower():
        raise SystemExit("%s must refuse enact" % path)
if surface == "work-routine":
    if "cron" not in blob.lower() or "listener" not in blob.lower():
        raise SystemExit("%s must name cron xor listeners" % path)
if surface == "work-bridge":
    if "approval" not in blob.lower():
        raise SystemExit("%s must name approval" % path)
    if "mount" not in blob.lower():
        raise SystemExit("%s must refuse a mount" % path)
if surface == "work-store":
    if "/srv/aios/memory" not in blob:
        raise SystemExit("%s must name /srv/aios/memory as not-the-store" % path)
if surface == "work-provider":
    if data.get("provider") != "fixture":
        raise SystemExit("%s provider must be fixture" % path)
if surface == "work-disable":
    if "disable" not in blob.lower():
        raise SystemExit("%s must script disable" % path)
if surface == "bots-off":
    if "bots yes" in joined:
        raise SystemExit("%s bootstrap must not ask bots" % path)
if surface == "bots-job":
    if "path" not in blob.lower() or "slice" not in blob.lower():
        raise SystemExit("%s job must be path+slice+skill" % path)
    if "virsh" not in blob.lower():
        raise SystemExit("%s must refuse virsh" % path)
    if "intent" not in blob.lower():
        raise SystemExit("%s VM start must be an intent" % path)
PY
}

p814_begin() {
  SURFACE=$1
  P814_ROOT=$(p814_root)
  PYTHONDONTWRITEBYTECODE=1
  export PYTHONDONTWRITEBYTECODE
  RUN="${P814_ROOT}/tests/vm/run.sh"
  QEMU="${P814_ROOT}/tests/vm/qemu.sh"
  FIXTURES="${P814_ROOT}/tests/vm/fixtures"
  MAIN="${P814_ROOT}/installer/aios_installer/main.py"
  TUI="${P814_ROOT}/operator-client/tty/aios.py"
  HI="${P814_ROOT}/docs/envelope/hard-invariants.md"
  AIROOTFS="${P814_ROOT}/payload/profile/airootfs"
  SEED="${P814_ROOT}/seed/work-runtime"
  FIXTURE="${FIXTURES}/${SURFACE}.json"
  [ -f "${FIXTURE}" ] || die "missing ${FIXTURE} (P8.14 incomplete)"
  p814_album_complete
  p814_check_fixture "${SURFACE}"
  p814_snapshot_live
  P814_TMP=$(mktemp -d)
  trap 'rm -rf "${P814_TMP}"' EXIT
  P814_BOOT="${P814_TMP}/boot"
  P814_DEST="${P814_TMP}/root"
  P814_BRAKE="${P814_TMP}/unused-brake"
  mkdir -p "${P814_BOOT}" "${P814_DEST}"
}

p814_payload_no_src() {
  [ ! -e "${AIROOTFS}/srv/aios/src" ] \
    || die "ISO airootfs has /srv/aios/src (do not synthesise in the ISO)"
  [ ! -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime.service" ] \
    || die "aios-work-runtime.service must not be a system unit (L-23)"
  [ ! -e "${AIROOTFS}/etc/systemd/system/aios-work-runtime-bots.service" ] \
    || die "aios-work-runtime-bots.service must not be a system unit (L-23)"
  [ ! -e "${AIROOTFS}/usr/lib/systemd/user/default.target.wants/aios-work-runtime.service" ] \
    || die "work-runtime user unit must stay disabled on the payload (HI-15)"
  [ ! -e "${AIROOTFS}/usr/lib/systemd/user/default.target.wants/aios-work-runtime-bots.service" ] \
    || die "bots user unit must stay disabled on the payload (HI-15)"
}

p814_drive_installer() {
  _key=${1:-commands}
  mkdir -p "${P814_BOOT}" "${P814_DEST}/run/aios" "${P814_DEST}/etc/aios"
  : > "${P814_DEST}/run/aios/bots-request"
  _cmds="${P814_TMP}/cmds.$$"
  p814_json_list "${FIXTURE}" "${_key}" > "${_cmds}"
  P814_INSTALL_OUT=$(
    AIOS_BOOTSTRAP="${P814_BOOT}" AIOS_ROOT="${P814_DEST}" \
      AIOS_HI="${HI}" python3 -u "${MAIN}" < "${_cmds}"
  ) || true
  if printf '%s\n' "${P814_INSTALL_OUT}" | grep -q Traceback; then
    die "${SURFACE} installer traceback: ${P814_INSTALL_OUT}"
  fi
  [ -f "${P814_BOOT}/answers.json" ] \
    || die "${SURFACE} missing answers.json"
}

p814_drive_tui() {
  _mode=$1
  _key=$2
  _cmds="${P814_TMP}/tui-cmds.$$"
  if ! python3 - "${FIXTURE}" "${_key}" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
sys.exit(0 if isinstance(data.get(key), list) and data.get(key) else 1)
PY
  then
    return 0
  fi
  p814_json_list "${FIXTURE}" "${_key}" > "${_cmds}"
  P814_TUI_OUT=$(
    AIOS_ANSWERS="${P814_BOOT}/answers.json" \
      AIOS_BRAKE="${P814_BRAKE}" \
      AIOS_ROOT="${P814_DEST}" \
      AIOS_PROVIDER=fixture \
      python3 -u "${TUI}" "${_mode}" < "${_cmds}"
  ) || true
  if printf '%s\n' "${P814_TUI_OUT}" | grep -q Traceback; then
    die "${SURFACE} ${_mode} tui traceback: ${P814_TUI_OUT}"
  fi
}

p814_wrap_host() {
  _script=$1
  if [ -x "${_script}" ]; then
    "${_script}" || die "host oracle failed: ${_script}"
  elif [ -f "${_script}" ]; then
    die "${_script} exists but is not executable"
  fi
}

p814_wrap_p8() {
  _name=$1
  _script="${P814_ROOT}/tests/oracles/p8-${_name}.sh"
  if [ -x "${_script}" ]; then
    "${_script}" || die "p8-${_name}.sh failed"
  elif [ -f "${_script}" ]; then
    die "p8-${_name}.sh exists but is not executable"
  fi
}

p814_wrap_p8_required() {
  _name=$1
  _script="${P814_ROOT}/tests/oracles/p8-${_name}.sh"
  [ -x "${_script}" ] || die "missing ${_script} (P8.14 incomplete)"
  "${_script}" || die "p8-${_name}.sh failed"
}

p814_answers_python() {
  python3 - "${P814_BOOT}/answers.json" "$@" || die "${SURFACE} answers.json"
}

p814_maybe_qemu() {
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    [ -x "${RUN}" ] || die "missing ${RUN}"
    exec "${RUN}" "${SURFACE}"
  fi
}

p814_finish() {
  p814_assert_isolation
  p814_maybe_qemu
  printf 'ok: vm-%s (host). Full ISO boot not claimed.\n' "${SURFACE}"
}
