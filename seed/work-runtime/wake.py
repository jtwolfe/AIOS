"""Wake inject order from skills/wake.md. One invocation. Stateless per turn."""

import json
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

ANSWERS_PATH = "/srv/aios/state/bootstrap-in-progress/answers.json"
ENVELOPE_WORK = "/srv/aios/envelope/work-runtime.md"

# Skip is not a yes (HI-15).
_ENABLED_LINE = re.compile(r"^\s*enabled\s*[:=]\s*(true|yes|1)\s*$")


class WakeError(Exception):
    """Inject cannot be built."""


def resolve_path(env_name, default):
    env = os.environ.get(env_name)
    if env is not None:
        env = env.strip()
        if not env:
            raise WakeError("%s empty" % env_name)
        return env
    root = os.environ.get("AIOS_ROOT")
    if root is not None:
        root = root.strip()
        if not root:
            raise WakeError("AIOS_ROOT empty")
        return os.path.abspath(root) + default
    return default


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _answers_path():
    return resolve_path("AIOS_ANSWERS", ANSWERS_PATH)


def _envelope_work():
    return resolve_path("AIOS_ENVELOPE_WORK", ENVELOPE_WORK)


def work_runtime_yes():
    """Skip is not a yes (HI-15)."""
    answers = _answers_path()
    if os.path.isfile(answers):
        try:
            with open(answers, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            doc = None
        if isinstance(doc, dict) and doc.get("accepted") is True:
            if doc.get("work_runtime") is True:
                return True
    clause = _envelope_work()
    if os.path.isfile(clause):
        try:
            text = _read(clause)
        except OSError:
            text = ""
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if _ENABLED_LINE.match(stripped):
                return True
    return False


def _vetoes():
    path = _answers_path()
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError):
        return {}
    if not isinstance(doc, dict):
        return {}
    vetoes = doc.get("vetoes") or {}
    if not isinstance(vetoes, dict):
        return {}
    return vetoes


def envelope_text():
    enabled = "yes" if work_runtime_yes() else "no"
    lines = ["work-runtime enabled: %s" % enabled]
    vetoes = _vetoes()
    if not vetoes:
        lines.append("vetoes: none")
        return "\n".join(lines)
    for key in sorted(vetoes):
        value = vetoes[key]
        if value is True:
            shown = "yes"
        elif value is False:
            shown = "no"
        else:
            shown = str(value)
        lines.append("vetoes.%s: %s" % (key, shown))
    return "\n".join(lines)


def _notes_dir(root):
    env = os.environ.get("AIOS_WORK_NOTES")
    if env is not None:
        env = env.strip()
        if not env:
            raise WakeError("AIOS_WORK_NOTES empty")
        return env
    return os.path.join(root, "notes")


def notes_text(root, asked):
    notes_dir = _notes_dir(root)
    if not os.path.isdir(notes_dir):
        return "none"
    needle = (asked or "").strip().lower()
    matched = []
    all_notes = []
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
        all_notes.append(body)
        if needle and (needle in body.lower() or needle in name.lower()):
            matched.append(body)
    chosen = matched or all_notes
    if not chosen:
        return "none"
    return "\n\n".join(chosen)


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
        ("envelope bit", envelope_text()),
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
