"""Harness B turn loop (P4.3). No-arg main.serve stays idle (L-21)."""

import json
import os
import re
import subprocess
import sys

from memory import ingest, load_record, mark_outcome, raise_conflict
from skills import match as match_skills
from triage import classify

# talk → update conditions → plan → accept → enact once → verify → remember or pause
STAGES = (
    "talk",
    "update-conditions",
    "plan",
    "accept",
    "enact",
    "verify",
    "remember",
)


class Turn:
    def __init__(
        self,
        asked,
        triage,
        skills,
        plan,
        accepted,
        enacted,
        evidence,
        outcome,
        paused,
        reply,
        memory_paths,
        hi=None,
    ):
        self.asked = asked
        self.triage = triage
        self.skills = skills
        self.plan = plan
        self.accepted = accepted
        self.enacted = enacted
        self.evidence = evidence
        self.outcome = outcome
        self.paused = paused
        self.reply = reply
        self.memory_paths = memory_paths
        self.hi = hi
        self.stages = list(STAGES)

    def as_dict(self):
        names = [skill.name for skill in self.skills] or ["none"]
        return {
            "asked": self.asked,
            "triage": self.triage.kind,
            "hi": self.hi,
            "skills": names,
            "plan": self.plan,
            "accepted": self.accepted,
            "enact": self.enacted,
            "evidence": self.evidence,
            "outcome": self.outcome,
            "paused": self.paused,
            "reply": self.reply,
            "memory": self.memory_paths,
            "stages": self.stages,
        }


class _Named:
    def __init__(self, name):
        self.name = name
        self.body = ""
        self.references = []


# Same markers as checker/aios_checker/schema.py (HI-02: do not import the checker).
# '-' is non-word, so no leading word-boundary before -syu.
_CLASS_MARKERS = (
    (
        "pacman",
        re.compile(
            r"(?i)(\bpacman\b|\bpacstrap\b|-syu\b|packages\.txt|"
            r"\binstall\s+\S+|as the system editor)"
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
            r"(?i)(\bbootctl\b|\bmkinitcpio\b|\bbootloader\b|"
            r"\bvmlinuz\b|\binitramfs\b|\blinux-lts\b|/boot\b|"
            r"systemd-boot|\besp\b|\buki\b)"
        ),
    ),
)
# Whole-token seatbelt path, not a policy/ substring of a command line.
_POLICY_ORACLE = re.compile(r"(?i)^(policy/[\w./-]+|[\w./-]+\.sh)$")
_WIKI_CITE = re.compile(r"(?i)^https://wiki\.archlinux\.org/\S+$")
_MAN_WEB_CITE = re.compile(r"(?i)^https://man\.archlinux\.org/\S+$")
_MAN_CMD_CITE = re.compile(r"(?i)^man(\s+[0-9]+)?\s+[A-Za-z0-9._:-]+$")
_MAN_PAGE_CITE = re.compile(r"(?i)^[A-Za-z0-9._:-]+\([0-9][a-z]?\)$")


def _items_from_reply(reply, field, prefixes):
    text = reply if isinstance(reply, str) else str(reply or "")
    try:
        obj = json.loads(text)
    except ValueError:
        obj = None
    if isinstance(obj, dict):
        raw = obj.get(field)
        if isinstance(raw, list):
            return [str(item).strip() for item in raw if str(item).strip()]
    found = []
    for line in text.splitlines():
        stripped = line.strip()
        lower = stripped.lower()
        for prefix in prefixes:
            if not lower.startswith(prefix):
                continue
            rest = stripped[len(prefix) :]
            # "man:" is a label; "manager:" is not. "wiki:https://..." is a URL.
            if rest.startswith("https://") or rest.startswith("http://"):
                item = rest.strip()
            elif not rest or rest[0].isspace():
                item = rest.strip()
            else:
                continue
            if item:
                found.append(item)
            break
    return found


def _oracles_from_reply(reply):
    return _items_from_reply(reply, "oracles", ("oracle:",))


def _citations_from_reply(reply):
    return _items_from_reply(reply, "citations", ("citation:", "wiki:", "man:"))


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


def _oracle_class_text(item):
    text = str(item).strip()
    if not text or _POLICY_ORACLE.match(text):
        return ""
    return text


def citation_classes(asked, oracles):
    parts = [asked if isinstance(asked, str) else str(asked or "")]
    if isinstance(oracles, (list, tuple)):
        for item in oracles:
            text = _oracle_class_text(item)
            if text:
                parts.append(text)
    hay = "\n".join(parts)
    return tuple(name for name, pattern in _CLASS_MARKERS if pattern.search(hay))


def citations_usable(items, required_classes):
    cleaned = [str(item).strip() for item in (items or []) if str(item).strip()]
    if required_classes and not cleaned:
        return False
    return all(citation_ok(item) for item in cleaned)


def _messages(asked, skills, triage):
    from goals import work_runtime_yes

    if work_runtime_yes():
        wr_line = (
            "Work-runtime synthesis is a machine goal via enact after "
            "accept. Do not mutate live while planning (L-20, HI-15)."
        )
    else:
        wr_line = "Do not synthesise the work runtime (HI-15)."
    parts = [
        "You are the AIOS privileged proposer. Quote HI by id.",
        "Do not merge to main (HI-03). Do not force-push.",
        wr_line,
        "Do not decide what memory is worth keeping (HI-11).",
        "Research is plan-only. Do not enact while planning (L-20).",
        "Wiki/man this turn for pacman/systemd/btrfs/boot; empty citations are rejected (P4.6).",
        "triage: %s" % triage.kind,
        "asked: %s" % asked,
    ]
    if skills:
        for skill in skills:
            parts.append("skill %s:\n%s" % (skill.name, skill.body))
            for name, body in skill.references:
                parts.append("skill %s reference %s:\n%s" % (skill.name, name, body))
    else:
        parts.append("no skill matched; do not invent policy")
    return [{"role": "user", "content": "\n\n".join(parts)}]


def _enact_once(enact_bin):
    # One window. Live -Syu is P4.5; tests inject AIOS_ENACT.
    path = enact_bin if enact_bin is not None else os.environ.get("AIOS_ENACT")
    if not path:
        return "gated-p45", [], None
    try:
        proc = subprocess.run(
            [path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as exc:
        return "failed", [], "enact failed: %s" % exc
    ran = [path]
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "enact failed").strip()
        return "failed", ran, err
    return "once", ran, None


def _complete(provider, asked, skills, triage):
    if provider is None:
        from provider.base import load

        provider = load()
    return provider.complete(_messages(asked, skills, triage))


def _remember(
    asked,
    triage,
    skills,
    plan,
    accept,
    enacted,
    evidence,
    outcome,
    paused,
    reply,
    hi,
    memory_root,
    extra=None,
):
    names = [skill.name for skill in skills] or ["none"]
    class_name = names[0] if names and names[0] != "none" else triage.kind
    rec = {
        "asked": asked,
        "operator": asked,
        "human": asked,
        "triage": triage.kind,
        "hi": hi,
        "skills": names,
        "class": class_name,
        "plan": plan,
        "accept": accept,
        "enact": enacted,
        "evidence": evidence,
        "outcome": outcome,
        "paused": paused,
        "reply": reply,
        "source": "human",
    }
    if extra:
        rec.update(extra)
    return ingest(rec, root=memory_root)


def _skills_from_rec(rec):
    names = rec.get("skills") or []
    out = []
    for name in names:
        if name and name != "none":
            out.append(_Named(name))
    return out


def accept_plan(ident, memory_root=None, skills_root=None, enact_bin=None, provider=None):
    # Accept that stored plan (L-20). Do not generate a new one this invocation.
    rec = load_record(ident, root=memory_root)
    paused = False
    enacted = "skipped"
    evidence = {"ran": []}
    reply = ""
    hi = None
    if not rec or rec.get("outcome") != "waiting-accept":
        asked = (rec or {}).get("asked") or ident
        triage = classify(asked) if asked else classify("")
        loaded = _skills_from_rec(rec or {})
        plan = (rec or {}).get("plan")
        outcome = "no-plan"
        paused = True
        paths = _remember(
            asked,
            triage,
            loaded,
            plan,
            False,
            enacted,
            evidence,
            outcome,
            paused,
            "no stored plan to accept",
            hi,
            memory_root,
            extra={"plan_id": ident},
        )
        return Turn(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    asked = rec.get("asked") or ""
    plan = rec.get("plan") if isinstance(rec.get("plan"), dict) else {}
    oracles = plan.get("oracles") or []
    citations = plan.get("citations") if isinstance(plan.get("citations"), list) else []
    triage = classify(asked)
    loaded = _skills_from_rec(rec)
    if not loaded:
        loaded = match_skills(asked, root=skills_root)
    reply = rec.get("reply") or ""
    hi = rec.get("hi")
    required = citation_classes(asked, oracles)

    if not oracles:
        enacted = "refused-hi-10"
        paused = True
        outcome = "pause"
        reply = (reply + "\n" if reply else "") + "no oracle set, no enactment (HI-10)"
        paths = _remember(
            asked,
            triage,
            loaded,
            plan,
            True,
            enacted,
            evidence,
            outcome,
            paused,
            reply,
            hi,
            memory_root,
            extra={"plan_id": rec.get("id") or ident},
        )
        return Turn(
            asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    if not citations_usable(citations, required):
        # L-20: wiki/man this turn in the plan (asked + commands, same as schema).
        enacted = "refused-p46"
        paused = True
        outcome = "pause"
        kind = ", ".join(required) if required else "wiki/man"
        reply = (reply + "\n" if reply else "") + (
            "missing or invalid wiki/man citations on %s, no enactment (P4.6)"
            % kind
        )
        paths = _remember(
            asked,
            triage,
            loaded,
            plan,
            True,
            enacted,
            evidence,
            outcome,
            paused,
            reply,
            hi,
            memory_root,
            extra={"plan_id": rec.get("id") or ident},
        )
        return Turn(
            asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    enacted, ran, err = _enact_once(enact_bin)
    evidence = {"ran": ran}
    if err:
        paused = True
        outcome = "pause"
        reply = (reply + "\n" if reply else "") + err
    elif enacted == "once":
        # Checker is a different process (HI-02). This uid does not merge (HI-03).
        outcome = "verify"
        mark_outcome(rec.get("id") or ident, "accepted", root=memory_root)
    elif enacted == "gated-p45":
        # Not a successful moment. Must not count toward SKILL.md (HI-11).
        outcome = "gated-p45"
        paused = True
    else:
        outcome = enacted
        paused = True

    paths = _remember(
        asked,
        triage,
        loaded,
        plan,
        True,
        enacted,
        evidence,
        outcome,
        paused,
        reply,
        hi,
        memory_root,
        extra={"plan_id": rec.get("id") or ident},
    )
    return Turn(
        asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, paths, hi=hi
    )


def run_turn(
    asked,
    accept=False,
    accept_id=None,
    provider=None,
    memory_root=None,
    skills_root=None,
    enact_bin=None,
):
    ident = (accept_id if accept_id is not None else "") 
    ident = ident if isinstance(ident, str) else str(ident)
    ident = ident.strip()
    if accept or ident:
        return accept_plan(
            ident or (asked if isinstance(asked, str) else str(asked or "")).strip(),
            memory_root=memory_root,
            skills_root=skills_root,
            enact_bin=enact_bin,
            provider=provider,
        )

    asked = asked if isinstance(asked, str) else str(asked or "")
    paused = False
    reply = ""
    plan = None
    enacted = "skipped"
    evidence = {"ran": []}
    outcome = "idle"
    loaded = []
    hi = None

    triage = classify(asked)

    if triage.kind == "conflict":
        hi = triage.hi
        raise_conflict(asked, triage.hi, root=memory_root)
        reply = "raised %s" % triage.hi
        outcome = "conflict"
        paused = True
        paths = _remember(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, hi, memory_root
        )
        return Turn(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    if triage.kind == "empty":
        paths = _remember(
            asked, triage, loaded, plan, False, enacted, evidence, "idle", False, reply, hi, memory_root
        )
        return Turn(
            asked, triage, loaded, plan, False, enacted, evidence, "idle", False, reply, paths, hi=hi
        )

    loaded = match_skills(asked, root=skills_root)
    skill_note = [skill.name for skill in loaded] if loaded else ["none"]

    if triage.kind in ("question", "talk", "privileged"):
        try:
            reply = _complete(provider, asked, loaded, triage)
        except Exception as exc:
            reply = ""
            paused = True
            outcome = "pause"
            err = str(exc)
            plan = {
                "intent": {"source": "human", "asked": asked},
                "oracles": [],
                "skills": skill_note,
                "enact": "not-while-planning",
            }
            paths = _remember(
                asked,
                triage,
                loaded,
                plan,
                False,
                enacted,
                evidence,
                outcome,
                paused,
                err,
                hi,
                memory_root,
            )
            return Turn(
                asked,
                triage,
                loaded,
                plan,
                False,
                enacted,
                evidence,
                outcome,
                paused,
                err,
                paths,
                hi=hi,
            )

    if triage.kind in ("question", "talk"):
        plan = {"enact": "not-a-build", "skills": skill_note, "oracles": []}
        outcome = "answered" if triage.kind == "question" else "recorded"
        paths = _remember(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, hi, memory_root
        )
        return Turn(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    # Privileged: plan (docs) is the only write this invocation (L-20).
    oracles = _oracles_from_reply(reply)
    citations = _citations_from_reply(reply)
    plan = {
        "intent": {"source": "human", "asked": asked},
        "oracles": oracles,
        "skills": skill_note,
        "enact": "not-while-planning",
        "citations": citations,
    }
    outcome = "waiting-accept"
    paths = _remember(
        asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, hi, memory_root
    )
    return Turn(
        asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, paths, hi=hi
    )


def cmd_turn(argv):
    args = list(argv)
    if args and args[0] == "--accept":
        ident = " ".join(args[1:]).strip()
        turn = run_turn("", accept=True, accept_id=ident)
    else:
        turn = run_turn(" ".join(args))
    sys.stdout.write(json.dumps(turn.as_dict(), indent=2, sort_keys=True))
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 1 if turn.paused else 0
