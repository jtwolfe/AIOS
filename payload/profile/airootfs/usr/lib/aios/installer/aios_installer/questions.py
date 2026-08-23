"""Installer questions. Skip is not a yes (HI-15)."""

# L-18 `questions`: purpose, work-runtime opt-in, operator login, vetoes.
IDS = (
    "purpose",
    "work-runtime",
    "operator",
    "never-do",
    "networks",
    "remotes",
)

PROMPTS = {
    "purpose": "What is this machine for?",
    "work-runtime": "Do you want to work with AI agents on this system?",
    "operator": "Operator login name?",
    "never-do": "What must the agent never do?",
    "networks": "Which networks may this machine join?",
    "remotes": "May this machine speak to remotes?",
}

# Yes/no items: only an explicit yes is yes. Skip leaves false.
YES_NO = frozenset(("work-runtime", "remotes"))


def empty():
    # HI-15: work runtime default off. No bots key on the first envelope.
    return {
        "purpose": None,
        "work_runtime": False,
        "operator": None,
        "vetoes": {
            "never_do": None,
            "networks": None,
            "remotes": False,
        },
    }


def is_yes(text):
    return (text or "").strip().lower() in ("yes", "y")


def is_no(text):
    return (text or "").strip().lower() in ("no", "n")


def _set_yes_no(answers, qid, value):
    if qid == "work-runtime":
        answers["work_runtime"] = bool(value)
        return
    if qid == "remotes":
        answers.setdefault("vetoes", {})["remotes"] = bool(value)


def apply_answer(answers, qid, text):
    text = "" if text is None else str(text).strip()
    if qid not in IDS:
        raise ValueError("unknown question %s" % qid)
    if qid in YES_NO:
        if is_yes(text):
            _set_yes_no(answers, qid, True)
            return "yes"
        # HI-15: anything that is not an explicit yes is not a yes.
        _set_yes_no(answers, qid, False)
        return "not-yes"
    if qid == "purpose":
        answers["purpose"] = text or None
    elif qid == "operator":
        answers["operator"] = text or None
    elif qid == "never-do":
        answers.setdefault("vetoes", {})["never_do"] = text or None
    elif qid == "networks":
        answers.setdefault("vetoes", {})["networks"] = text or None
    return "answered"


def apply_skip(answers, qid):
    if qid not in IDS:
        raise ValueError("unknown question %s" % qid)
    if qid in YES_NO:
        _set_yes_no(answers, qid, False)
        return "not-yes"
    apply_answer(answers, qid, "")
    return "unset"


def work_runtime_on(answers):
    return answers.get("work_runtime") is True


def format_answers(answers):
    vetoes = answers.get("vetoes") or {}
    work = "true" if work_runtime_on(answers) else "false"
    lines = [
        "purpose: %s" % (answers.get("purpose") or "(unset)"),
        "work-runtime: %s" % work,
        "operator: %s" % (answers.get("operator") or "(unset)"),
        "vetoes.never-do: %s" % (vetoes.get("never_do") or "(unset)"),
        "vetoes.networks: %s" % (vetoes.get("networks") or "(unset)"),
        "vetoes.remotes: %s" % ("true" if vetoes.get("remotes") is True else "false"),
    ]
    return "\n".join(lines)
