"""Recovery view (L-18). Durable bootstrap-in-progress snapshot (HI-09)."""

import json
import os

import compiler
from questions import IDS, empty, format_answers

DEFAULT_BOOTSTRAP = "/srv/aios/state/bootstrap-in-progress"
PROGRESS_VIEWS = ("questions", "envelope", "accept")
ALL_VIEWS = (
    "chrome",
    "conversation",
    "questions",
    "envelope",
    "accept",
    "recovery",
)


def bootstrap_dir():
    env = os.environ.get("AIOS_BOOTSTRAP")
    if env:
        return env
    return DEFAULT_BOOTSTRAP


def answers_path():
    return os.path.join(bootstrap_dir(), "answers.json")


def _atomic_write(path, text):
    # Temp + rename so a kill mid-write cannot leave half JSON (HI-09).
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    if not isinstance(text, str):
        text = str(text)
    if not text.endswith("\n"):
        text = text + "\n"
    tmp = "%s.tmp" % path
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def snapshot(last_step, answers, snapper_id, decision, qindex=0):
    return {
        "last_step": last_step or "questions",
        "snapper_id": snapper_id,
        "decision": decision,
        "answers": answers,
        "qindex": qindex,
    }


def render(last_step, answers, snapper_id, decision):
    snap = snapper_id if snapper_id not in (None, "") else "none"
    lines = [
        "last-step: %s" % (last_step or "questions"),
        "snapper-id: %s" % snap,
        "envelope-decision: %s" % (decision or "(none)"),
        "accepted-answers:",
        format_answers(answers),
        "resume: re-present last step",
        "rollback: L-19 snapper_pre window; not enacted here (HI-09)",
    ]
    return "\n".join(lines)


def resume_view(last_step):
    step = last_step or "questions"
    if step in ALL_VIEWS:
        return step
    return "questions"


def _parse_snapper_id(value):
    # bool is an int subclass; True must not become snapper id 1.
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    text = str(value).strip()
    if not text or text in ("none", "(none)"):
        return None
    if text.isdigit():
        return int(text)
    return None


def _parse_qindex(value):
    if isinstance(value, bool) or not isinstance(value, int):
        return 0
    if value < 0:
        return 0
    if value > len(IDS):
        return len(IDS)
    return value


def _parse_step(value):
    if not isinstance(value, str):
        return "questions"
    step = value.strip() or "questions"
    if step in ALL_VIEWS:
        return step
    return "questions"


def _parse_decision(data):
    if not isinstance(data, dict):
        return None
    if data.get("accepted") is True:
        return "accepted"
    dec = data.get("decision")
    if dec == "accepted":
        return "accepted"
    if dec == "rejected":
        return "rejected"
    return None


def _read_text(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def capture_snapper_pre():
    parsed = _parse_snapper_id(os.environ.get("AIOS_SNAPPER_PRE"))
    if parsed is not None:
        return parsed
    dest = bootstrap_dir()
    for path in (
        os.path.join(dest, "snapper_pre"),
        os.path.join(os.path.dirname(dest), "snapper_pre"),
    ):
        text = _read_text(path)
        if text is None:
            continue
        parsed = _parse_snapper_id(text)
        if parsed is not None:
            return parsed
    return None


def _answers_doc(last_step, answers, snapper_id, decision, qindex):
    if not isinstance(answers, dict):
        answers = empty()
    vetoes = answers.get("vetoes") if isinstance(answers.get("vetoes"), dict) else {}
    operator = answers.get("operator")
    if operator is not None and not isinstance(operator, str):
        operator = str(operator) if operator else None
    if isinstance(operator, str):
        operator = operator.strip() or None
    purpose = answers.get("purpose")
    if purpose is not None and not isinstance(purpose, str):
        purpose = str(purpose) if purpose else None
    if isinstance(purpose, str):
        purpose = purpose.strip() or None
    never = vetoes.get("never_do")
    if never is not None and not isinstance(never, str):
        never = str(never) if never else None
    if isinstance(never, str):
        never = never.strip() or None
    networks = vetoes.get("networks")
    if networks is not None and not isinstance(networks, str):
        networks = str(networks) if networks else None
    if isinstance(networks, str):
        networks = networks.strip() or None
    snap = _parse_snapper_id(snapper_id)
    return {
        "accepted": decision == "accepted",
        "decision": decision if decision in ("accepted", "rejected") else None,
        "operator": operator,
        "operator_login": operator,
        "purpose": purpose,
        "qindex": _parse_qindex(qindex),
        "snapper_pre": snap,
        "step": _parse_step(last_step),
        "vetoes": {
            "never_do": never,
            "networks": networks,
            "remotes": vetoes.get("remotes") is True,
        },
        "work_runtime": answers.get("work_runtime") is True,
    }


def save(last_step, answers, snapper_id, decision, qindex=0):
    dest = bootstrap_dir()
    if not os.environ.get("AIOS_BOOTSTRAP"):
        parent = os.path.dirname(dest)
        if parent and not os.path.isdir(parent):
            return
    os.makedirs(dest, exist_ok=True)
    doc = _answers_doc(last_step, answers, snapper_id, decision, qindex)
    blob = json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=True)
    draft = compiler.draft(answers if isinstance(answers, dict) else empty())
    snap = doc["snapper_pre"]
    snap_text = "" if snap is None else str(snap)
    _atomic_write(os.path.join(dest, "snapper_pre"), snap_text)
    _atomic_write(os.path.join(dest, "step"), doc["step"])
    _atomic_write(os.path.join(dest, "envelope.draft.md"), draft)
    _atomic_write(os.path.join(dest, "answers.json"), blob)


def _load_answers_mapping(data):
    answers = compiler.from_mapping(data)
    if not answers.get("operator"):
        login = data.get("operator_login")
        if login:
            answers["operator"] = login
    return answers


def _require_snapshot(data):
    # Fail closed on typed-field mismatch. 1 is not JSON true (HI-15).
    if not isinstance(data, dict):
        raise ValueError("snapshot is not an object")
    for key in ("purpose", "work_runtime", "operator", "vetoes", "accepted"):
        if key not in data:
            raise ValueError("snapshot missing %s" % key)
    if not isinstance(data.get("work_runtime"), bool):
        raise ValueError("work_runtime must be a JSON boolean")
    if not isinstance(data.get("accepted"), bool):
        raise ValueError("accepted must be a JSON boolean")
    vetoes = data.get("vetoes")
    if not isinstance(vetoes, dict):
        raise ValueError("vetoes must be an object")
    if "remotes" in vetoes and not isinstance(vetoes.get("remotes"), bool):
        raise ValueError("vetoes.remotes must be a JSON boolean")
    if "qindex" in data:
        qindex = data.get("qindex")
        if isinstance(qindex, bool) or not isinstance(qindex, int):
            raise ValueError("qindex must be an int")
    if "snapper_pre" in data and data.get("snapper_pre") is not None:
        snap = data.get("snapper_pre")
        if isinstance(snap, bool) or not isinstance(snap, int):
            raise ValueError("snapper_pre must be an int")
    if "decision" in data and data.get("decision") not in (
        None,
        "accepted",
        "rejected",
    ):
        raise ValueError("decision invalid")
    if "step" in data and not isinstance(data.get("step"), str):
        raise ValueError("step must be a string")
    if data.get("bots") is True:
        raise ValueError("bots must not be true")


def load():
    dest = bootstrap_dir()
    path = os.path.join(dest, "answers.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        _require_snapshot(data)
        answers = _load_answers_mapping(data)
        if answers.get("work_runtime") is not data.get("work_runtime"):
            raise ValueError("work_runtime identity mismatch")
        step = data.get("step") or data.get("last_step")
        if not step:
            file_step = _read_text(os.path.join(dest, "step"))
            if file_step is not None:
                step = file_step.strip()
        last_step = _parse_step(step)
        if last_step not in PROGRESS_VIEWS:
            last_step = "questions"
        snap = _parse_snapper_id(data.get("snapper_pre"))
        if snap is None:
            snap = _parse_snapper_id(_read_text(os.path.join(dest, "snapper_pre")))
        if snap is None:
            snap = capture_snapper_pre()
        qindex = _parse_qindex(data.get("qindex"))
        decision = _parse_decision(data)
        return {
            "last_step": last_step,
            "snapper_id": snap,
            "decision": decision,
            "answers": answers,
            "qindex": qindex,
        }
    except (OSError, json.JSONDecodeError, ValueError, TypeError, UnicodeError):
        return None
