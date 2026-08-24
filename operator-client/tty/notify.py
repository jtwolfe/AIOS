#!/usr/bin/python3
"""HI-14 notify view: five-name failure payload, not a coding CLI (P7.2)."""

import json
import os

# Same scan set as checker/policy/hi-14-failure-handoff.sh
NOTIFY_DIRS = (
    "/run/aios/notify",
    "/srv/aios/state/notify",
    "/srv/aios/memory/notify",
)

# Field names the policy greps. Do not invent a sixth required name.
UNIT_KEYS = ("unit", "executable")
JOURNAL_KEYS = ("journal", "journal_slice")
COMMIT_KEYS = ("commit", "state_commit")
SNAPPER_KEYS = ("snapper", "snapper_id")
CLAUSE_KEYS = ("clause",)
SKILL_KEYS = ("skill", "skill_path")


def scan_dirs():
    override = os.environ.get("AIOS_NOTIFY")
    if override:
        return (override,)
    return NOTIFY_DIRS


def _present(val):
    if val is None or val == "" or val == 0 or val == "0":
        return None
    if isinstance(val, bool):
        return None
    if isinstance(val, (int, float)):
        return str(val)
    text = str(val).strip()
    if not text or text == "0":
        return None
    return text


def _first(doc, keys):
    if not isinstance(doc, dict):
        return None
    for key in keys:
        got = _present(doc.get(key))
        if got is not None:
            return got
    return None


def parse(doc):
    """Return a complete HI-14 payload or None. Missing fields are not filled."""
    unit = _first(doc, UNIT_KEYS)
    journal = _first(doc, JOURNAL_KEYS)
    commit = _first(doc, COMMIT_KEYS)
    snapper = _first(doc, SNAPPER_KEYS)
    clause = _first(doc, CLAUSE_KEYS)
    if not unit or not journal or not commit or not snapper or not clause:
        return None
    out = {
        "unit": unit,
        "journal": journal,
        "commit": commit,
        "snapper": snapper,
        "clause": clause,
    }
    skill = _first(doc, SKILL_KEYS)
    if skill:
        out["skill"] = skill
    return out


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            blob = fh.read()
    except OSError:
        return None
    if not blob.strip():
        return None
    try:
        doc = json.loads(blob)
    except ValueError:
        return None
    if not isinstance(doc, dict):
        return None
    return doc


def load_payloads():
    items = []
    for folder in scan_dirs():
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(folder, name)
            if not os.path.isfile(path):
                continue
            doc = _read(path)
            if doc is None:
                continue
            payload = parse(doc)
            if payload is None:
                continue
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                mtime = 0
            payload = dict(payload)
            payload["path"] = path
            items.append((mtime, path, payload))
    items.sort(key=lambda row: (-row[0], row[1]))
    return [row[2] for row in items]


def conversation_line(payload):
    parts = [
        "HI-14",
        "unit: %s" % payload["unit"],
        "journal: %s" % payload["journal"],
        "commit: %s" % payload["commit"],
        "snapper: %s" % payload["snapper"],
        "clause: %s" % payload["clause"],
    ]
    skill = payload.get("skill")
    if skill:
        parts.append("skill: %s" % skill)
    return " | ".join(parts)


def render_lines(payloads):
    lines = []
    if not payloads:
        lines.append("handoff: none")
        lines.append("open: OS conversation with payload; not a coding CLI (HI-14)")
        return lines
    lines.append("handoff: %s" % len(payloads))
    for i, payload in enumerate(payloads):
        if i:
            lines.append("---")
        lines.append("unit: %s" % payload["unit"])
        lines.append("journal: %s" % payload["journal"])
        lines.append("commit: %s" % payload["commit"])
        lines.append("snapper: %s" % payload["snapper"])
        lines.append("clause: %s" % payload["clause"])
        skill = payload.get("skill")
        if skill:
            lines.append("skill: %s" % skill)
    lines.append("open: OS conversation with payload; not a coding CLI (HI-14)")
    return lines
