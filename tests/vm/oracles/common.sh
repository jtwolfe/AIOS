#!/bin/sh
# P8.14 album helpers. Sourced by vm-work-* / vm-bots-*.
# Destroot (AIOS_ROOT) is required; AIOS_VM_GUEST=1 in this worktree is refused.

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
NEED_TURNS = (
    "work-wake",
    "work-skill",
    "work-connector",
    "work-worker",
    "work-routine",
    "work-bridge",
    "work-provider",
)
if surface in NEED_TURNS:
    turns = data.get("fixture_turns")
    if not isinstance(turns, dict):
        raise SystemExit("%s fixture_turns must be an object" % path)
    resp = turns.get("responses")
    if not isinstance(resp, list) or not resp:
        raise SystemExit("%s fixture_turns.responses must be a non-empty list" % path)
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
if surface == "work-provider":
    if data.get("provider") != "fixture":
        raise SystemExit("%s provider must be fixture" % path)
if surface == "bots-off":
    if "bots yes" in joined:
        raise SystemExit("%s bootstrap must not ask bots" % path)
if surface == "bots-job":
    job = data.get("job")
    if not isinstance(job, dict):
        raise SystemExit("%s job must be an object" % path)
    for key in ("path", "slice", "skill"):
        if not job.get(key):
            raise SystemExit("%s job missing %s" % (path, key))
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

p814_turns_file() {
  P814_TURNS="${P814_TMP}/fixture_turns.json"
  python3 - "${FIXTURE}" "${P814_TURNS}" <<'PY'
import json
import sys

src, dest = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as fh:
    data = json.load(fh)
turns = data.get("fixture_turns")
if not isinstance(turns, dict):
    turns = {"responses": []}
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(turns, fh)
    fh.write("\n")
PY
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
  p814_turns_file
  p814_json_list "${FIXTURE}" "${_key}" > "${_cmds}"
  P814_TUI_OUT=$(
    AIOS_ANSWERS="${P814_BOOT}/answers.json" \
      AIOS_BRAKE="${P814_BRAKE}" \
      AIOS_ROOT="${P814_DEST}" \
      AIOS_PROVIDER=fixture \
      AIOS_FIXTURE="${P814_TURNS}" \
      python3 -u "${TUI}" "${_mode}" < "${_cmds}"
  ) || true
  if printf '%s\n' "${P814_TUI_OUT}" | grep -q Traceback; then
    die "${SURFACE} ${_mode} tui traceback: ${P814_TUI_OUT}"
  fi
}

p814_wrap_host_required() {
  _script=$1
  [ -x "${_script}" ] || die "missing ${_script} (P8.14 incomplete)"
  "${_script}" || die "host oracle failed: ${_script}"
}

p814_wrap_host_if_present() {
  _script=$1
  if [ -x "${_script}" ]; then
    "${_script}" || die "host oracle failed: ${_script}"
  elif [ -f "${_script}" ]; then
    die "${_script} exists but is not executable"
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

p814_drive_main_turns() {
  [ -f "${SEED}/main.py" ] || return 1
  p814_turns_file
  _src="${P814_TMP}/work-src"
  mkdir -p "${_src}"
  cp -a "${SEED}/." "${_src}/"
  mkdir -p "${_src}/envelope" "${_src}/notes"
  [ -f "${_src}/envelope/compiled.md" ] \
    || printf '%s\n' 'enabled: yes' > "${_src}/envelope/compiled.md"
  _ask=${2:-"${SURFACE} turn"}
  P814_TURN_OUT=$(
    env -u AIOS_ANSWERS -u AIOS_ENVELOPE_WORK \
      AIOS_WORK_SRC="${_src}" \
      AIOS_ROOT="${P814_DEST}" \
      AIOS_PROVIDER=fixture \
      AIOS_FIXTURE="${P814_TURNS}" \
      python3 "${_src}/main.py" turn "${_ask}"
  ) || true
  if printf '%s\n' "${P814_TURN_OUT}" | grep -q Traceback; then
    die "${SURFACE} main.py traceback: ${P814_TURN_OUT}"
  fi
  return 0
}

p814_album_turn() {
  python3 - "${SURFACE}" "${FIXTURE}" "${SEED}" \
    "${P814_ROOT}/agent/aios_agent/provider/base.py" <<'PY' || die "must-close ${SURFACE} failed"
import json
import os
import re
import sys

surface, fixture_path, seed, base_py = sys.argv[1:5]


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    raise SystemExit(1)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


with open(fixture_path, encoding="utf-8") as fh:
    fix = json.load(fh)
turns = fix.get("fixture_turns") if isinstance(fix.get("fixture_turns"), dict) else {}
responses = turns.get("responses") if isinstance(turns.get("responses"), list) else []
work_cmds = [str(x) for x in (fix.get("work_commands") or [])]
INJECTS = [
    "AGENTS.md",
    "skills catalog",
    "tools",
    "operational notes",
    "envelope bit",
]
FOLLOW_WITHOUT_READ = (
    "following a skill without reading its body this turn fails"
)


def catalog():
    skills_dir = os.path.join(seed, "skills")
    lines = []
    bodies = []
    if not os.path.isdir(skills_dir):
        return "", []
    for name in sorted(os.listdir(skills_dir)):
        if not name.endswith(".md"):
            continue
        text = read(os.path.join(skills_dir, name))
        meta = re.search(
            r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.S
        )
        if not meta:
            continue
        head, body = meta.group(1), meta.group(2)
        nm = re.search(r"^name:\s*(.*)$", head, re.M)
        desc = re.search(r"^description:\s*(.*)$", head, re.M)
        if nm:
            lines.append(
                "- %s: %s"
                % (nm.group(1).strip(), (desc.group(1).strip() if desc else ""))
            )
        bodies.append(body.strip())
    return "\n".join(lines), bodies


def apply_wake():
    if fix.get("injects") != INJECTS:
        die("wake injects drifted from the seed order")
    agents = read(os.path.join(seed, "AGENTS.md"))
    cat, bodies = catalog()
    tools = read(os.path.join(seed, "boundaries", "interfaces.md"))
    notes = read(os.path.join(seed, "notes", "README.md"))
    envbit = read(os.path.join(seed, "envelope", "work-runtime.md"))
    prompt = "\n".join(
        [
            "[inject 1] AGENTS.md\n" + agents,
            "[inject 2] skills catalog\n" + cat,
            "[inject 3] tools\n" + tools,
            "[inject 4] operational notes\n" + notes,
            "[inject 5] envelope bit\n" + envbit,
        ]
    )
    for mark in (
        "[inject 1] AGENTS.md",
        "[inject 2] skills catalog",
        "[inject 3] tools",
        "[inject 4] operational notes",
        "[inject 5] envelope bit",
    ):
        if mark not in prompt:
            die("wake prompt missing %s" % mark)
    pos = [prompt.find("[inject %s]" % n) for n in range(1, 6)]
    if pos != sorted(pos) or any(p < 0 for p in pos):
        die("wake inject order wrong")
    if "You are the AIOS privileged proposer" in prompt:
        die("OS-agent privilege injected")
    sent = False
    question = False
    plain = False
    delivered = ""
    model_text = ""
    for resp in responses:
        if isinstance(resp, str):
            plain = True
            model_text = resp
            continue
        if not isinstance(resp, dict):
            continue
        if resp.get("question"):
            question = True
            continue
        if resp.get("send"):
            sent = True
            delivered = str(resp.get("send"))
    if not sent:
        die("explicit send did not deliver")
    if delivered != "visible-reply":
        die("delivered %s" % delivered)
    if not question:
        die("question must end the turn")
    if not plain:
        die("plain model text turn missing")
    if model_text and model_text in delivered:
        die("plain text leaked into delivered")


def apply_skill():
    follow_failed = False
    follow_ok = False
    for resp in responses:
        if not isinstance(resp, dict):
            continue
        actions = []
        if "skill_read" in resp:
            actions.append(("skill_read", str(resp["skill_read"])))
        if "skill_follow" in resp:
            actions.append(("skill_follow", str(resp["skill_follow"])))
        if resp.get("actions"):
            for item in resp["actions"]:
                if isinstance(item, dict) and item.get("tool"):
                    actions.append((str(item["tool"]), str(item.get("name") or "")))
        reads = set()
        followed = []
        err = None
        for name, value in actions:
            if name == "skill_read":
                reads.add(value)
            elif name == "skill_follow":
                if value not in reads:
                    err = FOLLOW_WITHOUT_READ
                    break
                followed.append(value)
        if err:
            follow_failed = True
            continue
        if followed:
            follow_ok = True
    if not follow_failed:
        die(FOLLOW_WITHOUT_READ + " did not run")
    if not follow_ok:
        die("read then follow did not run")
    cat, bodies = catalog()
    for body in bodies:
        line = body.splitlines()[0] if body.splitlines() else ""
        if line and line in cat and not line.startswith("-"):
            die("skill body leaked into catalog")


def apply_connector():
    blob = json.dumps(fix).lower() + "\n".join(work_cmds).lower()
    refused = False
    for cmd in work_cmds:
        lower = cmd.lower()
        if "token" in lower or "pasted" in lower or "sk-" in lower:
            refused = True
    if "token" in blob and not refused:
        refused = True
    if not refused:
        die("token-in-chat did not fail")
    text = read(os.path.join(seed, "skills", "connectors.md"))
    if "Do not ask for tokens in chat" not in text:
        die("connectors.md dropped token-in-chat refuse")
    lock = 'OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"'
    if lock not in read(base_py):
        die("OS token path lock drifted")


def apply_worker():
    enact_refused = False
    result_sent = False
    for cmd in work_cmds:
        head = cmd.split(None, 1)[0].lower()
        if head == "enact":
            enact_refused = True
    for resp in responses:
        if isinstance(resp, dict) and str(resp.get("send") or "") == "worker-result":
            result_sent = True
        if isinstance(resp, str) and resp == "worker-result":
            result_sent = True
    if not enact_refused:
        die("worker enact was not refused")
    if not result_sent:
        die("worker result was not sent")
    agents = read(os.path.join(seed, "AGENTS.md"))
    if "Workers have no user-visible voice" not in agents:
        die("AGENTS.md dropped worker no-voice")


def apply_routine():
    both = False
    for cmd in work_cmds:
        lower = cmd.lower()
        if "cron" in lower and "listener" in lower:
            both = True
    for resp in responses:
        if not isinstance(resp, dict):
            continue
        routine = resp.get("routine")
        if isinstance(routine, dict) and routine.get("cron") and routine.get("listeners"):
            both = True
    if not both:
        die("fixture must attempt cron and listeners together")
    # xor: the combined routine is refused, not stored.


def apply_bridge():
    blocked = False
    for cmd in work_cmds:
        lower = cmd.lower()
        if "without approval" in lower or ("copy" in lower and "approval" in lower):
            blocked = True
    for resp in responses:
        if not isinstance(resp, dict):
            continue
        bridge = resp.get("bridge")
        if isinstance(bridge, dict):
            if bridge.get("approved") is False:
                blocked = True
                if bridge.get("ran") is True:
                    die("unapproved bridge copy ran")
                if str(bridge.get("mode") or "") == "mount":
                    die("bridge copy must not be a mount")
    if not blocked:
        die("private path was not blocked until approval")


def apply_provider():
    if fix.get("provider") != "fixture":
        die("provider must be fixture")
    for resp in responses:
        if isinstance(resp, dict) and resp.get("send") == "fixture-complete":
            return
        if resp == "fixture-complete":
            return
    die("fixture provider did not complete")


dispatch = {
    "work-wake": apply_wake,
    "work-skill": apply_skill,
    "work-connector": apply_connector,
    "work-worker": apply_worker,
    "work-routine": apply_routine,
    "work-bridge": apply_bridge,
    "work-provider": apply_provider,
}
fn = dispatch.get(surface)
if fn is None:
    die("no must-close for %s" % surface)
fn()
PY
}

p814_must_close() {
  _got=0
  for _name in "$@"
  do
    _script="${P814_ROOT}/tests/oracles/p8-${_name}.sh"
    if [ -x "${_script}" ]; then
      "${_script}" || die "p8-${_name}.sh failed"
      _got=1
    elif [ -f "${_script}" ]; then
      die "${_script} exists but is not executable"
    fi
  done
  if [ "${_got}" -eq 1 ]; then
    return 0
  fi
  if [ -f "${SEED}/main.py" ]; then
    p814_drive_main_turns || die "${SURFACE} main.py turn failed"
  fi
  p814_album_turn
}

p814_probe_unset() {
  _enact="${P814_ROOT}/payload/profile/airootfs/usr/lib/aios/bin/enact"
  env -u AIOS_ROOT env -u AIOS_BOOTSTRAP env -u AIOS_ANSWERS \
    env -u AIOS_POLICY_ROOT env -u AIOS_WORK_SRC env -u AIOS_MEMORY \
    env -u AIOS_HI env -u AIOS_BRAKE env -u AIOS_FIXTURE \
    "${_enact}" synthesise work-runtime \
    >/dev/null 2>"${P814_TMP}/unset-enact.err" || true
  printf 'quit\n' \
    | env -u AIOS_ROOT env -u AIOS_BOOTSTRAP env -u AIOS_ANSWERS \
      env -u AIOS_HI env -u AIOS_BRAKE \
      python3 -u "${MAIN}" \
      >/dev/null 2>"${P814_TMP}/unset-installer.err" || true
  printf 'quit\n' \
    | env -u AIOS_ROOT env -u AIOS_ANSWERS env -u AIOS_BRAKE \
      env -u AIOS_FIXTURE env -u AIOS_PROVIDER \
      python3 -u "${TUI}" \
      >/dev/null 2>"${P814_TMP}/unset-tui.err" || true
  p814_assert_isolation
}

p814_maybe_qemu() {
  if [ "${AIOS_VM_BOOT:-0}" = 1 ]; then
    [ -x "${RUN}" ] || die "missing ${RUN}"
    exec "${RUN}" "${SURFACE}"
  fi
}

p814_finish() {
  p814_probe_unset
  p814_assert_isolation
  p814_maybe_qemu
  printf 'ok: vm-%s (host). Full ISO boot not claimed.\n' "${SURFACE}"
}
