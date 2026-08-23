"""Load SKILL.md playbooks on demand. The model does not curate the tree (HI-11)."""

import json
import os

SKILLS_ROOT = "/srv/aios/skills"
# P4.3 lock: two successful verbatim moments of the same class, or a human ask.
# Promotion is a proposal in this tree, not model fiat (HI-11).
EARN_AFTER = 2


class Skill:
    def __init__(self, name, path, description, triggers, body, references):
        self.name = name
        self.path = path
        self.description = description
        self.triggers = list(triggers)
        self.body = body
        self.references = list(references)


def _fm(text):
    meta = {}
    key = None
    for line in text.splitlines():
        stripped = line.strip()
        if key and stripped.startswith("- "):
            cur = meta.get(key)
            if not isinstance(cur, list):
                meta[key] = [] if cur in (None, "") else [cur]
            meta[key].append(stripped[2:].strip())
            continue
        if ":" in stripped:
            key, value = stripped.split(":", 1)
            key = key.strip()
            value = value.strip()
            meta[key] = value if value else []
    return meta


def _load_skill(path):
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read()
    meta = {}
    body = raw
    if raw.startswith("---"):
        end = raw.find("\n---", 3)
        if end != -1:
            meta = _fm(raw[3:end])
            body = raw[end + 4 :].lstrip("\n")
    name = meta.get("name") or os.path.basename(os.path.dirname(path)) or "skill"
    description = meta.get("description") or ""
    triggers = meta.get("triggers") or [name]
    if isinstance(triggers, str):
        triggers = [part.strip() for part in triggers.split(",") if part.strip()]
    references = []
    refdir = os.path.join(os.path.dirname(path), "references")
    if os.path.isdir(refdir):
        for fn in sorted(os.listdir(refdir)):
            fp = os.path.join(refdir, fn)
            if os.path.isfile(fp):
                with open(fp, "r", encoding="utf-8") as fh:
                    references.append((fn, fh.read()))
    # Body (and references) are read here: following a skill requires this turn.
    return Skill(name, path, description, triggers, body, references)


def catalog(root=None):
    root = root or os.environ.get("AIOS_SKILLS") or SKILLS_ROOT
    out = []
    if not os.path.isdir(root):
        return out
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            if name != "SKILL.md":
                continue
            out.append(_load_skill(os.path.join(dirpath, name)))
    return out


def match(text, root=None):
    """Return skills whose triggers hit this turn. Empty means say so; do not invent."""
    asked = (text or "").lower()
    hit = []
    for skill in catalog(root):
        for trig in skill.triggers:
            if trig and trig.lower() in asked:
                hit.append(skill)
                break
    return hit


def nested_agents(path):
    """Deeper AGENTS.md outranks a general skill for files in that tree."""
    path = path or ""
    found = []
    cur = os.path.abspath(path) if path else ""
    while cur and cur != os.path.dirname(cur):
        candidate = os.path.join(cur, "AGENTS.md")
        if os.path.isfile(candidate):
            with open(candidate, "r", encoding="utf-8") as fh:
                found.append((candidate, fh.read()))
        cur = os.path.dirname(cur)
    return found


def earns_skill(successful_moments, human_asked=False):
    """Mechanical bar only. No model_wants argument (HI-11)."""
    if human_asked:
        return True
    try:
        count = int(successful_moments)
    except (TypeError, ValueError):
        count = 0
    return count >= EARN_AFTER


def count_successful(root, class_name):
    """Count verbatim moments of a class that already verified."""
    root = root or os.environ.get("AIOS_MEMORY") or "/srv/aios/memory"
    moments = os.path.join(root, "moments")
    if not os.path.isdir(moments):
        return 0
    n = 0
    for name in os.listdir(moments):
        path = os.path.join(moments, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(doc, dict):
            continue
        if doc.get("class") != class_name:
            continue
        if doc.get("outcome") in ("verify", "verified"):
            n += 1
    return n
