"""Routines: cron xor listeners. A file in the work store. Disable leaves git."""

import json
import os
import re

class RoutineError(Exception):
    """Routine surface cannot complete."""


def _dir(root):
    return os.path.join(root, "routines")


def _safe_id(raw):
    text = re.sub(r"[^A-Za-z0-9._-]+", "-", str(raw or "").strip()).strip(".-")
    if not text or text in (".", ".."):
        raise RoutineError("routine id missing")
    return text


def _path(root, routine_id):
    return os.path.join(_dir(root), "%s.json" % routine_id)


def _present(value):
    if value is None or value is False:
        return False
    if value == "" or value == [] or value == {}:
        return False
    return True


def _kind_and_fields(spec):
    cron = spec.get("cron")
    listeners = spec.get("listeners")
    has_cron = _present(cron)
    has_listeners = _present(listeners)
    if has_cron and has_listeners:
        raise RoutineError("a routine is cron or listeners, never both")
    kind = str(spec.get("kind") or "").strip().lower()
    if kind in ("cron", "listeners"):
        if kind == "cron" and has_listeners:
            raise RoutineError("a routine is cron or listeners, never both")
        if kind == "listeners" and has_cron:
            raise RoutineError("a routine is cron or listeners, never both")
        if kind == "cron" and not has_cron:
            raise RoutineError("a routine needs cron or listeners")
        if kind == "listeners" and not has_listeners:
            raise RoutineError("a routine needs cron or listeners")
        return kind, cron if has_cron else "", listeners if has_listeners else []
    if has_cron:
        return "cron", cron, []
    if has_listeners:
        return "listeners", "", listeners
    raise RoutineError("a routine needs cron or listeners")


def _save(root, record):
    os.makedirs(_dir(root), exist_ok=True)
    path = _path(root, record["id"])
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return record


def _load(root, routine_id):
    path = _path(root, routine_id)
    if not os.path.isfile(path):
        raise RoutineError("unknown routine %s" % routine_id)
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise RoutineError("routine record invalid")
    return data


def create(root, spec):
    spec = dict(spec or {})
    routine_id = _safe_id(spec.get("id") or spec.get("name") or spec.get("text"))
    kind, cron, listeners = _kind_and_fields(spec)
    record = {
        "id": routine_id,
        "kind": kind,
        "cron": cron if kind == "cron" else "",
        "listeners": listeners if kind == "listeners" else [],
        "enabled": True,
        "path": os.path.join("routines", "%s.json" % routine_id),
    }
    return _save(root, record)


def disable(root, spec):
    spec = dict(spec or {})
    routine_id = _safe_id(spec.get("id") or spec.get("name") or spec.get("text"))
    record = _load(root, routine_id)
    record["enabled"] = False
    return _save(root, record)


expire = disable
