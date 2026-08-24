#!/usr/bin/python3
"""Unprivileged work runtime. No-arg main stays idle. Turns are CLI."""

import json
import os
import sys
import time

POLL_S = 60
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

PRIVILEGED_TOOLS = ("enact", "pacman", "systemctl", "bootctl", "pacstrap")


class WorkError(Exception):
    """Turn cannot complete."""


def work_src():
    env = os.environ.get("AIOS_WORK_SRC")
    if env is None:
        return HERE
    env = env.strip()
    if not env:
        raise WorkError("AIOS_WORK_SRC empty")
    return os.path.abspath(env)


def serve():
    # Available, not always proposing. One malformed wake must not exit the unit.
    while True:
        try:
            time.sleep(POLL_S)
        except KeyboardInterrupt:
            return 0
        except Exception:
            try:
                time.sleep(POLL_S)
            except Exception:
                return 0


def _actions_from_obj(obj):
    if not isinstance(obj, dict):
        return None
    if isinstance(obj.get("actions"), list):
        out = []
        for item in obj["actions"]:
            got = _actions_from_obj(item)
            if got:
                out.extend(got)
        return out
    if "tool" in obj:
        name = str(obj.get("tool") or "").strip()
        text = obj.get("text")
        if text is None:
            text = obj.get("name")
        if text is None:
            text = obj.get("body")
        return [(name, str(text or ""))]
    out = []
    if "skill_read" in obj:
        out.append(("skill_read", str(obj.get("skill_read") or "")))
    if "skill_follow" in obj:
        out.append(("skill_follow", str(obj.get("skill_follow") or "")))
    if "send" in obj:
        out.append(("send", str(obj.get("send") or "")))
    if "question" in obj:
        out.append(("question", str(obj.get("question") or "")))
    return out or None


def parse_actions(text):
    raw = text if isinstance(text, str) else str(text or "")
    stripped = raw.strip()
    if not stripped:
        return []
    try:
        obj = json.loads(stripped)
    except ValueError:
        obj = None
    if isinstance(obj, dict):
        got = _actions_from_obj(obj)
        if got is not None:
            return got
    actions = []
    for line in raw.splitlines():
        stripped_line = line.strip()
        lower = stripped_line.lower()
        for prefix in ("skill_read:", "skill_follow:", "send:", "question:"):
            if not lower.startswith(prefix):
                continue
            rest = stripped_line[len(prefix) :].strip()
            actions.append((prefix[:-1], rest))
            break
    return actions


def _result(
    asked,
    injects,
    prompt,
    model_text="",
    delivered="",
    question=None,
    ended="idle",
    outcome="idle",
    skills_read=None,
    skills_followed=None,
    error=None,
):
    return {
        "asked": asked,
        "injects": list(injects),
        "prompt": prompt,
        "model_text": model_text,
        "delivered": delivered,
        "surface": delivered,
        "question": question,
        "ended": ended,
        "outcome": outcome,
        "skills_read": list(skills_read or []),
        "skills_followed": list(skills_followed or []),
        "error": error,
    }


def run_turn(asked):
    from provider import ProviderError, load
    from skills import load_body
    from wake import INJECTS, WakeError, inject

    asked = asked if isinstance(asked, str) else str(asked or "")
    injects = list(INJECTS)
    prompt = ""
    if not asked.strip():
        return _result(asked, injects, prompt, ended="idle", outcome="idle")

    root = work_src()
    try:
        prompt, injects = inject(asked, root)
    except WakeError as exc:
        return _result(
            asked,
            injects,
            prompt,
            ended="failed",
            outcome="failed",
            error=str(exc),
        )

    try:
        reply = load().complete([{"role": "user", "content": prompt}])
    except ProviderError as exc:
        return _result(
            asked,
            injects,
            prompt,
            ended="failed",
            outcome="failed",
            error=str(exc),
        )
    except Exception as exc:
        return _result(
            asked,
            injects,
            prompt,
            ended="failed",
            outcome="failed",
            error=str(exc),
        )

    reply = reply if isinstance(reply, str) else str(reply or "")
    actions = parse_actions(reply)
    delivered = []
    question = None
    ended = "idle"
    outcome = "idle"
    error = None
    skills_read = []
    skills_followed = []
    read_set = set()

    if not actions:
        # Plain model text is not delivered.
        return _result(
            asked,
            injects,
            prompt,
            model_text=reply,
            delivered="",
            ended="idle",
            outcome="idle",
        )

    for name, text in actions:
        tool = (name or "").strip().lower()
        if tool in PRIVILEGED_TOOLS:
            error = "work agents never enact privileged change (HI-13)"
            ended = "failed"
            outcome = "failed"
            break
        if tool == "skill_read":
            skill = load_body(root, text)
            if skill is None:
                error = "unknown skill %s" % text
                ended = "failed"
                outcome = "failed"
                break
            if skill.name not in read_set:
                skills_read.append(skill.name)
                read_set.add(skill.name)
            continue
        if tool == "skill_follow":
            skill = load_body(root, text)
            if skill is None:
                error = "unknown skill %s" % text
                ended = "failed"
                outcome = "failed"
                break
            if skill.name not in read_set:
                error = (
                    "following a skill without reading its body this turn fails"
                )
                ended = "failed"
                outcome = "failed"
                break
            if skill.name not in skills_followed:
                skills_followed.append(skill.name)
            continue
        if tool == "send":
            delivered.append(text)
            ended = "sent"
            outcome = "sent"
            continue
        if tool == "question":
            question = text
            ended = "question"
            outcome = "wait"
            break
        error = "unknown tool %s" % tool
        ended = "failed"
        outcome = "failed"
        break

    return _result(
        asked,
        injects,
        prompt,
        model_text=reply,
        delivered="\n".join(delivered),
        question=question,
        ended=ended,
        outcome=outcome,
        skills_read=skills_read,
        skills_followed=skills_followed,
        error=error,
    )


def cmd_turn(argv):
    asked = " ".join(argv)
    try:
        result = run_turn(asked)
    except Exception as exc:
        result = _result(
            asked,
            [],
            "",
            ended="failed",
            outcome="failed",
            error=str(exc),
        )
    sys.stdout.write(json.dumps(result, indent=2, sort_keys=True))
    sys.stdout.write("\n")
    sys.stdout.flush()
    if result.get("outcome") == "failed":
        return 1
    return 0


def _usage():
    sys.stderr.write("usage: main.py [turn [TEXT]]\n")
    return 2


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        try:
            return serve()
        except KeyboardInterrupt:
            return 0
        except Exception:
            return 0
    if argv[0] == "turn":
        return cmd_turn(argv[1:])
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
