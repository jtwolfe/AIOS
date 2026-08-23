"""Machine goals: idle default, events, stall pause (L-21)."""

import json
import os
import sys
import uuid

from memory import ingest

# L-21: same oracle-gap fingerprint twice pauses. Do not rewrite oracles to pass
# (HI-08, HI-10). A rotating gap hits the round cap instead of self-driving.
SAME_GAP = 2
MAX_ROUNDS = 8
MAX_EVENTS = 1

GOALS_PATH = "/srv/aios/state/goals.json"
NOTIFY_DIR = "/srv/aios/state/notify"
BRAKE_PATH = "/srv/aios/state/brake"
ANSWERS_PATH = "/srv/aios/state/bootstrap-in-progress/answers.json"
ENVELOPE_WORK = "/srv/aios/envelope/work-runtime.md"

KNOWN_STATUS = frozenset(("idle", "paused", "waiting-accept", "verify"))
KNOWN_GOALS = frozenset(
    ("event-repair", "sysupgrade", "reconstruct", "work-runtime")
)
EVENT_KINDS = frozenset(
    (
        "unit-failed",
        "hi-failed",
        "packages-drift",
        "sysupgrade",
        "infra",
        "gap",
        "work-runtime",
    )
)

# Named checker scripts already in the tree. Never `true` (HI-08, HI-10).
_HI_ORACLE = {
    "HI-01": "policy/hi-01-git-source.sh",
    "HI-02": "policy/hi-02-split.sh",
    "HI-03": "policy/hi-03-no-proposer-main.sh",
    "HI-04": "policy/hi-04-no-unsigned-root.sh",
    "HI-05": "policy/hi-05-human-authority.sh",
    "HI-06": "policy/hi-06-seatbelts.sh",
    "HI-07": "policy/hi-07-conflicts-raised.sh",
    "HI-08": "policy/hi-08-human-not-ci.sh",
    "HI-09": "policy/hi-09-no-undeclared-state.sh",
    "HI-10": "policy/hi-10-oracles-required.sh",
    "HI-11": "policy/hi-11-verbatim-memory.sh",
    "HI-12": "policy/hi-12-named-daemons.sh",
    "HI-13": "policy/hi-13-work-slice.sh",
    "HI-14": "policy/hi-14-failure-handoff.sh",
    "HI-15": "policy/hi-15-work-default-off.sh",
    "HI-16": "policy/hi-16-os-privilege.sh",
    "HI-17": "policy/hi-17-seeds-local.sh",
}

_KIND_ORACLES = {
    "unit-failed": ("policy/hi-14-failure-handoff.sh",),
    "packages-drift": ("policy/packages-drift.sh",),
    "sysupgrade": (
        "policy/no-partial-upgrade.sh",
        "policy/boot-seatbelt.sh",
        "policy/packages-drift.sh",
    ),
    "reconstruct": ("policy/boot-seatbelt.sh",),
}

# L-19: stall offers TUI rollback of that window. This uid does not enact it.
ROLLBACK = {
    "action": "rollback",
    "view": "snapper",
    "window": "previous",
    "clause": "L-19",
}

_INFRA_TOKENS = (
    "infra",
    "mirror",
    "disk",
    "api",
    "enospc",
    "no space",
    "network unreachable",
    "connection refused",
)


class GoalRun:
    def __init__(
        self,
        status,
        paused,
        proposal,
        notify,
        rollback,
        reason,
        hi=None,
        memory_paths=None,
        oracles=None,
        invented=False,
    ):
        self.status = status
        self.paused = paused
        self.proposal = proposal
        self.notify = notify
        self.rollback = rollback
        self.reason = reason
        self.hi = hi
        self.memory_paths = memory_paths or {}
        self.oracles = list(oracles or [])
        # L-21: this runner does not invent motives or oracles to pass.
        self.invented = bool(invented)

    def as_dict(self):
        return {
            "status": self.status,
            "paused": self.paused,
            "proposal": self.proposal,
            "notify": self.notify,
            "rollback": self.rollback,
            "reason": self.reason,
            "hi": self.hi,
            "oracles": self.oracles,
            "invented": self.invented,
            "work_runtime": False,
            "memory": self.memory_paths,
            "outcome": "pause" if self.paused else self.status,
        }


def _goals_path(path=None):
    return path or os.environ.get("AIOS_GOALS") or GOALS_PATH


def _notify_dir(path=None):
    return path or os.environ.get("AIOS_NOTIFY") or NOTIFY_DIR


def _brake_path(path=None):
    return path or os.environ.get("AIOS_BRAKE") or BRAKE_PATH


def _answers_path(path=None):
    return path or os.environ.get("AIOS_ANSWERS") or ANSWERS_PATH


def _envelope_work(path=None):
    return path or os.environ.get("AIOS_ENVELOPE_WORK") or ENVELOPE_WORK


def _idle_doc():
    return {
        "status": "idle",
        "declared": [],
        "last_gap": None,
        "gap_count": 0,
        "rounds": 0,
        "proposal": None,
        "notify": None,
        "rollback": None,
        "reason": "idle is the default (L-21)",
        "hi": "L-21",
    }


def _paused_doc(reason, hi="L-21"):
    return {
        "status": "paused",
        "declared": [],
        "last_gap": None,
        "gap_count": 0,
        "rounds": 0,
        "proposal": None,
        "notify": None,
        "rollback": None,
        "reason": reason,
        "hi": hi,
    }


def _write_json(path, doc):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, mode=0o755, exist_ok=True)
    blob = json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=True)
    tmp = "%s.tmp" % path
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(blob)
        fh.write("\n")
    os.replace(tmp, path)
    return path


def save_state(doc, path=None):
    """Write operational state. Does not commit to main (HI-03)."""
    return _write_json(_goals_path(path), doc)


def load_state(path=None):
    """Missing file is idle. Unknown/corrupt restores paused (L-21)."""
    path = _goals_path(path)
    if not os.path.isfile(path):
        return _idle_doc(), False
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        doc = _paused_doc("unreadable goals file restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    if not raw.strip():
        doc = _paused_doc("empty goals file restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    try:
        parsed = json.loads(raw)
    except ValueError:
        doc = _paused_doc("corrupt goals file restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    if not isinstance(parsed, dict):
        doc = _paused_doc("corrupt goals file restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    # Unknown keys that look like self-driving are unknown state (L-21).
    if parsed.get("self_driving") or parsed.get("auto_propose"):
        doc = _paused_doc("unknown goal state restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    status = parsed.get("status")
    if status not in KNOWN_STATUS:
        doc = _paused_doc("unknown goal status restores paused (L-21)")
        save_state(doc, path)
        return doc, True
    declared = parsed.get("declared")
    if declared is None:
        declared = []
    if not isinstance(declared, list):
        doc = _paused_doc("corrupt declared goals restore paused (L-21)")
        save_state(doc, path)
        return doc, True
    for name in declared:
        if name not in KNOWN_GOALS:
            doc = _paused_doc(
                "unknown goal %s restores paused (L-21)" % name
            )
            save_state(doc, path)
            return doc, True
    parsed["declared"] = declared
    parsed.setdefault("last_gap", None)
    parsed.setdefault("gap_count", 0)
    parsed.setdefault("rounds", 0)
    parsed.setdefault("proposal", None)
    return parsed, False


def work_runtime_yes(answers=None, clause=None):
    """Skip is not a yes (HI-15)."""
    answers = _answers_path(answers)
    if os.path.isfile(answers):
        try:
            with open(answers, "r", encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            doc = None
        if isinstance(doc, dict) and doc.get("accepted") is True:
            if doc.get("work_runtime") is True:
                return True
    clause = _envelope_work(clause)
    if os.path.isfile(clause):
        try:
            with open(clause, "r", encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            text = ""
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if stripped.lower() in (
                "enabled: true",
                "enabled: yes",
                "enabled: 1",
                "enabled = true",
            ):
                return True
    return False


def _clause_id(event):
    raw = event.get("clause") or event.get("hi") or ""
    raw = raw if isinstance(raw, str) else str(raw)
    token = raw.strip().split()[0] if raw.strip() else ""
    token = token.rstrip(".,;:")
    if token.startswith("HI-") or token.startswith("L-"):
        return token
    return ""


def _clean_oracles(raw):
    if not isinstance(raw, list):
        return []
    out = []
    for item in raw:
        text = item if isinstance(item, str) else str(item or "")
        text = text.strip()
        if not text:
            continue
        # HI-08/HI-10: `true` is not an oracle.
        if text == "true" or text == "/bin/true":
            continue
        out.append(text)
    return out


def _named_oracles(event):
    kind = event.get("kind") or ""
    if kind == "hi-failed":
        named = _HI_ORACLE.get(_clause_id(event))
        return [named] if named else []
    listed = _KIND_ORACLES.get(kind) or ()
    return list(listed)


def _oracles_for(event, state):
    # Stall path keeps the original set. Do not rewrite to pass (L-21).
    existing = []
    if state:
        prop = state.get("proposal") or {}
        existing = _clean_oracles(prop.get("oracles"))
    if existing:
        return existing
    supplied = _clean_oracles(event.get("oracles"))
    if supplied:
        return supplied
    return _named_oracles(event)


def _fingerprint(event, state):
    if event.get("gap"):
        return str(event.get("gap"))
    oracles = _oracles_for(event, state)
    output = event.get("output") or event.get("stderr") or ""
    kind = event.get("kind") or ""
    unit = event.get("unit") or event.get("executable") or ""
    return "%s|%s|%s|%s" % (kind, unit, ",".join(oracles), output)


def _is_infra(event):
    kind = (event.get("kind") or "").lower()
    if kind in ("infra", "infra-error"):
        return True
    blob = " ".join(
        [
            kind,
            str(event.get("reason") or ""),
            str(event.get("error") or ""),
        ]
    ).lower()
    for token in _INFRA_TOKENS:
        if token in blob:
            return True
    return False


def _normalize_event(raw):
    if not isinstance(raw, dict):
        return None
    kind = raw.get("kind")
    if not kind:
        if raw.get("unit") or raw.get("executable"):
            kind = "unit-failed"
        elif _is_infra(raw):
            kind = "infra"
        else:
            # Unknown blob is not a motive (L-21).
            return None
    kind = kind if isinstance(kind, str) else str(kind)
    kind = kind.strip().lower().replace("_", "-")
    event = dict(raw)
    event["kind"] = kind
    if kind not in EVENT_KINDS and not _is_infra(event):
        return None
    return event


def _hi14_payload(event, clause):
    unit = event.get("unit") or event.get("executable") or "aios-agent.service"
    journal = event.get("journal") or event.get("journal_slice") or ""
    commit = event.get("commit") or event.get("state_commit") or ""
    snapper = event.get("snapper")
    if snapper is None:
        snapper = event.get("snapper_id")
    if snapper is None:
        snapper = 0
    return {
        "unit": unit,
        "executable": event.get("executable") or unit,
        "journal": journal,
        "journal_slice": journal,
        "commit": commit,
        "state_commit": commit,
        "snapper": snapper,
        "snapper_id": snapper,
        "clause": clause,
    }


def _write_notify(payload, notify_dir=None):
    folder = _notify_dir(notify_dir)
    os.makedirs(folder, mode=0o755, exist_ok=True)
    ident = uuid.uuid4().hex[:12]
    path = os.path.join(folder, ident)
    _write_json(path, payload)
    out = dict(payload)
    out["path"] = path
    return out


def _remember(record, memory_root):
    rec = dict(record)
    rec.setdefault("source", "machine-goal")
    rec.setdefault("asked", rec.get("reason") or "machine-goal")
    rec.setdefault("operator", rec["asked"])
    rec.setdefault("human", rec["asked"])
    rec["invented"] = False
    return ingest(rec, root=memory_root)


def _proposal(event, oracles, asked, clause):
    kind = event.get("kind") if event else "sysupgrade"
    plan = {
        "intent": {
            "source": "machine-goal",
            "asked": asked,
            "clause": clause,
        },
        "oracles": list(oracles),
        "citations": [],
        # L-20: plan is the only write. Accept is a later invocation.
        "enact": "not-while-planning",
        "skills": ["none"],
    }
    if kind in ("sysupgrade", "packages-drift"):
        # Live -Syu is P4.5. linux-lts remains an oracle, not a hope (HI-06).
        plan["syu"] = "gated-p45"
        plan["intent"]["asked"] = asked
    return plan


def _asked_for(event):
    kind = (event or {}).get("kind") or "sysupgrade"
    unit = (event or {}).get("unit") or (event or {}).get("executable") or ""
    if kind == "unit-failed":
        return "repair unit-failed %s" % (unit or "unit")
    if kind == "hi-failed":
        return "repair %s" % (_clause_id(event) or "HI")
    if kind == "packages-drift":
        return "repair packages.txt drift (bounded -Syu, not mixed)"
    if kind == "sysupgrade":
        return "bounded sysupgrade window; linux-lts remains bootable"
    return "machine-goal %s" % kind


def _run_from_state(
    state,
    paused,
    reason,
    hi,
    notify=None,
    rollback=None,
    memory_root=None,
    extra=None,
    remember=True,
):
    proposal = state.get("proposal")
    oracles = []
    if proposal and isinstance(proposal, dict):
        oracles = list(proposal.get("oracles") or [])
    paths = {}
    if remember:
        record = {
            "asked": reason,
            "source": "machine-goal",
            "triage": "machine-goal",
            "plan": proposal,
            "accept": False,
            "enact": "skipped",
            "outcome": "pause" if paused else state.get("status"),
            "paused": paused,
            "hi": hi,
            "reason": reason,
        }
        if extra:
            record.update(extra)
        paths = _remember(record, memory_root)
    return GoalRun(
        state.get("status"),
        paused,
        proposal,
        notify,
        rollback,
        reason,
        hi=hi,
        memory_paths=paths,
        oracles=oracles,
        invented=False,
    )


def tick(
    events=None,
    path=None,
    notify_dir=None,
    memory_root=None,
    brake_path=None,
):
    """One machine-goal step. Empty events invent nothing (L-21)."""
    path = _goals_path(path)
    state, corrupt = load_state(path)
    events = events or []
    if not isinstance(events, list):
        events = [events]

    if corrupt:
        notify = None
        run = _run_from_state(
            state,
            True,
            state.get("reason") or "unknown goal state restores paused (L-21)",
            "L-21",
            notify=notify,
            rollback=None,
            memory_root=memory_root,
        )
        run.status = "paused"
        run.paused = True
        run.proposal = None
        return run

    if os.path.exists(_brake_path(brake_path)):
        # L-12: human brake. Do not invent a repair around it.
        return GoalRun(
            state.get("status") or "idle",
            True,
            None,
            None,
            None,
            "enact frozen (L-12)",
            hi="L-12",
            invented=False,
        )

    if state.get("status") == "paused":
        # Same-gap stall holds. No third attempt (L-21). Do not ingest again.
        oracles = []
        prop = state.get("proposal")
        if prop and isinstance(prop, dict):
            oracles = list(prop.get("oracles") or [])
        return GoalRun(
            "paused",
            True,
            prop,
            state.get("notify"),
            state.get("rollback"),
            state.get("reason") or "paused (L-21); no third attempt",
            hi=state.get("hi") or "L-21",
            oracles=oracles,
            invented=False,
        )

    normalized = []
    for raw in events:
        event = _normalize_event(raw)
        if event is not None:
            normalized.append(event)
    normalized = normalized[:MAX_EVENTS]

    for event in normalized:
        if event.get("kind") == "work-runtime":
            reason = "work runtime stays off until an explicit yes (HI-15)"
            if work_runtime_yes():
                reason = "work-runtime synthesis is P8.1; not this loop (HI-15)"
            state["status"] = "idle"
            state["proposal"] = None
            state["reason"] = reason
            state["hi"] = "HI-15"
            save_state(state, path)
            return _run_from_state(
                state, False, reason, "HI-15", memory_root=memory_root
            )

    for event in normalized:
        if _is_infra(event):
            reason = "infra error pauses (L-21): %s" % (
                event.get("reason") or event.get("kind") or "infra"
            )
            payload = _hi14_payload(event, "L-21")
            notify = _write_notify(payload, notify_dir)
            state["status"] = "paused"
            state["reason"] = reason
            state["hi"] = "L-21"
            state["notify"] = notify
            state["rollback"] = dict(ROLLBACK)
            save_state(state, path)
            run = _run_from_state(
                state,
                True,
                reason,
                "L-21",
                notify=notify,
                rollback=state["rollback"],
                memory_root=memory_root,
            )
            run.proposal = None
            return run

    for event in normalized:
        if event.get("kind") == "gap" or event.get("gap"):
            fp = _fingerprint(event, state)
            last = state.get("last_gap")
            if last == fp:
                count = int(state.get("gap_count") or 0) + 1
            else:
                count = 1
            rounds = int(state.get("rounds") or 0) + 1
            state["last_gap"] = fp
            state["gap_count"] = count
            state["rounds"] = rounds
            # Keep original oracles. Ignore a replacement set on this event.
            oracles = _oracles_for(event, state)
            if state.get("proposal") and isinstance(state.get("proposal"), dict):
                state["proposal"]["oracles"] = oracles
            if count >= SAME_GAP or rounds >= MAX_ROUNDS:
                reason = "same-gap twice pauses (L-21); no third attempt"
                if rounds >= MAX_ROUNDS and count < SAME_GAP:
                    reason = "round cap pauses (L-21)"
                payload = _hi14_payload(event, "L-21")
                notify = _write_notify(payload, notify_dir)
                state["status"] = "paused"
                state["reason"] = reason
                state["hi"] = "L-21"
                state["notify"] = notify
                state["rollback"] = dict(ROLLBACK)
                save_state(state, path)
                return _run_from_state(
                    state,
                    True,
                    reason,
                    "L-21",
                    notify=notify,
                    rollback=state["rollback"],
                    memory_root=memory_root,
                )
            state["reason"] = "oracle gap recorded (L-21); one retry remains"
            state["hi"] = "L-21"
            save_state(state, path)
            return _run_from_state(
                state,
                False,
                state["reason"],
                "L-21",
                memory_root=memory_root,
            )

    declared = [name for name in (state.get("declared") or []) if name in KNOWN_GOALS]
    if "work-runtime" in declared and not work_runtime_yes():
        declared = [name for name in declared if name != "work-runtime"]
        state["declared"] = declared

    if not normalized:
        if state.get("status") == "waiting-accept" and state.get("proposal"):
            # Restart resumes the plan. It does not invent a new one (L-21).
            return _run_from_state(
                state,
                False,
                "resume waiting-accept (L-21)",
                state.get("hi") or "L-21",
                memory_root=memory_root,
            )
        if "sysupgrade" in declared:
            event = {"kind": "sysupgrade"}
            return _plan_event(
                event, state, path, notify_dir, memory_root
            )
        # Reconstruct without an event is holding seatbelts, not a proposal.
        state["status"] = "idle"
        state["proposal"] = None
        state["reason"] = "idle is the default (L-21)"
        state["hi"] = "L-21"
        if os.path.isfile(path) or declared:
            save_state(state, path)
        return GoalRun(
            "idle",
            False,
            None,
            None,
            None,
            state["reason"],
            hi="L-21",
            invented=False,
        )

    event = normalized[0]
    if event.get("kind") in (
        "unit-failed",
        "hi-failed",
        "packages-drift",
        "sysupgrade",
    ):
        return _plan_event(event, state, path, notify_dir, memory_root)

    # Unknown remainder: idle. Do not invent motives (L-21).
    state["status"] = "idle"
    state["reason"] = "idle is the default (L-21)"
    state["hi"] = "L-21"
    if os.path.isfile(path):
        save_state(state, path)
    return GoalRun(
        "idle", False, None, None, None, state["reason"], hi="L-21", invented=False
    )


def _plan_event(event, state, path, notify_dir, memory_root):
    rounds = int(state.get("rounds") or 0)
    if rounds >= MAX_ROUNDS:
        reason = "round cap pauses (L-21)"
        payload = _hi14_payload(event, "L-21")
        notify = _write_notify(payload, notify_dir)
        state["status"] = "paused"
        state["reason"] = reason
        state["hi"] = "L-21"
        state["notify"] = notify
        state["rollback"] = dict(ROLLBACK)
        save_state(state, path)
        return _run_from_state(
            state,
            True,
            reason,
            "L-21",
            notify=notify,
            rollback=state["rollback"],
            memory_root=memory_root,
        )
    oracles = _oracles_for(event, state)
    if not oracles:
        # No oracle set, no enactment (HI-10). Do not invent one to pass.
        reason = "no oracle set, no enactment (HI-10)"
        state["status"] = "paused"
        state["reason"] = reason
        state["hi"] = "HI-10"
        state["proposal"] = None
        save_state(state, path)
        return _run_from_state(
            state, True, reason, "HI-10", memory_root=memory_root
        )
    clause = _clause_id(event) or {
        "unit-failed": "HI-14",
        "packages-drift": "HI-01",
        "sysupgrade": "L-19",
        "hi-failed": "HI-09",
    }.get(event.get("kind"), "L-21")
    asked = _asked_for(event)
    plan = _proposal(event, oracles, asked, clause)
    state["status"] = "waiting-accept"
    state["proposal"] = plan
    state["rounds"] = rounds + 1
    state["reason"] = asked
    state["hi"] = "L-21"
    state["notify"] = None
    state["rollback"] = None
    save_state(state, path)
    return _run_from_state(
        state, False, asked, "L-21", memory_root=memory_root
    )


def _events_from_arg(src):
    src = src if isinstance(src, str) else str(src or "")
    src = src.strip()
    if not src:
        return []
    raw = src
    if src == "-":
        raw = sys.stdin.read()
    elif os.path.isfile(src):
        with open(src, "r", encoding="utf-8") as fh:
            raw = fh.read()
    if not raw.strip():
        return []
    try:
        obj = json.loads(raw)
    except ValueError:
        return [{"kind": src}]
    if obj is None:
        return []
    if isinstance(obj, list):
        return [item for item in obj if isinstance(item, dict)]
    if isinstance(obj, dict):
        return [obj]
    return []


def cmd_goals(argv):
    args = list(argv)
    if args and args[0] == "gap":
        fp = " ".join(args[1:]).strip() or "gap"
        run = tick([{"kind": "gap", "gap": fp}])
    elif args and args[0] == "infra":
        kind = " ".join(args[1:]).strip() or "infra"
        run = tick([{"kind": "infra", "reason": kind}])
    elif not args or args[0] in ("tick", "status", "run"):
        src = " ".join(args[1:]).strip() if args and args[0] != "status" else ""
        if args and args[0] == "status":
            src = ""
        run = tick(_events_from_arg(src) if src else [])
    else:
        run = tick(_events_from_arg(" ".join(args)))
    sys.stdout.write(json.dumps(run.as_dict(), indent=2, sort_keys=True))
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 1 if run.paused else 0
