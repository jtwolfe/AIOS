"""Privileged proposal documents: intent plus oracles (HI-08, HI-10)."""

import json
import uuid

INTENT_SOURCES = ("human", "envelope-clause", "machine-goal", "work-intent")
KNOWN_REPOS = (
    "envelope",
    "memory",
    "skills",
    "agent",
    "checker",
    "state",
    "seeds",
)
REQUIRED_TOP = ("id", "branch", "repos", "intent", "oracles", "evidence")
ALLOWED_TOP = REQUIRED_TOP + ("citations",)
ALLOWED_INTENT = ("source", "asked", "clause")
ALLOWED_EVIDENCE = ("ran", "snapper_pre")


class ProposalSchemaError(Exception):
    """Proposal is not intent-plus-oracles, or evidence is missing."""


def _need_dict(value, what):
    if not isinstance(value, dict) or isinstance(value, list):
        raise ProposalSchemaError("%s must be an object" % what)
    return value


def _need_str(value, what, *, allow_empty=False):
    if not isinstance(value, str) or isinstance(value, bool):
        raise ProposalSchemaError("%s must be a string" % what)
    if not allow_empty and not value.strip():
        raise ProposalSchemaError("%s must be non-empty" % what)
    return value


def _need_list(value, what):
    # A JSON string is iterable; it is not an oracle set.
    if isinstance(value, (str, bytes, dict)) or not isinstance(value, list):
        raise ProposalSchemaError("%s must be a list" % what)
    return value


def _need_str_list(value, what, *, min_len=0):
    items = _need_list(value, what)
    out = []
    for i, item in enumerate(items):
        out.append(_need_str(item, "%s[%s]" % (what, i)))
    if len(out) < min_len:
        raise ProposalSchemaError("%s must not be empty" % what)
    return out


def _uuid4(value):
    raw = _need_str(value, "id")
    try:
        parsed = uuid.UUID(raw)
    except (ValueError, AttributeError, TypeError) as exc:
        raise ProposalSchemaError("id must be a UUID") from exc
    if parsed.version != 4:
        raise ProposalSchemaError("id must be a UUID version 4")
    return str(parsed)


def _branch(value):
    # L-03: agent worktrees push only refs/heads/agent/*.
    name = _need_str(value, "branch")
    if not name.startswith("agent/") or name == "agent/":
        raise ProposalSchemaError("branch must be agent/<slug> (L-03)")
    if name in ("main", "refs/heads/main") or name.endswith("/main"):
        raise ProposalSchemaError("branch must not be main (HI-03)")
    return name


def _repos(value):
    names = _need_str_list(value, "repos", min_len=1)
    unknown = [n for n in names if n not in KNOWN_REPOS]
    if unknown:
        raise ProposalSchemaError(
            "unknown repo %s (HI-12)" % ", ".join(unknown)
        )
    return names


def _intent(value):
    obj = _need_dict(value, "intent")
    extra = set(obj) - set(ALLOWED_INTENT)
    if extra:
        raise ProposalSchemaError(
            "unknown intent field %s" % ", ".join(sorted(extra))
        )
    if "source" not in obj or "asked" not in obj:
        raise ProposalSchemaError("intent requires source and asked")
    source = _need_str(obj["source"], "intent.source")
    if source not in INTENT_SOURCES:
        raise ProposalSchemaError(
            "intent.source must be one of %s" % ", ".join(INTENT_SOURCES)
        )
    asked = _need_str(obj["asked"], "intent.asked")
    clause = obj.get("clause", None)
    if clause is not None:
        clause = _need_str(clause, "intent.clause")
    return {"source": source, "asked": asked, "clause": clause}


def _oracles(value):
    if isinstance(value, (str, bytes, dict)) or not isinstance(value, list) or not value:
        raise ProposalSchemaError("oracles must be a non-empty list (HI-10)")
    return _need_str_list(value, "oracles", min_len=1)


def _evidence(value):
    # HI-08: the checker refuses missing evidence; the human is not CI.
    obj = _need_dict(value, "evidence")
    extra = set(obj) - set(ALLOWED_EVIDENCE)
    if extra:
        raise ProposalSchemaError(
            "unknown evidence field %s" % ", ".join(sorted(extra))
        )
    if "ran" not in obj:
        raise ProposalSchemaError("evidence.ran is required (HI-08)")
    ran_raw = obj["ran"]
    if (
        isinstance(ran_raw, (str, bytes, dict))
        or not isinstance(ran_raw, list)
        or not ran_raw
    ):
        raise ProposalSchemaError("evidence.ran must be a non-empty list (HI-08)")
    ran = _need_str_list(ran_raw, "evidence.ran", min_len=1)
    out = {"ran": ran}
    if "snapper_pre" in obj:
        pre = obj["snapper_pre"]
        if isinstance(pre, bool) or not isinstance(pre, int) or pre < 0:
            raise ProposalSchemaError("evidence.snapper_pre must be an int >= 0")
        out["snapper_pre"] = pre
    return out


def _citations(value):
    if value is None:
        return []
    return _need_str_list(value, "citations", min_len=0)


def validate_proposal(obj):
    """Return a normalised proposal dict, or raise ProposalSchemaError."""
    data = _need_dict(obj, "proposal")
    extra = set(data) - set(ALLOWED_TOP)
    if extra:
        raise ProposalSchemaError(
            "unknown field %s" % ", ".join(sorted(extra))
        )
    missing = [k for k in REQUIRED_TOP if k not in data]
    if missing:
        if "oracles" in missing:
            raise ProposalSchemaError("oracles missing (HI-10)")
        if "evidence" in missing:
            raise ProposalSchemaError("evidence missing (HI-08)")
        if "intent" in missing:
            raise ProposalSchemaError("intent missing (HI-10)")
        raise ProposalSchemaError("missing field %s" % ", ".join(missing))
    oracles = _oracles(data["oracles"])
    return {
        "id": _uuid4(data["id"]),
        "branch": _branch(data["branch"]),
        "repos": _repos(data["repos"]),
        "intent": _intent(data["intent"]),
        "oracles": oracles,
        "citations": _citations(data.get("citations")),
        "evidence": _evidence(data["evidence"]),
    }


def load_proposal(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except OSError as exc:
        raise ProposalSchemaError("cannot read proposal: %s" % exc) from exc
    except json.JSONDecodeError as exc:
        raise ProposalSchemaError("proposal is not JSON: %s" % exc) from exc
    return validate_proposal(raw)
