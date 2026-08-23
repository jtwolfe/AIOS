"""Harness B turn loop (P4.3). No-arg main.serve stays idle (L-21)."""

import json
import os
import subprocess
import sys

from memory import ingest, raise_conflict
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


def _oracles_from_reply(reply):
    text = reply if isinstance(reply, str) else str(reply or "")
    try:
        obj = json.loads(text)
    except ValueError:
        obj = None
    if isinstance(obj, dict):
        raw = obj.get("oracles")
        if isinstance(raw, list):
            return [str(item) for item in raw if str(item).strip()]
    found = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("oracle:"):
            item = stripped.split(":", 1)[1].strip()
            if item:
                found.append(item)
    return found


def _messages(asked, skills, triage):
    parts = [
        "You are the AIOS privileged proposer. Quote HI by id.",
        "Do not merge to main (HI-03). Do not force-push.",
        "Do not synthesise the work runtime (HI-15).",
        "Do not decide what memory is worth keeping (HI-11).",
        "Research is plan-only. Do not enact while planning (L-20).",
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


def _remember(asked, triage, skills, plan, accept, enacted, evidence, outcome, paused, reply, hi, memory_root):
    names = [skill.name for skill in skills] or ["none"]
    class_name = names[0] if names and names[0] != "none" else triage.kind
    return ingest(
        {
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
        },
        root=memory_root,
    )


def run_turn(
    asked,
    accept=False,
    provider=None,
    memory_root=None,
    skills_root=None,
    enact_bin=None,
):
    asked = asked if isinstance(asked, str) else str(asked or "")
    accept = bool(accept)
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
                accept,
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
                accept,
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

    # Privileged: plan (docs) is the only write until accept (L-20).
    oracles = _oracles_from_reply(reply)
    plan = {
        "intent": {"source": "human", "asked": asked},
        "oracles": oracles,
        "skills": skill_note,
        "enact": "not-while-planning",
        "citations": [],
    }
    if not accept:
        outcome = "waiting-accept"
        paths = _remember(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, hi, memory_root
        )
        return Turn(
            asked, triage, loaded, plan, False, enacted, evidence, outcome, paused, reply, paths, hi=hi
        )

    if not oracles:
        enacted = "refused-hi-10"
        paused = True
        outcome = "pause"
        reply = (reply + "\n" if reply else "") + "no oracle set, no enactment (HI-10)"
        paths = _remember(
            asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, hi, memory_root
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
    else:
        outcome = "verify"

    paths = _remember(
        asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, hi, memory_root
    )
    return Turn(
        asked, triage, loaded, plan, True, enacted, evidence, outcome, paused, reply, paths, hi=hi
    )


def cmd_turn(argv):
    accept = False
    args = list(argv)
    if args and args[0] == "--accept":
        accept = True
        args = args[1:]
    text = " ".join(args)
    turn = run_turn(text, accept=accept)
    sys.stdout.write(json.dumps(turn.as_dict(), indent=2, sort_keys=True))
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 1 if turn.paused else 0
