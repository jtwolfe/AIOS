"""Privileged proposal documents: intent plus oracles (HI-08, HI-10, P4.6)."""

import json
import re
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

# P4.6 / L-20: wiki or man this turn. Infer class from the document so
# omitting a label cannot skip the gate.
_CLASS_MARKERS = (
    (
        "pacman",
        re.compile(
            r"(?i)(\bpacman\b|\bpacstrap\b|\b-syu\b|packages\.txt|"
            r"packages-drift|no-partial-upgrade)"
        ),
    ),
    (
        "systemd",
        re.compile(
            r"(?i)(\bsystemd\b|\bsystemctl\b|\.service\b|\.timer\b|"
            r"\.socket\b|\.slice\b|/etc/systemd|unit file)"
        ),
    ),
    (
        "btrfs",
        re.compile(
            r"(?i)(\bbtrfs\b|\bsnapper\b|\bsubvol(?:ume)?\b|\bfstab\b)"
        ),
    ),
    (
        "boot",
        re.compile(
            r"(?i)(\bbootctl\b|\bmkinitcpio\b|\bbootloader\b|boot-seatbelt|"
            r"\bvmlinuz\b|\binitramfs\b|\blinux-lts\b|/boot\b|"
            r"systemd-boot|\besp\b|\buki\b)"
        ),
    ),
)
_WIKI_CITE = re.compile(r"(?i)^https://wiki\.archlinux\.org/\S+$")
_MAN_WEB_CITE = re.compile(r"(?i)^https://man\.archlinux\.org/\S+$")
_MAN_CMD_CITE = re.compile(r"(?i)^man(\s+[0-9]+)?\s+[A-Za-z0-9._:-]+$")
_MAN_PAGE_CITE = re.compile(r"(?i)^[A-Za-z0-9._:-]+\([0-9][a-z]?\)$")


class ProposalSchemaError(Exception):
    """Proposal is not intent-plus-oracles, or P4.6 citations are missing."""


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


def citation_ok(item):
    text = item.strip() if isinstance(item, str) else ""
    if not text:
        return False
    return bool(
        _WIKI_CITE.match(text)
        or _MAN_WEB_CITE.match(text)
        or _MAN_CMD_CITE.match(text)
        or _MAN_PAGE_CITE.match(text)
    )


def citation_classes(intent, oracles, evidence=None):
    asked = ""
    if isinstance(intent, dict):
        asked = intent.get("asked") or ""
        if not isinstance(asked, str):
            asked = str(asked)
    parts = [asked]
    if isinstance(oracles, (list, tuple)):
        parts.extend(str(item) for item in oracles)
    ran = (evidence or {}).get("ran") if isinstance(evidence, dict) else None
    if isinstance(ran, (list, tuple)):
        parts.extend(str(item) for item in ran)
    hay = "\n".join(parts)
    return tuple(name for name, pattern in _CLASS_MARKERS if pattern.search(hay))


def _citations(value, required_classes):
    if value is None:
        items = []
    else:
        items = [item.strip() for item in _need_str_list(value, "citations", min_len=0)]
    if required_classes and not items:
        raise ProposalSchemaError(
            "citations must not be empty for %s (P4.6)"
            % ", ".join(required_classes)
        )
    for i, item in enumerate(items):
        if not citation_ok(item):
            raise ProposalSchemaError(
                "citations[%s] must be wiki.archlinux.org or man (P4.6)" % i
            )
        items[i] = item
    return items


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
    intent = _intent(data["intent"])
    evidence = _evidence(data["evidence"])
    required = citation_classes(intent, oracles, evidence)
    return {
        "id": _uuid4(data["id"]),
        "branch": _branch(data["branch"]),
        "repos": _repos(data["repos"]),
        "intent": intent,
        "oracles": oracles,
        "citations": _citations(data.get("citations"), required),
        "evidence": evidence,
    }


def load_proposal(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except OSError as exc:
        raise ProposalSchemaError("cannot read proposal: %s" % exc) from exc
    except UnicodeDecodeError as exc:
        raise ProposalSchemaError("proposal is not UTF-8: %s" % exc) from exc
    except json.JSONDecodeError as exc:
        raise ProposalSchemaError("proposal is not JSON: %s" % exc) from exc
    except RecursionError as exc:
        raise ProposalSchemaError("proposal JSON too deeply nested") from exc
    except ValueError as exc:
        raise ProposalSchemaError("proposal is not JSON: %s" % exc) from exc
    return validate_proposal(raw)
