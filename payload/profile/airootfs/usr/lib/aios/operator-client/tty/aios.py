#!/usr/bin/python3
"""OS operator client (P7.1, P7.2, P7.3, L-18, L-12, HI-14). Unprivileged. One binary."""

import os
import signal
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

MODE = "os"
BRAKE_PATH = "/srv/aios/state/brake.d/stamp"
WORK_REFUSED = (
    "refused: work (HI-15); work runtime is off until bootstrap "
    "records an explicit yes"
)

ACTIONS = {
    "chrome": ("view", "brake", "send", "mode"),
    "conversation": ("send", "view", "brake", "mode"),
    "notify": ("open", "view", "brake", "mode"),
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

def _line(out, text=""):
    out.write("%s\n" % text)
    out.flush()


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


class Session:
    def __init__(self):
        self.mode = MODE
        self.view = "chrome"
        self.transcript = []
        self.braked = _brake_on()
        self.writes_frozen = self.braked
        self.note_text = ""
        self.piped = False

    def actions(self):
        return ACTIONS.get(self.view, ("view", "brake", "mode"))

    def render(self, out):
        _line(out, "-- AIOS --")
        _line(out, "mode: %s" % self.mode)
        _line(out, "view: %s" % self.view)
        _line(out, "actions: %s" % " ".join(self.actions()))
        _line(out, "catalog: %s" % " ".join(VIEWS))
        _line(out, "brake: %s" % ("on" if self.braked else "off"))
        _line(
            out,
            "writes: %s" % ("frozen" if self.writes_frozen else "live"),
        )
        if self.note_text:
            _line(out, "note: %s" % self.note_text)
        if self.view == "chrome":
            self._chrome(out)
        elif self.view == "conversation":
            self._conversation(out)
        elif self.view == "notify":
            self._notify(out)
        else:
            self._stub(out)
        _line(out, "--")

    def _chrome(self, out):
        _line(out, "surface: os")
        _line(out, "switch: work refused (HI-15); installer refused (not firstboot)")
        _line(out, "brake: human-only; freeze privileged writes; TUI stays (L-12)")
        _line(out, "send: conversation line")
        _line(out, "os-views: %s" % " ".join(VIEWS))

    def _conversation(self, out):
        _line(out, "transcript:")
        if not self.transcript:
            _line(out, "  (empty)")
        else:
            for item in self.transcript[-20:]:
                _line(out, "  %s" % item)

    def _notify(self, out):
        for line in notify.render_lines(notify.load_payloads()):
            _line(out, line)

    def open_handoff(self):
        payloads = notify.load_payloads()
        if not payloads:
            self.note_text = "no HI-14 payload"
            return
        self.transcript.append(notify.conversation_line(payloads[0]))
        self.view = "conversation"
        self.note_text = "opened notify into conversation (HI-14)"

    def _stub(self, out):
        _line(out, "not this PR")

    def switch(self, view_id):
        view_id = (view_id or "").strip().lower()
        if view_id == "brake":
            self.note_text = "brake is a chrome action, not a view (L-12, L-18)"
            return
        if view_id in INSTALLER_VIEWS:
            self.note_text = "installer view refused (not firstboot)"
            return
        if view_id in WORK_VIEWS:
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

    def send(self, text):
        text = (text or "").strip()
        if not text:
            self.note_text = "send: empty"
            return
        self.transcript.append("operator: %s" % text)
        if text.endswith("?"):
            self.note_text = "turn-ended: question"
        else:
            self.note_text = "sent"

    def mode_switch(self, target):
        target = (target or "").strip().lower()
        if not target or target == MODE:
            self.mode = MODE
            self.note_text = "mode: os"
            return
        if target == "work":
            self.note_text = "mode refused: work (HI-15); staying os"
            return
        if target == "installer":
            self.note_text = "mode refused: installer (not firstboot)"
            return
        self.note_text = "mode refused: %s; staying os" % target

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
            name = _SHORT_VIEW.get(arg.strip().lower(), arg.strip().lower())
            self.switch(name)
            return None

        if cmd in VIEWS:
            self.switch(cmd)
            return None

        if cmd in _SHORT_VIEW and not arg:
            self.switch(_SHORT_VIEW[cmd])
            return None

        if cmd in ("brake", "b") and not arg:
            self.brake()
            return None
        if cmd == "open":
            if self.view != "notify":
                self.note_text = "open is a notify action (HI-14)"
                return None
            self.open_handoff()
            return None
        if cmd == "send":
            self.send(arg)
            return None
        if cmd == "mode":
            self.mode_switch(arg)
            return None

        self.note_text = "unknown: %s" % cmd
        return None


def serve(stdin=None, stdout=None):
    stdin = sys.stdin if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    sess = Session()
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
            _line(stdout, "views: %s" % " ".join(VIEWS))
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
    _line(out, "aios work       work surface (refused: HI-15)")
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
        return refuse_work()
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
