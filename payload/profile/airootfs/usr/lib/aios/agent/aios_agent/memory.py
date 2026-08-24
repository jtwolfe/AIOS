"""Verbatim ingest. The proposing model does not choose what to keep (HI-11)."""

import datetime
import json
import os
import subprocess
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


def _git(base, args):
    env = os.environ.copy()
    env.pop("GIT_DIR", None)
    env.pop("GIT_WORK_TREE", None)
    return subprocess.run(
        ["git", "-C", base] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def _branch_name(ident):
    ident = ident.replace("/", "-")
    if len(ident) >= 8 and ident[:8].isdigit():
        date = "%s-%s-%s" % (ident[0:4], ident[4:6], ident[6:8])
    else:
        date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    short = ident.rsplit("-", 1)[-1] or ident
    return "agent/%s-memory-%s" % (date, short)


def _git_record(base, rels, ident, message):
    """Commit on agent/*, never on main (HI-03, L-03). Worktree write already happened."""
    if not rels or not os.path.isdir(base):
        return None
    for rel in rels:
        text = rel.replace("\\", "/")
        if "routines" in text.split("/") or "connectors" in text.split("/"):
            return None
    try:
        probe = _git(base, ["rev-parse", "--is-inside-work-tree"])
    except OSError:
        return None
    if probe.returncode != 0 or probe.stdout.strip() != "true":
        return None
    head = _git(base, ["rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    if head == "main" or head.endswith("/main"):
        # Leave main. Never commit there (HI-03).
        pass
    branch = _branch_name(ident)
    if not branch.startswith("agent/"):
        return None
    if head != branch:
        moved = _git(base, ["checkout", "-B", branch])
        if moved.returncode != 0:
            return None
        head = branch
    add = _git(base, ["add", "--"] + list(rels))
    if add.returncode != 0:
        return None
    commit = _git(
        base,
        [
            "-c",
            "user.name=aios",
            "-c",
            "user.email=aios@localhost",
            "commit",
            "-m",
            message,
        ],
    )
    if commit.returncode != 0:
        return head
    remotes = _git(base, ["remote"]).stdout.split()
    if "origin" in remotes and head.startswith("agent/"):
        _git(base, ["push", "origin", "refs/heads/%s" % head])
    return head


def load_record(ident, root=None):
    ident = ident if isinstance(ident, str) else str(ident or "")
    ident = ident.strip()
    if not ident:
        return None
    if os.path.isfile(ident):
        try:
            with open(ident, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            return None
        if isinstance(doc, dict):
            return doc
        return None
    base = _root(root)
    for folder in ("moments", "exchanges"):
        path = os.path.join(base, folder, ident)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict):
            return doc
    return None


def mark_outcome(ident, outcome, root=None):
    rec = load_record(ident, root=root)
    if not rec:
        return None
    rec["outcome"] = outcome
    base = _root(root)
    ident = rec.get("id") or ident
    rels = []
    for folder in ("exchanges", "moments"):
        path = os.path.join(base, folder, ident)
        if os.path.isfile(path):
            _write(path, rec)
            rels.append(os.path.join(folder, ident))
    if rels:
        _git_record(base, rels, ident, "chore(memory): accept %s" % ident)
    return rec


def ingest(record, root=None):
    """Store the exchange, evidence, and outcome. No keep/skip switch (HI-11).

    Writes the worktree, then commits on agent/<date>-memory-<id>.
    Does not merge to main (HI-03).
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
    payload.pop("Summary", None)
    payload.pop("TL;DR", None)
    payload.pop("model summary", None)
    base = _root(root)
    # Work store (routines/connectors) is git in the work tree, not memory.
    exchange = _write(os.path.join(base, "exchanges", ident), payload)
    moment = _write(os.path.join(base, "moments", ident), payload)
    rels = [
        os.path.join("exchanges", ident),
        os.path.join("moments", ident),
    ]
    branch = _git_record(
        base, rels, ident, "chore(memory): ingest %s" % ident
    )
    out = {"id": ident, "exchange": exchange, "moment": moment}
    if branch:
        out["branch"] = branch
    return out


def raise_conflict(asked, hi, root=None, ident=None):
    """HI-07: instruction vs invariant becomes a record, not a silent pass."""
    asked = asked if isinstance(asked, str) else str(asked or "")
    hi = hi if isinstance(hi, str) else str(hi or "HI-07")
    stamp, iso = _stamp()
    ident = ident or "%s-%s" % (stamp, uuid.uuid4().hex[:8])
    base = _root(root)
    path = os.path.join(base, "conflicts", ident)
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("%s\n" % hi)
        fh.write("asked: %s\n" % asked.replace("\n", " "))
        fh.write("at: %s\n" % iso)
        fh.write("id: %s\n" % ident)
    _git_record(
        base,
        [os.path.join("conflicts", ident)],
        ident,
        "chore(memory): conflict %s %s" % (hi, ident),
    )
    return path
