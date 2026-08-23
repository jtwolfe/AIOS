"""Classify a turn. Not every message is a build (HI-07, L-21)."""

import re

# Empty pings are not daemons (L-21).
_EMPTY = frozenset(
    ("", "ping", "pong", "hello", "hi", "hey", "ok", "thanks", "thx", "yo")
)

# Instruction vs HI: raise, do not swallow (HI-07).
_CONFLICT = (
    (re.compile(r"(?i)\b(merge|commit|push)\b.{0,48}\bmain\b"), "HI-03"),
    (re.compile(r"(?i)force[- ]push|--force\b|\bgit\s+push\s+-[a-z]*f"), "HI-03"),
    (re.compile(r"(?i)curl\s*\|(\s*(ba)?sh)?|wget\s*\|"), "HI-04"),
    (
        re.compile(
            r"(?i)(disable|mask|stop|kill|restart)\s+\S*"
            r"(aios-checker|snapper|etckeeper|aios-agent)"
        ),
        "HI-06",
    ),
    (re.compile(r"(?i)\bpacman\s+-S(?!yu\b)\S*\s+\S"), "HI-06"),
    (
        re.compile(
            r"(?i)(synthesi[sz]e|enable|start).{0,48}work[- ]runtime"
            r"|work[- ]runtime.{0,48}(synthesi[sz]e|enable|start)"
        ),
        "HI-15",
    ),
)

# A question about a veto is not an instruction to violate it.
_REQUEST = re.compile(
    r"(?i)\b(please|go ahead|do it|install|disable|mask|enable work|synthesi)"
)

_PRIVILEGED = re.compile(
    r"(?i)(\bpacman\b|\b-syu\b|\benact\b|\bbootctl\b|\bmkinitcpio\b|"
    r"\bsystemctl\b|\bfstab\b|install\s+\S+|/\s*etc/systemd|"
    r"\benvelope\b|hard.invariant|skill\.md|unit file)"
)

_QUESTION_START = re.compile(
    r"(?i)^(why|how|what|when|where|who|which|is |are |does |do |"
    r"can |could |should |may )"
)


class TriageResult:
    def __init__(self, kind, asked, reason, hi=None):
        self.kind = kind
        self.asked = asked
        self.reason = reason
        self.hi = hi


def _is_question(text):
    stripped = text.strip()
    if stripped.endswith("?"):
        return True
    return bool(_QUESTION_START.match(stripped))


def _conflict_hi(text):
    for pattern, hi in _CONFLICT:
        if pattern.search(text):
            return hi
    return None


def classify(text):
    asked = text if isinstance(text, str) else str(text or "")
    stripped = asked.strip()
    if stripped.lower() in _EMPTY:
        return TriageResult(
            "empty", asked, "empty ping is not a build (L-21)"
        )

    hi = _conflict_hi(stripped)
    if hi:
        # A why/how about the rule is not an instruction (HI-07).
        if not (_is_question(stripped) and not _REQUEST.search(stripped)):
            return TriageResult(
                "conflict",
                asked,
                "instruction vs %s" % hi,
                hi=hi,
            )

    if _PRIVILEGED.search(stripped):
        if not (
            _is_question(stripped)
            and not _REQUEST.search(stripped)
            and not re.search(r"(?i)\b(install|enact|systemctl|pacman\s+-)", stripped)
        ):
            return TriageResult("privileged", asked, "privileged change")

    if _is_question(stripped):
        return TriageResult("question", asked, "not a build")
    return TriageResult("talk", asked, "update conditions, not a build")
