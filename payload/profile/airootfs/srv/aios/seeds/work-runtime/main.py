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
MAX_TOOL_ROUNDS = 8
FOLLOW_WITHOUT_READ = (
    "following a skill without reading its body this turn fails"
)


class WorkError(Exception):
    """Turn cannot complete."""


def work_src():
    # Unset → this tree. Empty must not fall through to live /srv.
    env = os.environ.get("AIOS_WORK_SRC")
    if env is None:
        return HERE
    env = env.strip()
    if not env:
        raise WorkError("AIOS_WORK_SRC empty")
    return os.path.abspath(env)


def serve():
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
    compact = dict(obj)
    if "question" in compact:
        compact.pop("send", None)
    out = []
    for key, value in compact.items():
        if key in ("skill_read", "skill_follow", "send", "question"):
            out.append((key, str(value or "")))
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


def _messages_text(messages):
    parts = []
    for item in messages:
        if isinstance(item, dict):
            parts.append(str(item.get("content", "")))
        else:
            parts.append(str(item))
    return "\n".join(parts)


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
    context="",
):
    return {
        "asked": asked,
        "injects": list(injects),
        "prompt": prompt,
        "context": context,
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

    messages = [{"role": "user", "content": prompt}]
    delivered = []
    question = None
    ended = "idle"
    outcome = "idle"
    error = None
    skills_read = []
    skills_followed = []
    read_set = set()
    bodies_in_context = set()
    last_reply = ""
    context = prompt

    try:
        provider = load()
    except ProviderError as exc:
        return _result(
            asked,
            injects,
            prompt,
            context=context,
            ended="failed",
            outcome="failed",
            error=str(exc),
        )

    for _round in range(MAX_TOOL_ROUNDS):
        try:
            reply = provider.complete(messages)
        except ProviderError as exc:
            return _result(
                asked,
                injects,
                prompt,
                context=context,
                model_text=last_reply,
                delivered="\n".join(delivered),
                ended="failed",
                outcome="failed",
                error=str(exc),
                skills_read=skills_read,
                skills_followed=skills_followed,
            )
        except Exception as exc:
            return _result(
                asked,
                injects,
                prompt,
                context=context,
                model_text=last_reply,
                delivered="\n".join(delivered),
                ended="failed",
                outcome="failed",
                error=str(exc),
                skills_read=skills_read,
                skills_followed=skills_followed,
            )
        last_reply = reply if isinstance(reply, str) else str(reply or "")
        actions = parse_actions(last_reply)
        if not actions:
            if not delivered and question is None:
                ended = "idle"
                outcome = "idle"
            break

        queued = []
        stop = False
        for name, text in actions:
            tool = (name or "").strip().lower()
            if tool in PRIVILEGED_TOOLS:
                error = "work agents never enact privileged change (HI-13)"
                ended = "failed"
                outcome = "failed"
                stop = True
                break
            if tool == "skill_read":
                skill = load_body(root, text)
                if skill is None:
                    error = "unknown skill %s" % text
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                if skill.name not in read_set:
                    skills_read.append(skill.name)
                    read_set.add(skill.name)
                if skill.name not in bodies_in_context:
                    queued.append(skill)
                continue
            if tool == "skill_follow":
                skill = load_body(root, text)
                if skill is None:
                    error = "unknown skill %s" % text
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                if skill.name not in bodies_in_context:
                    error = FOLLOW_WITHOUT_READ
                    ended = "failed"
                    outcome = "failed"
                    stop = True
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
                stop = True
                break
            error = "unknown tool %s" % tool
            ended = "failed"
            outcome = "failed"
            stop = True
            break

        if stop and error:
            break
        if queued:
            messages.append({"role": "assistant", "content": last_reply})
            parts = []
            for skill in queued:
                parts.append("skill body %s:\n%s" % (skill.name, skill.body))
                bodies_in_context.add(skill.name)
            messages.append({"role": "user", "content": "\n\n".join(parts)})
            context = _messages_text(messages)
            if question or error or delivered:
                break
            continue
        break
    else:
        error = "skill read exceeded this-turn rounds"
        ended = "failed"
        outcome = "failed"

    return _result(
        asked,
        injects,
        prompt,
        context=context,
        model_text=last_reply,
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
