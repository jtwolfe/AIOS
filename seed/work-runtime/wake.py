"""Wake inject order from skills/wake.md."""

import os
import re

from skills import catalog_text

INJECTS = (
    "AGENTS.md",
    "skills catalog",
    "tools",
    "operational notes",
    "envelope bit",
)

_ENABLED_LINE = re.compile(r"^\s*enabled\s*[:=]\s*(true|yes|1)\s*$")
_DISABLED_LINE = re.compile(r"^\s*enabled\s*[:=]\s*(false|no|0)\s*$")
_VETO_LINE = re.compile(r"^\s*vetoes\.([A-Za-z0-9_-]+)\s*[:=]\s*(.*)$")
_NOTE_TOKEN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
_NOTE_STOP = frozenset(
    (
        "the",
        "and",
        "for",
        "with",
        "from",
        "into",
        "this",
        "that",
        "your",
        "about",
        "job",
        "note",
        "notes",
        "work",
        "task",
        "please",
    )
)


class WakeError(Exception):
    """Inject cannot be built."""


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _compiled_path(root):
    env = os.environ.get("AIOS_WORK_ENVELOPE")
    if env is not None:
        env = env.strip()
        if not env:
            raise WakeError("AIOS_WORK_ENVELOPE empty")
        return env
    return os.path.join(root, "envelope", "compiled.md")


def _parse_compiled(text):
    enabled = None
    vetoes = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if _ENABLED_LINE.match(stripped):
            enabled = True
            continue
        if _DISABLED_LINE.match(stripped):
            enabled = False
            continue
        veto = _VETO_LINE.match(stripped)
        if veto:
            vetoes[veto.group(1)] = veto.group(2).strip()
    return enabled, vetoes


def _env_bit():
    raw = os.environ.get("AIOS_WORK_RUNTIME")
    if raw is None:
        return None
    val = raw.strip().lower()
    if not val:
        raise WakeError("AIOS_WORK_RUNTIME empty")
    if val in ("yes", "true", "1"):
        return True
    if val in ("no", "false", "0"):
        return False
    raise WakeError("AIOS_WORK_RUNTIME invalid")


def envelope_state(root):
    # Work uid cannot read /srv/aios/state or /srv/aios/envelope (L-23).
    path = _compiled_path(root)
    env_enabled = _env_bit()
    file_enabled = None
    vetoes = {}
    if os.path.isfile(path):
        file_enabled, vetoes = _parse_compiled(_read(path))
    if file_enabled is None and env_enabled is None:
        raise WakeError("work envelope bit missing (HI-15)")
    enabled = env_enabled if env_enabled is not None else file_enabled
    return enabled, vetoes


def envelope_text(root):
    enabled, vetoes = envelope_state(root)
    lines = ["work-runtime enabled: %s" % ("yes" if enabled else "no")]
    if not vetoes:
        lines.append("vetoes: none")
        return "\n".join(lines)
    for key in sorted(vetoes):
        lines.append("vetoes.%s: %s" % (key, vetoes[key]))
    return "\n".join(lines)


def _notes_dir(root):
    env = os.environ.get("AIOS_WORK_NOTES")
    if env is not None:
        env = env.strip()
        if not env:
            raise WakeError("AIOS_WORK_NOTES empty")
        return env
    return os.path.join(root, "notes")


def _note_tokens(text):
    words = _NOTE_TOKEN.findall((text or "").lower())
    return [w for w in words if len(w) >= 4 and w not in _NOTE_STOP]


def notes_text(root, asked):
    notes_dir = _notes_dir(root)
    if not os.path.isdir(notes_dir):
        return "none"
    tokens = _note_tokens(asked)
    if not tokens:
        return "none"
    matched = []
    for name in sorted(os.listdir(notes_dir)):
        path = os.path.join(notes_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            body = _read(path).rstrip()
        except OSError:
            continue
        if not body:
            continue
        hay = "%s\n%s" % (name.lower(), body.lower())
        if any(token in hay for token in tokens):
            matched.append(body)
    if not matched:
        return "none"
    return "\n\n".join(matched)


def inject(asked, root):
    agents = os.path.join(root, "AGENTS.md")
    tools = os.path.join(root, "boundaries", "interfaces.md")
    if not os.path.isfile(agents):
        raise WakeError("missing %s" % agents)
    if not os.path.isfile(tools):
        raise WakeError("missing %s" % tools)
    sections = (
        ("AGENTS.md", _read(agents)),
        ("skills catalog", catalog_text(root)),
        ("tools", _read(tools)),
        ("operational notes", notes_text(root, asked)),
        ("envelope bit", envelope_text(root)),
    )
    parts = []
    names = []
    for index, (title, body) in enumerate(sections, 1):
        names.append(title)
        parts.append("[inject %s] %s\n%s" % (index, title, body.rstrip()))
    if tuple(names) != INJECTS:
        raise WakeError("inject order drifted")
    parts.append("asked: %s" % asked)
    return "\n\n".join(parts) + "\n", list(INJECTS)
