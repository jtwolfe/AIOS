"""Verbatim ingest. The proposing model does not choose what to keep (HI-11)."""

import datetime
import json
import os
import uuid

MEMORY_ROOT = "/srv/aios/memory"


def _root(root):
    return root or os.environ.get("AIOS_MEMORY") or MEMORY_ROOT


def _stamp():
    now = datetime.datetime.now(datetime.timezone.utc)
    return now.replace(microsecond=0).strftime("%Y%m%dT%H%M%SZ"), now.isoformat()


def _write(path, payload):
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o755, exist_ok=True)
    # JSON always includes "asked" so a summary cannot stand in (HI-11).
    blob = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(blob)
        fh.write("\n")
    return path


def ingest(record, root=None):
    """Store the exchange, evidence, and outcome. No keep/skip switch (HI-11).

    Writes the worktree only. Does not merge to main (HI-03).
    """
    if not isinstance(record, dict):
        record = {"asked": str(record or "")}
    asked = record.get("asked")
    if asked is None:
        asked = ""
    asked = asked if isinstance(asked, str) else str(asked)
    stamp, iso = _stamp()
    ident = record.get("id") or "%s-%s" % (stamp, uuid.uuid4().hex[:8])
    payload = dict(record)
    payload["asked"] = asked
    payload.setdefault("operator", asked)
    payload.setdefault("human", asked)
    payload.setdefault("source", "human")
    payload["at"] = payload.get("at") or iso
    payload["id"] = ident
    # Never persist a summary as the only record of the turn.
    payload.pop("Summary", None)
    payload.pop("TL;DR", None)
    payload.pop("model summary", None)
    base = _root(root)
    exchange = _write(os.path.join(base, "exchanges", ident), payload)
    moment = _write(os.path.join(base, "moments", ident), payload)
    return {"id": ident, "exchange": exchange, "moment": moment}


def raise_conflict(asked, hi, root=None, ident=None):
    """HI-07: instruction vs invariant becomes a record, not a silent pass."""
    asked = asked if isinstance(asked, str) else str(asked or "")
    hi = hi if isinstance(hi, str) else str(hi or "HI-07")
    stamp, iso = _stamp()
    ident = ident or "%s-%s" % (stamp, uuid.uuid4().hex[:8])
    base = _root(root)
    path = os.path.join(base, "conflicts", ident)
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    # Line-oriented so hi-07-conflicts-raised.sh can grep HI-xx.
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("%s\n" % hi)
        fh.write("asked: %s\n" % asked.replace("\n", " "))
        fh.write("at: %s\n" % iso)
        fh.write("id: %s\n" % ident)
    return path
