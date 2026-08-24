#!/usr/bin/python3
"""OS operator client (P7.1, P7.2, P7.3, P7.4, P7.5, P7.6, P7.7, P8.15, L-18, L-14, L-12, L-17, L-19). Unprivileged. One binary."""

import io
import json
import os
import signal
import subprocess
import sys
import time

import notify

# L-18 OS catalog. brake is a chrome action, not a view id (L-12).
VIEWS = (
    "chrome",
    "conversation",
    "envelope",
    "intents",
    "notify",
    "snapper",
    "packages",
    "login",
)

INSTALLER_VIEWS = ("questions", "accept", "recovery")
# L-18 work catalog. Fail closed until an explicit yes (HI-15).
WORK_VIEWS = (
    "skills",
    "connectors",
    "bridge",
    "store",
    "roster",
    "job",
)
BOTS_VIEWS = ("roster", "job")
# Work session catalog: chrome + conversation + work views + login, not OS tools (L-14).
WORK_CATALOG = (
    "chrome",
    "conversation",
    "skills",
    "connectors",
    "bridge",
    "store",
    "login",
)
STUB_VIEWS = ()
_WORK_INSPECT = ("skills", "connectors", "bridge", "store")

MODE = "os"
BRAKE_PATH = "/srv/aios/state/brake.d/stamp"
ACCEPT_STAMP = "/etc/aios/envelope-accepted"
ANSWERS_PATH = "/srv/aios/state/bootstrap-in-progress/answers.json"
PACKAGES_PATH = "/srv/aios/state/packages.txt"
INTENTS_DIR = "/srv/aios/state/intents"
ESP_MAP = "/srv/aios/state/esp-generations"
LOGIN_REQUEST = "/run/aios/login-request"
LOGIN_STATUS = "/run/aios/login-status"
ROLLBACK_REQUEST = "/run/aios/rollback-request"
ROLLBACK_STATUS = "/run/aios/rollback-status"
OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"
WORK_REFUSED = (
    "refused: work (HI-15); work runtime is off until bootstrap "
    "records an explicit yes"
)
BOTS_REFUSED = (
    "refused: bots (HI-15); second bit is off until the OS envelope "
    "view records an explicit yes after work-runtime is already yes"
)
_WORK_PRIVILEGED = ("enact", "accept", "reject", "rollback")
BOTS_REQUEST = "/run/aios/bots-request"
ENVELOPE_WORK = "/srv/aios/envelope/work-runtime.md"
ENVELOPE_BOTS = "/srv/aios/envelope/work-runtime-bots.md"
BOTS_SRC = "/srv/aios/src/work-runtime-bots"
_BOTS_ENABLED = re.compile(r"^\s*enabled\s*[:=]\s*(true|yes|1)\s*$")
_BOTS_DISABLED = re.compile(r"^\s*enabled\s*[:=]\s*(false|no|0)\s*$")
_WORK_PRIVILEGED = ("enact", "accept", "reject", "rollback")

ACTIONS = {
    "chrome": ("view", "brake", "send", "mode"),
    "conversation": ("send", "attach", "view", "brake", "mode"),
    "envelope": ("inspect", "view", "brake", "bots"),
    "roster": ("open", "view", "mode"),
    "job": ("send", "stop", "view", "mode"),
    "intents": ("open", "inspect", "view", "brake"),
    "notify": ("open", "view", "brake", "mode"),
    "snapper": ("inspect", "rollback", "view", "brake"),
    "packages": ("inspect", "view", "brake"),
    "login": ("start", "cancel", "poll", "view", "brake"),
    "skills": ("open", "follow", "inspect", "view", "brake", "mode"),
    "connectors": ("connect", "disconnect", "inspect", "view", "brake", "mode"),
    "bridge": ("approve", "deny", "inspect", "view", "brake", "mode"),
    "store": ("inspect", "view", "brake", "mode"),
}

_WORK_SHORT = {
    "h": "chrome",
    "c": "conversation",
    "s": "skills",
    "n": "connectors",
    "g": "bridge",
    "t": "store",
    "l": "login",
}

_SHORT_VIEW = {
    "h": "chrome",
    "c": "conversation",
    "e": "envelope",
    "i": "intents",
    "n": "notify",
    "s": "snapper",
    "p": "packages",
    "l": "login",
}

_INSPECT_VIEWS = ("envelope", "intents", "snapper", "packages")


def _line(out, text=""):
    out.write("%s\n" % text)
    out.flush()


def _root():
    env = os.environ.get("AIOS_ROOT")
    if env is None:
        return ""
    env = env.strip()
    if not env:
        raise OSError("AIOS_ROOT empty")
    return os.path.abspath(env)


def _path(env_name, default):
    env = os.environ.get(env_name)
    if env:
        return env
    root = _root()
    if root:
        return root + default
    return default


def _brake_path():
    return os.environ.get("AIOS_BRAKE") or BRAKE_PATH


def _brake_on():
    return os.path.isfile(_brake_path())


def write_brake():
    path = _brake_path()
    parent = os.path.dirname(path)
    if parent:
        if os.environ.get("AIOS_BRAKE"):
            os.makedirs(parent, exist_ok=True)
        elif not os.path.isdir(parent):
            raise OSError("brake drop missing (L-12)")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("braked\n")
    if not os.path.isfile(path):
        raise OSError("missing %s" % path)
    return path


def _fresh_stdin(current):
    # L-09: TextIOWrapper latches EOF after Ctrl+D; a new wrapper on the
    # same tty keeps readline blocking. Do not sleep the console away.
    opened = None
    try:
        fd = current.fileno()
    except (AttributeError, OSError, ValueError):
        fd = None
    if fd is not None:
        try:
            opened = open(
                os.dup(fd),
                "r",
                encoding="utf-8",
                errors="replace",
                closefd=True,
            )
        except OSError:
            opened = None
    if opened is None:
        for path in ("/dev/tty", "/dev/console"):
            try:
                opened = open(path, "r", encoding="utf-8", errors="replace")
                break
            except OSError:
                continue
    if opened is None:
        return current
    if current is not opened and current is not sys.stdin:
        try:
            current.close()
        except OSError:
            pass
    return opened


def _add_sys_path(path):
    if path and os.path.isdir(path) and path not in sys.path:
        sys.path.insert(0, path)


def _here():
    return os.path.dirname(os.path.abspath(__file__))


def _agent_dir():
    env = os.environ.get("AIOS_AGENT")
    if env:
        return env
    candidates = (
        os.path.normpath(os.path.join(_here(), "..", "..", "agent", "aios_agent")),
        "/usr/lib/aios/agent/aios_agent",
        "/srv/aios/agent/aios_agent",
    )
    for path in candidates:
        if os.path.isfile(os.path.join(path, "provider", "live.py")):
            return path
    return candidates[0]


def _installer_dir():
    env = os.environ.get("AIOS_INSTALLER")
    if env:
        return env
    candidates = (
        os.path.normpath(
            os.path.join(_here(), "..", "..", "installer", "aios_installer")
        ),
        "/usr/lib/aios/installer/aios_installer",
    )
    for path in candidates:
        if os.path.isfile(os.path.join(path, "compiler.py")):
            return path
    return candidates[0]


def _write_login_request(path, text):
    # Operator is not the owner (aios-agent is). Write only; chmod(2)
    # is owner-only. Missing file stays rendezvous-missing (L-17).
    payload = text if text.endswith("\n") else "%s\n" % text
    fd = os.open(path, os.O_WRONLY | os.O_TRUNC)
    try:
        data = payload.encode("utf-8")
        while data:
            n = os.write(fd, data)
            data = data[n:]
        os.fsync(fd)
    finally:
        os.close(fd)


def _clickable(out, url):
    try:
        tty = out.isatty()
    except Exception:
        tty = False
    if tty:
        return "\033]8;;%s\033\\%s\033]8;;\033\\" % (url, url)
    return url


def _read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _answers_path():
    env = os.environ.get("AIOS_ANSWERS")
    if env:
        return env
    boot = os.environ.get("AIOS_BOOTSTRAP")
    if boot:
        return os.path.join(boot, "answers.json")
    return _path("AIOS_ANSWERS", ANSWERS_PATH)


def _clause_enabled(path):
    if not path or not os.path.isfile(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, sep, val = stripped.partition("=")
        if not sep:
            key, sep, val = stripped.partition(":")
        if not sep:
            continue
        if key.strip().lower() == "enabled" and val.strip().lower() in (
            "true",
            "yes",
            "1",
        ):
            return True
    return False


def work_runtime_on():
    path = _answers_path()
    if path and os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            doc = None
        if isinstance(doc, dict) and doc.get("work_runtime") is True:
            return True
    return _clause_enabled(os.environ.get("AIOS_ENVELOPE_WORK"))


def _bots_clause_path():
    return _path("AIOS_ENVELOPE_BOTS", ENVELOPE_BOTS)


def _bots_request_path():
    return _path("AIOS_BOTS_REQUEST", BOTS_REQUEST)


def _bots_src_path():
    return os.environ.get("AIOS_BOTS_SRC") or _path("AIOS_BOTS_SRC", BOTS_SRC)


def bots_on():
    if not work_runtime_on():
        return False
    path = _bots_clause_path()
    if not path or not os.path.isfile(path):
        return False
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if _BOTS_DISABLED.match(stripped):
            return False
        if _BOTS_ENABLED.match(stripped):
            return True
    return False


def _load_answers_doc():
    path = _answers_path()
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError, TypeError):
        return {}
    if not isinstance(data, dict):
        return {}
    nested = data.get("answers")
    if isinstance(nested, dict):
        return nested
    return data


def _envelope_text():
    data = _load_answers_doc()
    try:
        _add_sys_path(_installer_dir())
        import compiler
    except Exception:
        compiler = None
    if compiler is not None:
        try:
            answers = compiler.from_mapping(data)
            return compiler.draft(answers)
        except Exception as exc:
            return "error: envelope inspect failed: %s\n" % exc
    lines = ["derived:"]
    if data:
        lines.append("  %s" % json.dumps(data, sort_keys=True))
    else:
        lines.append("  (no answers)")
    hi = os.environ.get("AIOS_HI") or ""
    if not hi:
        for cand in (
            _path("AIOS_HI", "/srv/aios/envelope/hard-invariants.md"),
            "/usr/lib/aios/envelope/hard-invariants.md",
            os.path.normpath(
                os.path.join(
                    _here(), "..", "..", "docs", "envelope", "hard-invariants.md"
                )
            ),
        ):
            if cand and os.path.isfile(cand):
                hi = cand
                break
    lines.append("canonical-hard-invariants:")
    if hi and os.path.isfile(hi):
        body = _read_text(hi).replace("\r\n", "\n").replace("\r", "\n")
        if body.endswith("\n"):
            body = body[:-1]
        return "\n".join(lines) + "\n" + body + "\n"
    return "\n".join(lines) + "\n(hi-file missing)\n"


def _packages_pin():
    return _path("AIOS_PACKAGES", PACKAGES_PATH)


def _live_packages():
    env = os.environ.get("AIOS_LIVE_PACKAGES")
    if env:
        if not os.path.isfile(env):
            return None
        return _read_text(env)
    try:
        proc = subprocess.run(
            ["pacman", "-Qqe"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    out = proc.stdout.decode("utf-8", "replace")
    return out


def _intents_dir():
    return os.environ.get("AIOS_INTENTS") or _path("AIOS_INTENTS", INTENTS_DIR)


def _intent_files():
    path = _intents_dir()
    if not os.path.isdir(path):
        return []
    names = []
    try:
        listing = os.listdir(path)
    except OSError:
        return []
    for name in sorted(listing):
        if name.startswith("."):
            continue
        full = os.path.join(path, name)
        if os.path.isfile(full):
            names.append(name)
    return names


def _intent_path(ident):
    ident = (ident or "").strip()
    if not ident or "/" in ident or ident in (".", ".."):
        return None
    directory = _intents_dir()
    direct = os.path.join(directory, ident)
    if os.path.isfile(direct):
        return direct
    if not ident.endswith(".json"):
        alt = os.path.join(directory, ident + ".json")
        if os.path.isfile(alt):
            return alt
    return None


def _snapper_text():
    env = os.environ.get("AIOS_SNAPPER_LIST")
    if env:
        if os.path.isfile(env):
            return _read_text(env)
        return env
    try:
        proc = subprocess.run(
            ["snapper", "--no-dbus", "-c", "root", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
        if proc.returncode == 0:
            text = proc.stdout.decode("utf-8", "replace")
            if text.strip():
                return text
    except (OSError, subprocess.TimeoutExpired):
        pass
    mapped = _path("AIOS_ESP_GENERATIONS", ESP_MAP)
    if os.path.isfile(mapped):
        return _read_text(mapped)
    return ""


def _esp_map_path():
    return _path("AIOS_ESP_GENERATIONS", ESP_MAP)


def _esp_generations():
    path = _esp_map_path()
    if not os.path.isfile(path):
        return []
    try:
        text = _read_text(path)
    except OSError:
        return []
    rows = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        if not parts:
            continue
        ident = parts[0]
        if ident.isdigit() and int(ident) > 0:
            rows.append(ident)
    return rows


def _previous_post():
    rows = _esp_generations()
    if len(rows) < 2:
        return None
    return rows[-2]


def _parse_rollback_n(arg):
    token = (arg or "").strip()
    if token.lower().startswith("rollback "):
        token = token.split(None, 1)[1].strip()
    if not token:
        return _previous_post()
    if token.startswith("-") or not token.isdigit() or int(token) <= 0:
        return None
    return token


def _work_src():
    env = os.environ.get("AIOS_WORK_SRC")
    if env:
        return env
    return _path("AIOS_WORK_SRC", "/srv/aios/src/work-runtime")


def _skills_dir():
    env = os.environ.get("AIOS_SKILLS")
    if env:
        return env
    return os.path.join(_work_src(), "skills")


def _connectors_dir():
    env = os.environ.get("AIOS_CONNECTORS")
    if env:
        return env
    return os.path.join(_work_src(), "connectors")


def _bridge_dir():
    env = os.environ.get("AIOS_BRIDGE")
    if env:
        return env
    return os.path.join(_work_src(), "bridge")


def _list_named_files(directory):
    if not directory or not os.path.isdir(directory):
        return []
    try:
        listing = os.listdir(directory)
    except OSError:
        return []
    names = []
    for name in sorted(listing):
        if name.startswith("."):
            continue
        full = os.path.join(directory, name)
        if os.path.isfile(full):
            names.append(name)
    return names


def _skill_record(path):
    name = os.path.splitext(os.path.basename(path))[0]
    desc = ""
    body = ""
    try:
        text = _read_text(path)
    except OSError:
        return name, desc, body
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            for line in parts[1].splitlines():
                stripped = line.strip()
                if stripped.startswith("name:"):
                    value = stripped.split(":", 1)[1].strip()
                    if value:
                        name = value
                elif stripped.startswith("description:"):
                    desc = stripped.split(":", 1)[1].strip()
            body = parts[2]
            if body.startswith("\n"):
                body = body[1:]
            if body.endswith("\n"):
                body = body[:-1]
            return name, desc, body
    if text.endswith("\n"):
        text = text[:-1]
    return name, desc, text


def _list_skills():
    directory = _skills_dir()
    rows = []
    for name in _list_named_files(directory):
        if not name.endswith(".md"):
            continue
        path = os.path.join(directory, name)
        rows.append(_skill_record(path))
    rows.sort(key=lambda row: row[0].lower())
    return rows


def _find_skill(ident):
    ident = (ident or "").strip().lower()
    if not ident:
        return None
    for name, desc, body in _list_skills():
        if name.lower() == ident:
            return name, desc, body
    return None


def _list_connectors():
    names = []
    for name in _list_named_files(_connectors_dir()):
        base = os.path.splitext(name)[0]
        names.append(base or name)
    return names


def _list_bridge_pending():
    return _list_named_files(_bridge_dir())


def _store_entries():
    src = _work_src()
    rows = []
    for kind in ("notes", "routines", "connectors"):
        directory = os.path.join(src, kind)
        files = _list_named_files(directory)
        if not files:
            rows.append("%s: (empty)" % kind)
            continue
        for name in files:
            rows.append("%s: %s" % (kind, name))
    return rows


class Session:
    def __init__(self, mode=None):
        want = (mode or MODE).strip().lower()
        if want == "work" and work_runtime_on():
            self.mode = "work"
        else:
            self.mode = MODE
        self.view = "chrome"
        self.transcript = []
        self.braked = _brake_on()
        self.writes_frozen = self.braked
        self.note_text = ""
        self.piped = False
        self.login_status = "idle"
        self.login_uri = ""
        self.login_user_code = ""
        self.login_complete = ""
        self._device_code = ""
        self._login_provider = None
        self._secrets = []
        self.rollback_state = ""
        self.rollback_n = ""
        self.rollback_error = ""
        self.rollback_entry = ""
        self.skill_sel = ""
        self._skills_read = set()
        self.connector_sel = ""
        self.bridge_sel = ""

    def catalog(self):
        if self.mode == "work":
            return WORK_CATALOG
        return VIEWS

    def shorts(self):
        if self.mode == "work":
            return _WORK_SHORT
        return _SHORT_VIEW

    def actions(self):
        return ACTIONS.get(self.view, ("view", "brake", "mode"))

    def _emit(self, out, text=""):
        for secret in self._secrets:
            if secret:
                text = text.replace(secret, "(redacted)")
        _line(out, text)

    def render(self, out):
        if self.view == "login":
            if self._login_provider is not None and self.login_status == "waiting":
                self._login_tick_inject()
            elif self._login_provider is None:
                self._login_tick_rendezvous()
        elif self.view == "snapper":
            self._rollback_load()
        self._emit(out, "-- AIOS --")
        self._emit(out, "mode: %s" % self.mode)
        self._emit(out, "view: %s" % self.view)
        self._emit(out, "actions: %s" % " ".join(self.actions()))
        self._emit(out, "catalog: %s" % " ".join(self.catalog()))
        self._emit(out, "brake: %s" % ("on" if self.braked else "off"))
        self._emit(
            out,
            "writes: %s" % ("frozen" if self.writes_frozen else "live"),
        )
        if self.note_text:
            self._emit(out, "note: %s" % self.note_text)
        body = {
            "chrome": self._chrome,
            "conversation": self._conversation,
            "envelope": self._envelope,
            "intents": self._intents,
            "notify": self._notify,
            "snapper": self._snapper,
            "packages": self._packages,
            "login": self._login,
            "skills": self._skills,
            "connectors": self._connectors,
            "bridge": self._bridge,
            "store": self._store,
        }.get(self.view)
        if body is None:
            self._stub(out)
        else:
            body(out)
        self._emit(out, "--")

    def _notify(self, out):
        for line in notify.render_lines(notify.load_payloads()):
            self._emit(out, line)

    def _chrome(self, out):
        self._emit(out, "surface: %s" % self.mode)
        if self.mode == "work":
            self._emit(out, "switch: os allowed (session); installer refused (not firstboot)")
            self._emit(out, "brake: human-only; freeze privileged writes; TUI stays (L-12)")
            self._emit(out, "send: conversation line")
            self._emit(out, "work-views: %s" % " ".join(WORK_CATALOG))
            self._emit(out, "privileged tools: none (L-14)")
            self._work_panes(out, list(WORK_CATALOG), ["work catalog (P8.15, L-18)"])
            return
        if work_runtime_on():
            self._emit(
                out,
                "switch: work allowed (session); installer refused (not firstboot)",
            )
        else:
            self._emit(
                out,
                "switch: work refused (HI-15); installer refused (not firstboot)",
            )
        self._emit(
            out,
            "brake: human-only; freeze privileged writes; TUI stays (L-12)",
        )
        self._emit(out, "send: conversation line")
        self._emit(out, "os-views: %s" % " ".join(VIEWS))

    def _work_panes(self, out, sidebar, info):
        self._emit(out, "sidebar:")
        if not sidebar:
            self._emit(out, "  (empty)")
        else:
            for item in sidebar:
                self._emit(out, "  %s" % item)
        self._emit(out, "transcript:")
        if not self.transcript:
            self._emit(out, "  (empty)")
        else:
            for item in self.transcript[-20:]:
                self._emit(out, "  %s" % item)
        self._emit(out, "info:")
        if not info:
            self._emit(out, "  (empty)")
            return
        for line in info:
            self._emit(out, "  %s" % line)

    def _conversation(self, out):
        if self.mode == "work":
            self._emit(out, "surface: work")
            self._work_panes(
                out,
                list(WORK_CATALOG),
                ["conversation (L-18); question ends the turn"],
            )
            self._emit(out, "attach: work path (L-18)")
            return
        self._emit(out, "transcript:")
        if not self.transcript:
            self._emit(out, "  (empty)")
        else:
            for item in self.transcript[-20:]:
                self._emit(out, "  %s" % item)
        self._emit(out, "attach: not allowed in OS mode")

    def _envelope(self, out):
        stamp = _path("AIOS_ACCEPT_STAMP", ACCEPT_STAMP)
        accepted = os.path.isfile(stamp)
        self._emit(out, "envelope-inspect: compiled HI + derived (L-18)")
        self._emit(out, "envelope-accepted: %s" % ("yes" if accepted else "no"))
        self._emit(out, "bots-bit: %s" % ("yes" if bots_on() else "off"))
        for line in _envelope_text().splitlines():
            self._emit(out, line)

    def _intents(self, out):
        names = _intent_files()
        self._emit(out, "intents: pending OS work (L-18)")
        if not names:
            self._emit(out, "(empty)")
            return
        for name in names:
            self._emit(out, "  %s" % name)

    def _snapper(self, out):
        self._emit(out, "snapper-inspect: generations (L-18); rollback is L-19")
        prev = _previous_post()
        if prev:
            self._emit(
                out,
                "rollback: previous successful post %s (L-19, HI-06); not undochange"
                % prev,
            )
        else:
            self._emit(out, "rollback: select N (L-19); not undochange")
        state = self.rollback_state or "idle"
        ident = self.rollback_n or "-"
        self._emit(out, "rollback-status: %s %s" % (state, ident))
        if self.rollback_entry and state == "prepared":
            self._emit(out, "rollback-entry: %s" % self.rollback_entry)
        if state in ("prepared", "promoted", "refused"):
            self._emit(out, self._rollback_note(ident))
        text = _snapper_text()
        if not text.strip():
            self._emit(out, "(empty)")
            return
        for line in text.splitlines():
            self._emit(out, line)

    def _packages(self, out):
        pin_path = _packages_pin()
        self._emit(out, "packages-inspect: packages.txt vs live (L-18)")
        self._emit(out, "packages.txt: %s" % pin_path)
        pin = None
        if os.path.isfile(pin_path):
            try:
                pin = _read_text(pin_path)
            except OSError:
                pin = None
        if pin is None:
            self._emit(out, "pin: (unreadable)")
        else:
            for line in pin.splitlines() or ["(empty)"]:
                self._emit(out, "pin: %s" % line)
        live = _live_packages()
        if live is None:
            self._emit(out, "live: (unreadable)")
            return
        if pin is not None and pin == live:
            self._emit(out, "live: match")
            return
        self._emit(out, "live: differ")
        for line in live.splitlines() or ["(empty)"]:
            self._emit(out, "live: %s" % line)

    def _login(self, out):
        self._emit(
            out,
            "L-17: live Grok login is after envelope accept. Never a pasted API key.",
        )
        self._emit(out, "login-status: %s" % self.login_status)
        if self.login_uri:
            self._emit(out, "verification: %s" % _clickable(out, self.login_uri))
        if self.login_user_code:
            self._emit(out, "user_code: %s" % self.login_user_code)
        if self.login_complete and self.login_complete != self.login_uri:
            self._emit(
                out,
                "verification-complete: %s"
                % _clickable(out, self.login_complete),
            )
        if self.login_status == "waiting":
            self._emit(
                out,
                "waiting: finish on a phone or other PC; this box polls (L-17)",
            )
        if self.login_status == "ok":
            self._emit(out, "token: written 0600 (not in transcript)")
        if self.mode == "work":
            self._emit(out, "surface: work")

    def _skills(self, out):
        rows = _list_skills()
        sidebar = [name for name, _desc, _body in rows]
        info = ["skills-inspect: catalog (L-18); read the body this turn to follow"]
        if self.skill_sel:
            rec = _find_skill(self.skill_sel)
            if rec is not None:
                name, desc, body = rec
                info.append("selected: %s" % name)
                if desc:
                    info.append("description: %s" % desc)
                if body:
                    info.extend(body.splitlines() or [""])
        elif not rows:
            info.append("(empty)")
        self._emit(out, "surface: work")
        self._work_panes(out, sidebar, info)

    def _connectors(self, out):
        names = _list_connectors()
        info = [
            "connectors-inspect: MCP status (L-18); connect is a card, not chat",
        ]
        if self.connector_sel:
            info.append("selected: %s" % self.connector_sel)
        elif not names:
            info.append("(empty)")
        self._emit(out, "surface: work")
        self._work_panes(out, names, info)

    def _bridge(self, out):
        pending = _list_bridge_pending()
        info = [
            "bridge-inspect: private-path approval (L-18); copy is verbatim, not a mount",
        ]
        if self.bridge_sel:
            info.append("selected: %s" % self.bridge_sel)
        elif not pending:
            info.append("pending: (empty)")
        self._emit(out, "surface: work")
        self._work_panes(out, pending, info)

    def _store(self, out):
        entries = _store_entries()
        sidebar = list(entries)
        info = [
            "store-inspect: notes routines connectors as git in the work tree (L-18)",
            "not /srv/aios/memory",
        ]
        self._emit(out, "surface: work")
        self._work_panes(out, sidebar, info)

    def _stub(self, out):
        self._emit(out, "not this PR")

    def switch(self, view_id):
        view_id = (view_id or "").strip().lower()
        view_id = self.shorts().get(view_id, view_id)
        if view_id == "brake":
            self.note_text = "brake is a chrome action, not a view (L-12, L-18)"
            return
        if view_id in INSTALLER_VIEWS:
            self.note_text = "installer view refused (not firstboot)"
            return
        if view_id in BOTS_VIEWS:
            if not bots_on():
                self.note_text = BOTS_REFUSED
                return
            if self.mode != "work":
                self.note_text = "%s refused in os session (L-14)" % view_id
                return
            self.view = view_id
            self.note_text = ""
            return
        if self.mode == "work":
            if view_id in self.catalog():
                self.view = view_id
                self.note_text = ""
                return
            if view_id in VIEWS or view_id in _WORK_PRIVILEGED:
                self.note_text = "%s refused in work session (L-14)" % view_id
                return
            self.note_text = "unknown view %s (L-18)" % view_id
            return
        if view_id in WORK_VIEWS:
            if work_runtime_on():
                self.note_text = "%s refused in os session (L-14)" % view_id
            else:
                self.note_text = "work view refused (HI-15)"
            return
        if view_id not in VIEWS:
            self.note_text = "unknown view %s (L-18)" % view_id
            return
        self.view = view_id
        self.note_text = ""

    def brake(self):
        try:
            write_brake()
        except OSError as exc:
            self.braked = False
            self.writes_frozen = False
            self.note_text = "brake failed: %s (L-12)" % exc
            return
        self.braked = True
        self.writes_frozen = True
        self.note_text = "brake on (L-12); writes frozen; TUI stays"

    def _complete(self, text):
        fixture = os.environ.get("AIOS_FIXTURE")
        kind = (os.environ.get("AIOS_PROVIDER") or "").strip()
        if not fixture or kind not in ("", "fixture"):
            return None
        try:
            _add_sys_path(_agent_dir())
            from provider.fixture import FixtureProvider

            return FixtureProvider(fixture).complete(text)
        except Exception:
            return None

    def send(self, text):
        text = (text or "").strip()
        if self.view == "login":
            self.note_text = "never a pasted API key (L-17)"
            return
        if not text:
            self.note_text = "send: empty"
            return
        self.transcript.append("operator: %s" % text)
        if text.endswith("?"):
            self.note_text = "turn-ended: question"
            return
        reply = self._complete(text)
        if reply:
            self.transcript.append("agent: %s" % reply)
        self.note_text = "sent"
        if self.view == "chrome":
            self.view = "conversation"

    def attach(self):
        if self.mode == "work":
            self.note_text = "attach: work path (L-18)"
            return
        self.note_text = "attach: not allowed in OS mode"

    def inspect(self):
        if self.mode == "work" and self.view in _WORK_INSPECT:
            self.note_text = "inspect: %s" % self.view
            return
        if self.view not in _INSPECT_VIEWS and self.view != "login":
            if self.view in STUB_VIEWS:
                self.note_text = "not this PR"
                return
            self.note_text = "inspect: not this view"
            return
        self.note_text = "inspect: %s" % self.view

    def open_handoff(self):
        payloads = notify.load_payloads()
        if not payloads:
            self.note_text = "no HI-14 payload"
            return
        self.transcript.append(notify.conversation_line(payloads[0]))
        self.view = "conversation"
        self.note_text = "opened notify into conversation (HI-14)"

    def skill_open(self, ident):
        ident = (ident or "").strip()
        rows = _list_skills()
        if not rows:
            self.note_text = "open: no skills"
            return
        rec = _find_skill(ident) if ident else rows[0]
        if rec is None:
            self.note_text = "open: unknown skill %s" % ident
            return
        name, _desc, _body = rec
        self.skill_sel = name
        self._skills_read.add(name)
        self.note_text = "open: %s (read this turn)" % name

    def skill_follow(self, ident):
        ident = (ident or self.skill_sel or "").strip()
        if not ident:
            self.note_text = "follow: select a skill"
            return
        rec = _find_skill(ident)
        name = rec[0] if rec is not None else ident
        if name not in self._skills_read:
            self.note_text = "follow refused: read the skill body this turn"
            return
        self.skill_sel = name
        self.note_text = "follow: %s" % name

    def connector_connect(self, ident):
        ident = (ident or self.connector_sel or "").strip()
        if not ident:
            self.note_text = "connect: select a connector"
            return
        self.connector_sel = ident
        self.note_text = "connect: card %s (not chat)" % ident

    def connector_disconnect(self, ident):
        ident = (ident or self.connector_sel or "").strip()
        if not ident:
            self.note_text = "disconnect: select a connector"
            return
        self.note_text = "disconnect: %s" % ident

    def bridge_approve(self, ident):
        ident = (ident or self.bridge_sel or "").strip()
        pending = _list_bridge_pending()
        if not pending and not ident:
            self.note_text = "approve: none pending"
            return
        if not ident:
            ident = pending[0]
        self.bridge_sel = ident
        self.note_text = "approve: %s (not run)" % ident

    def bridge_deny(self, ident):
        ident = (ident or self.bridge_sel or "").strip()
        pending = _list_bridge_pending()
        if not pending and not ident:
            self.note_text = "deny: none pending"
            return
        if not ident:
            ident = pending[0]
        self.note_text = "deny: %s" % ident

    def open_intent(self, ident):
        ident = (ident or "").strip()
        if not ident:
            names = _intent_files()
            if not names:
                self.note_text = "open: no intents"
                return
            ident = names[0]
        path = _intent_path(ident)
        if path is None:
            self.note_text = "open: unknown intent %s" % ident
            return
        try:
            body = _read_text(path).strip()
        except OSError as exc:
            self.note_text = "open failed: %s" % exc
            return
        self.view = "conversation"
        self.send(body or ident)

    def _rollback_request_path(self):
        return _path("AIOS_ROLLBACK_REQUEST", ROLLBACK_REQUEST)

    def _rollback_status_path(self):
        return _path("AIOS_ROLLBACK_STATUS", ROLLBACK_STATUS)

    def _rollback_note(self, ident=""):
        n = self.rollback_n or ident
        state = self.rollback_state
        if state == "prepared" and n:
            return "reboot into @.restore-%s (L-19)" % n
        if state == "promoted":
            return "promoted; reboot into @ (L-19)"
        if state == "refused":
            err = self.rollback_error or n or "refused"
            return "rollback refused: %s (L-19)" % err
        if ident:
            return "rollback %s requested (L-19, HI-06); not undochange" % ident
        return "rollback: select N (L-19)"

    def _rollback_load(self):
        path = self._rollback_status_path()
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError:
            return
        if not raw.strip():
            return
        try:
            data = json.loads(raw)
        except ValueError:
            return
        if not isinstance(data, dict):
            return
        state = (data.get("state") or "").strip().lower()
        n = str(data.get("n") or "").strip()
        err = str(data.get("error") or "").strip()
        entry = str(data.get("entry") or "").strip()
        if state:
            self.rollback_state = state
        if n:
            self.rollback_n = n
        if state == "refused":
            self.rollback_error = err
        if entry:
            self.rollback_entry = entry

    def rollback(self, arg=""):
        if self.mode == "work":
            self.note_text = "rollback refused in work session (L-14)"
            return
        # Operator is unprivileged: file a request; aios-agent runs enact (L-04).
        ident = _parse_rollback_n(arg)
        if ident is None:
            self.note_text = "rollback: select N (L-19)"
            return
        rows = _esp_generations()
        if rows:
            last = rows[-1]
            if ident == last:
                self.note_text = (
                    "rollback refused: %s is the failed window post id (HI-06, L-19)"
                    % ident
                )
                return
            if ident not in rows:
                self.note_text = (
                    "rollback refused: %s is not a successful post (L-19)" % ident
                )
                return
        path = self._rollback_request_path()
        try:
            parent = os.path.dirname(path)
            if parent and not os.path.isdir(parent):
                raise OSError("rollback rendezvous missing")
            _write_login_request(path, "rollback %s" % ident)
        except OSError as exc:
            self.note_text = "rollback rendezvous missing: %s (L-19)" % exc
            return
        self.rollback_n = ident
        self.note_text = "rollback %s requested (L-19, HI-06); not undochange" % ident

    def _forget_device(self):
        if self._device_code and self._device_code not in self._secrets:
            self._secrets.append(self._device_code)
        self._device_code = ""
        self._login_provider = None

    def _inject_login(self):
        # Host oracles: temp token path and/or HTTP fixture, never the
        # production lock. The operator TUI must not write os.token (L-16).
        http = (os.environ.get("AIOS_PROVIDER_HTTP") or "").strip()
        token = (os.environ.get("AIOS_OS_TOKEN") or "").strip()
        if token == OS_TOKEN_PATH:
            return False
        return bool(http or token)

    def _login_request_path(self):
        return _path("AIOS_LOGIN_REQUEST", LOGIN_REQUEST)

    def _login_status_path(self):
        return _path("AIOS_LOGIN_STATUS", LOGIN_STATUS)

    def _apply_login_status_doc(self, data):
        if not isinstance(data, dict):
            return
        uri = data.get("verification") or ""
        if isinstance(uri, str) and uri.startswith("https://") and not any(
            c.isspace() for c in uri
        ):
            self.login_uri = uri
        code = data.get("user_code") or ""
        if isinstance(code, str) and code and not any(c.isspace() for c in code):
            self.login_user_code = code
        err = data.get("error") or ""
        state = (data.get("state") or "").strip().lower()
        if state == "waiting":
            self.login_status = "waiting"
        elif state == "ok":
            self.login_status = "ok"
            self.note_text = "login ok (L-17); token not in transcript"
        elif state == "cancelled":
            self.login_status = "cancelled"
            self.note_text = "login cancelled (L-17)"
        elif state == "refused":
            self.login_status = "refused"
            if err:
                self.note_text = str(err)

    def _login_tick_rendezvous(self):
        path = self._login_status_path()
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError:
            return
        if not raw.strip():
            return
        try:
            data = json.loads(raw)
        except ValueError:
            return
        self._apply_login_status_doc(data)

    def _login_tick_inject(self):
        if self._login_provider is None or not self._device_code:
            return
        try:
            result = self._login_provider.poll_token(self._device_code)
        except Exception as exc:
            self.login_status = "refused"
            self.note_text = "%s" % exc
            self._forget_device()
            return
        if result == "ok":
            self.login_status = "ok"
            self.note_text = "login ok (L-17); token not in transcript"
            self._forget_device()
            return
        if result == "pending":
            return
        if result == "slow_down":
            return
        self.login_status = "refused"
        self.note_text = "device-code %s (L-17)" % result
        self._forget_device()

    def _login_tick(self):
        if self.login_status != "waiting":
            return
        if self._login_provider is not None:
            self._login_tick_inject()
            return
        self._login_tick_rendezvous()

    def _login_start_rendezvous(self):
        path = self._login_request_path()
        try:
            parent = os.path.dirname(path)
            if parent and not os.path.isdir(parent):
                raise OSError("login rendezvous missing")
            _write_login_request(path, "start")
        except OSError as exc:
            self.login_status = "refused"
            self.note_text = "login rendezvous missing: %s (L-17)" % exc
            return
        self.login_status = "waiting"
        self.note_text = "login started (L-17)"
        self._login_tick()

    def _login_start_inject(self):
        try:
            _add_sys_path(_agent_dir())
            from provider.base import ProviderError
            from provider.live import LiveProvider
        except Exception as exc:
            self.login_status = "refused"
            self.note_text = "live adapter missing: %s (L-17)" % exc
            return
        err = io.StringIO()
        try:
            provider = LiveProvider()
            sess = provider.request_device(err=err)
        except ProviderError as exc:
            self.login_status = "refused"
            self.note_text = "%s" % exc
            return
        except OSError:
            self.login_status = "refused"
            self.note_text = "device-code request failed (L-17)"
            return
        self._login_provider = provider
        self.login_uri = sess.get("uri") or ""
        self.login_user_code = sess.get("user_code") or ""
        self.login_complete = sess.get("complete") or ""
        self._device_code = sess.get("device_code") or ""
        if self._device_code:
            self._secrets.append(self._device_code)
        self.login_status = "waiting"
        self.note_text = "login started (L-17)"
        self._login_tick()

    def login_start(self, arg=""):
        if arg:
            self.note_text = "never a pasted API key (L-17)"
            return
        if self.writes_frozen:
            self.note_text = "refused: writes frozen (L-12)"
            return
        if self.login_status == "waiting":
            self.note_text = "login: already waiting"
            return
        kind = (os.environ.get("AIOS_PROVIDER") or "").strip()
        if kind == "fixture":
            self.login_status = "refused"
            self.note_text = "fixture has no live login (L-17)"
            return
        if self._inject_login():
            self._login_start_inject()
            return
        self._login_start_rendezvous()

    def login_cancel(self):
        if self._login_provider is not None:
            if self.login_status != "waiting":
                self.note_text = "login: not started"
                return
            self.login_status = "cancelled"
            self._forget_device()
            self.note_text = "login cancelled (L-17)"
            return
        path = self._login_request_path()
        try:
            _write_login_request(path, "cancel")
        except OSError as exc:
            self.note_text = "login rendezvous missing: %s (L-17)" % exc
            return
        self.login_status = "cancelled"
        self.note_text = "login cancelled (L-17)"

    def login_poll(self):
        if self.login_status != "waiting":
            self.note_text = "login: not waiting"
            return
        self._login_tick()
        if self.login_status == "waiting":
            self.note_text = "login: waiting (L-17)"

    def bots_action(self, arg=""):
        if self.mode == "work":
            self.note_text = "bots refused in work session (L-14)"
            return
        if not work_runtime_on():
            self.note_text = "bots refused: work-runtime is not yes (HI-15)"
            return
        token = (arg or "").strip().lower()
        if token in ("", "status"):
            self.note_text = "bots-bit: %s" % ("yes" if bots_on() else "off")
            return
        if token in ("no", "n", "skip"):
            self.note_text = "bots: not-yes (HI-15)"
            return
        if token not in ("yes", "y"):
            self.note_text = "bots: skip is not a yes (HI-15)"
            return
        try:
            _write_login_request(_bots_request_path(), "yes")
        except OSError as exc:
            self.note_text = "bots rendezvous missing: %s" % exc
            return
        self.note_text = "bots yes requested"
    def mode_switch(self, target):
        target = (target or "").strip().lower()
        if not target or target == MODE or target == "os":
            self.mode = MODE
            if self.view not in VIEWS:
                self.view = "chrome"
            self.note_text = "mode: os"
            return
        if target == "work":
            if not work_runtime_on():
                self.note_text = "mode refused: work (HI-15); staying %s" % self.mode
                return
            self.mode = "work"
            if self.view not in self.catalog():
                self.view = "chrome"
            self.note_text = "mode: work"
            return
        if target == "installer":
            self.note_text = "mode refused: installer (not firstboot)"
            return
        self.note_text = "mode refused: %s; staying %s" % (target, self.mode)

    def handle(self, raw):
        line = (raw or "").strip()
        if not line:
            return None
        if line.startswith(":"):
            line = line[1:].strip()
        if not line:
            return None
        parts = line.split(None, 1)
        cmd = parts[0].lower()
        arg = parts[1] if len(parts) > 1 else ""

        if cmd in ("quit", "exit"):
            return "quit"

        if cmd == "help":
            self.note_text = "actions: %s" % " ".join(self.actions())
            return None

        if cmd in ("view", "v"):
            token = arg.strip().lower()
            name = self.shorts().get(token, token)
            self.switch(name)
            return None

        if cmd in VIEWS or cmd in WORK_VIEWS or cmd in self.catalog():
            self.switch(cmd)
            return None

        if cmd in self.shorts() and not arg:
            self.switch(self.shorts()[cmd])
            return None

        if cmd in _WORK_PRIVILEGED and self.mode == "work":
            self.note_text = "%s refused in work session (L-14)" % cmd
            return None

        if cmd in ("brake", "b") and not arg:
            self.brake()
            return None
        if cmd == "send":
            self.send(arg)
            return None
        if cmd == "attach":
            self.attach()
            return None
        if cmd == "mode":
            self.mode_switch(arg)
            return None
        if cmd in ("inspect", "r") and not arg:
            self.inspect()
            return None
        if cmd == "open":
            if self.mode == "work":
                if self.view == "skills":
                    self.skill_open(arg)
                else:
                    self.note_text = "open: not this view"
                return None
            if self.view == "notify":
                self.open_handoff()
                return None
            if self.view == "intents":
                self.open_intent(arg)
                return None
            self.note_text = "open is a notify action (HI-14)"
            return None
        if cmd == "follow":
            if self.mode != "work" or self.view != "skills":
                self.note_text = "follow: not this view"
                return None
            self.skill_follow(arg)
            return None
        if cmd == "connect":
            if self.mode != "work" or self.view != "connectors":
                self.note_text = "connect: not this view"
                return None
            self.connector_connect(arg)
            return None
        if cmd == "disconnect":
            if self.mode != "work" or self.view != "connectors":
                self.note_text = "disconnect: not this view"
                return None
            self.connector_disconnect(arg)
            return None
        if cmd == "approve":
            if self.mode != "work" or self.view != "bridge":
                self.note_text = "approve: not this view"
                return None
            self.bridge_approve(arg)
            return None
        if cmd == "deny":
            if self.mode != "work" or self.view != "bridge":
                self.note_text = "deny: not this view"
                return None
            self.bridge_deny(arg)
            return None
        if cmd == "start":
            self.login_start(arg)
            return None
        if cmd == "cancel" and not arg:
            self.login_cancel()
            return None
        if cmd == "poll" and not arg:
            self.login_poll()
            return None
        if cmd == "rollback":
            self.rollback(arg)
            return None
        if self.view == "snapper" and cmd.isdigit() and not arg:
            self.rollback(cmd)
            return None

        self.note_text = "unknown: %s" % cmd
        return None


def serve(stdin=None, stdout=None, mode=None):
    stdin = sys.stdin if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    sess = Session(mode)
    try:
        sess.piped = not stdin.isatty()
    except Exception:
        sess.piped = True
    prev_int = None
    if not sess.piped:
        # L-09: kernel VINTR still discards a partial line; keep readline.
        prev_int = signal.signal(signal.SIGINT, signal.SIG_IGN)
    try:
        try:
            _line(stdout, "views: %s" % " ".join(sess.catalog()))
            sess.render(stdout)
        except BrokenPipeError:
            if sess.piped:
                return 0
        except KeyboardInterrupt:
            if sess.piped:
                return 0
        while True:
            try:
                try:
                    raw = stdin.readline()
                except KeyboardInterrupt:
                    if sess.piped:
                        return 0
                    continue
                if raw == "":
                    if sess.piped:
                        return 0
                    nxt = _fresh_stdin(stdin)
                    if nxt is stdin:
                        time.sleep(0.05)
                    else:
                        stdin = nxt
                    continue
                result = sess.handle(raw)
                if result == "quit":
                    return 0
                sess.render(stdout)
            except KeyboardInterrupt:
                if sess.piped:
                    return 0
                continue
            except BrokenPipeError:
                if sess.piped:
                    return 0
                continue
            except Exception as exc:
                try:
                    _line(stdout, "error: %s" % exc)
                except (BrokenPipeError, KeyboardInterrupt):
                    if sess.piped:
                        return 0
                    continue
                if sess.piped:
                    return 0
                continue
    finally:
        if prev_int is not None:
            signal.signal(signal.SIGINT, prev_int)
    return 0


def _usage(out):
    _line(out, "usage: aios [os|work|brake|status]")
    _line(out, "aios / aios os  OS definition surface (mode: os)")
    _line(out, "aios work       work surface (HI-15 unless explicit yes)")
    _line(out, "aios brake      freeze privileged writes (L-12); TUI stays")
    _line(out, "aios status     mode and brake stamp")
    _line(out, "L-18 views: %s" % " ".join(VIEWS))


def cli_brake(out=None):
    out = sys.stdout if out is None else out
    try:
        write_brake()
    except OSError as exc:
        _line(out, "brake failed: %s (L-12)" % exc)
        return 1
    _line(out, "brake: on")
    _line(out, "human-only; freeze privileged writes; TUI stays (L-12)")
    return 0


def cli_status(out=None):
    out = sys.stdout if out is None else out
    on = _brake_on()
    _line(out, "mode: os")
    _line(out, "view: chrome")
    _line(out, "brake: %s" % ("on" if on else "off"))
    _line(out, "brake is a chrome action, not a view (L-12)")
    return 0


def refuse_work(out=None):
    out = sys.stdout if out is None else out
    _line(out, WORK_REFUSED)
    return 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        return serve()
    cmd = argv[0].lower()
    if cmd in ("-h", "--help", "help"):
        _usage(sys.stdout)
        return 0
    if cmd == "os":
        if len(argv) > 1:
            _usage(sys.stderr)
            return 2
        return serve()
    if cmd == "work":
        if not work_runtime_on():
            return refuse_work()
        if len(argv) > 1:
            _usage(sys.stderr)
            return 2
        return serve(mode="work")
    if cmd == "brake":
        if len(argv) > 1:
            _usage(sys.stderr)
            return 2
        return cli_brake()
    if cmd == "status":
        if len(argv) > 1:
            _usage(sys.stderr)
            return 2
        return cli_status()
    _usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
