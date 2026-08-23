"""Recovery view (L-18)."""

from questions import format_answers


def snapshot(last_step, answers, snapper_id, decision):
    return {
        "last_step": last_step or "questions",
        "snapper_id": snapper_id,
        "decision": decision,
        "answers": answers,
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
    ]
    return "\n".join(lines)


def resume_view(last_step):
    step = last_step or "questions"
    if step in (
        "chrome",
        "conversation",
        "questions",
        "envelope",
        "accept",
        "recovery",
    ):
        return step
    return "questions"
