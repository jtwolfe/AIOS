#!/usr/bin/python3
"""Installer TUI in installer mode (L-09, L-18, L-12, L-20). Same catalog as the OS client."""

import os
import sys
import time

import compiler
import questions
import recover

# L-18 installer catalog. A view not in this tuple is a docs patch first.
VIEWS = (
    "chrome",
    "conversation",
    "questions",
    "envelope",
    "accept",
    "recovery",
)

MODE = "installer"
BRAKE_PATH = "/srv/aios/state/brake"
IDLE_S = 3600

ACTIONS = {
    "chrome": ("view", "brake", "send", "mode"),
    "conversation": ("send", "attach", "view", "brake"),
    "questions": ("answer", "skip", "view", "send", "brake"),
    "envelope": ("accept", "reject", "view", "brake"),
    "accept": ("accept", "reject", "view", "brake"),
    "recovery": ("resume", "view", "brake"),
}

_SHORT_VIEW = {
    "c": "conversation",
    "q": "questions",
    "e": "envelope",
    "h": "chrome",
    "r": "recovery",
}


def _line(out, text=""):
    out.write("%s\n" % text)
    out.flush()


def _brake_path():
    return os.environ.get("AIOS_BRAKE") or BRAKE_PATH


class Session:
    def __init__(self):
        self.mode = MODE
        self.view = "questions"
        self.answers = questions.empty()
        self.qindex = 0
        self.transcript = []
        self.braked = False
        self.writes_frozen = False
        self.decision = None
        self.last_step = "questions"
        self.note_text = ""
        self.snapper_id = None
        self.piped = False

    def qid(self):
        if 0 <= self.qindex < len(questions.IDS):
            return questions.IDS[self.qindex]
        return None

    def _advance(self):
        if self.qindex < len(questions.IDS):
            self.qindex += 1

    def actions(self):
        return ACTIONS.get(self.view, ("view", "brake"))

    def render(self, out):
        _line(out, "-- AIOS installer --")
        _line(out, "mode: %s" % self.mode)
        _line(out, "view: %s" % self.view)
        _line(out, "actions: %s" % " ".join(self.actions()))
        _line(out, "catalog: %s" % " ".join(VIEWS))
        _line(out, "brake: %s" % ("on" if self.braked else "off"))
        _line(
            out,
            "writes: %s" % ("frozen" if self.writes_frozen else "live"),
        )
        work = "true" if questions.work_runtime_on(self.answers) else "false"
        _line(out, "work-runtime: %s" % work)
        if self.note_text:
            _line(out, "note: %s" % self.note_text)
        body = {
            "chrome": self._chrome,
            "conversation": self._conversation,
            "questions": self._questions,
            "envelope": self._envelope,
            "accept": self._accept,
            "recovery": self._recovery,
        }[self.view]
        body(out)
        _line(out, "--")

    def _chrome(self, out):
        _line(out, "surface: installer")
        _line(out, "switch: os/work refused until envelope accept (L-17, L-09)")
        _line(out, "brake: human-only; freeze writes; TUI stays (L-12)")
        _line(out, "send: conversation line; questions end the turn")

    def _conversation(self, out):
        _line(out, "transcript:")
        if not self.transcript:
            _line(out, "  (empty)")
        else:
            for item in self.transcript[-20:]:
                _line(out, "  %s" % item)
        _line(out, "attach: not allowed in installer mode")

    def _questions(self, out):
        qid = self.qid()
        _line(out, questions.format_answers(self.answers))
        if qid is None:
            _line(out, "question: (done)")
            _line(out, "prompt: open envelope to accept or reject")
            return
        _line(out, "question: %s" % qid)
        _line(out, "prompt: %s" % questions.PROMPTS[qid])
        if qid == "work-runtime":
            _line(out, "skip: not a yes (HI-15)")

    def _envelope(self, out):
        for line in compiler.draft(self.answers).splitlines():
            _line(out, line)
        _line(out, "envelope-decision: %s" % (self.decision or "(none)"))

    def _accept(self, out):
        _line(out, "accept/reject the compiled envelope (keyboard).")
        _line(out, "envelope-decision: %s" % (self.decision or "(none)"))
        _line(out, compiler.draft(self.answers).splitlines()[0])

    def _recovery(self, out):
        for line in recover.render(
            self.last_step, self.answers, self.snapper_id, self.decision
        ).splitlines():
            _line(out, line)

    def switch(self, view_id):
        if view_id not in VIEWS:
            self.note_text = "unknown view %s (L-18)" % view_id
            return
        self.view = view_id
        self.last_step = view_id
        self.note_text = ""

    def brake(self):
        # L-12: stop the proposer, freeze privileged writes; installer stays.
        self.braked = True
        self.writes_frozen = True
        path = _brake_path()
        try:
            parent = os.path.dirname(path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("braked\n")
        except OSError:
            pass
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

    def attach(self):
        self.note_text = "attach: refused"

    def _frozen(self):
        if self.writes_frozen:
            self.note_text = "refused: writes frozen (L-12)"
            return True
        return False

    def accept(self):
        if self._frozen():
            return
        self.decision = "accepted"
        self.last_step = "accept"
        self.note_text = "envelope accepted (HI-05)"
        self.view = "accept"

    def reject(self):
        if self._frozen():
            return
        self.decision = "rejected"
        self.last_step = "accept"
        self.note_text = "envelope rejected; rollback is L-19 (no half-install)"
        self.view = "accept"

    def resume(self):
        target = recover.resume_view(self.last_step)
        self.view = target
        self.note_text = "resume: last-step=%s" % target

    def skip(self, qid):
        qid = (qid or "").strip() or self.qid()
        if not qid:
            self.note_text = "skip: no current question"
            return
        try:
            result = questions.apply_skip(self.answers, qid)
        except ValueError as exc:
            self.note_text = str(exc)
            return
        if qid == self.qid():
            self._advance()
        self.last_step = "questions"
        self.note_text = "skip: %s" % result

    def answer(self, payload):
        payload = (payload or "").strip()
        qid = self.qid()
        text = payload
        if payload:
            first, _, rest = payload.partition(" ")
            if first in questions.IDS:
                qid = first
                text = rest.strip()
        if not qid:
            self.note_text = "answer: no current question"
            return
        try:
            result = questions.apply_answer(self.answers, qid, text)
        except ValueError as exc:
            self.note_text = str(exc)
            return
        if qid == self.qid():
            self._advance()
        self.last_step = "questions"
        self.note_text = "answer: %s" % result

    def mode_switch(self, target):
        target = (target or "").strip().lower()
        if not target or target == MODE:
            self.mode = MODE
            self.note_text = "mode: installer"
            return
        # Unsigned firstboot: OS/work surfaces are later (L-09, L-17).
        self.note_text = "mode refused: %s (L-17, L-09); staying installer" % target

    def handle(self, raw):
        line = (raw or "").strip()
        if not line:
            return None
        if line.startswith(":"):
            line = line[1:].strip()
        parts = line.split(None, 1)
        cmd = parts[0].lower()
        arg = parts[1] if len(parts) > 1 else ""

        if cmd in ("quit", "exit"):
            if self.piped:
                return "quit"
            self.note_text = "installer stays up until accept (L-09)"
            return None

        if cmd == "help":
            self.note_text = "actions: %s" % " ".join(self.actions())
            return None

        if self.view == "questions" and cmd in ("y", "yes", "n", "no"):
            self.answer(cmd)
            return None

        if self.view in ("envelope", "accept") and cmd in ("y", "yes"):
            self.accept()
            return None
        if self.view in ("envelope", "accept") and cmd in ("n", "no"):
            self.reject()
            return None

        if cmd in ("view", "v"):
            name = _SHORT_VIEW.get(arg.strip().lower(), arg.strip().lower())
            if name == "a":
                name = "accept"
            self.switch(name)
            return None

        if cmd in VIEWS and cmd != "accept":
            self.switch(cmd)
            return None

        if cmd in _SHORT_VIEW and not arg:
            self.switch(_SHORT_VIEW[cmd])
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
        if cmd == "skip":
            self.skip(arg)
            return None
        if cmd == "answer":
            self.answer(arg)
            return None
        if cmd == "accept":
            self.accept()
            return None
        if cmd == "reject":
            self.reject()
            return None
        if cmd == "resume":
            self.resume()
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
    try:
        _line(stdout, "views: %s" % " ".join(VIEWS))
        sess.render(stdout)
    except BrokenPipeError:
        return 0
    while True:
        try:
            raw = stdin.readline()
        except KeyboardInterrupt:
            if sess.piped:
                return 0
            continue
        except Exception as exc:
            try:
                _line(stdout, "error: %s" % exc)
            except BrokenPipeError:
                return 0
            if sess.piped:
                return 0
            time.sleep(1)
            continue
        if raw == "":
            if sess.piped:
                return 0
            # L-09: idle on the console; do not exit into getty.
            time.sleep(IDLE_S)
            continue
        try:
            result = sess.handle(raw)
        except Exception as exc:
            try:
                _line(stdout, "error: %s" % exc)
                sess.render(stdout)
            except BrokenPipeError:
                return 0
            continue
        if result == "quit":
            return 0
        try:
            sess.render(stdout)
        except BrokenPipeError:
            return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] in ("-h", "--help", "help"):
        sys.stdout.write("usage: main.py\nL-18 views: %s\n" % " ".join(VIEWS))
        sys.stdout.flush()
        return 0
    return serve()


if __name__ == "__main__":
    sys.exit(main())
