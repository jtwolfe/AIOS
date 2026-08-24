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
COMPACT_TEXT = ("skill_read", "skill_follow", "send", "question")
COMPACT_OBJ = (
    "connector_discover",
    "connector_call",
    "connector_connect",
    "connector_install",
    "browser",
    "fetch",
    "search",
    "dispatch",
    "check",
    "stop",
    "coding",
    "worker_dispatch",
    "worker_check",
    "worker_stop",
    "worker_branch",
    "coding_on_a_branch",
    "routine",
    "routine_create",
    "routine_expire",
    "routine_disable",
    "bridge_shell",
    "bridge_read",
    "bridge_copy",
    "bridge_copy_to",
    "bridge_copy_from",
    "copy_to_workspace",
    "copy_from_workspace",
    "bridge_approve",
    "bridge_deny",
    "approve",
    "deny",
)
LINE_PREFIXES = (
    "connector_discover:",
    "connector_call:",
    "connector_connect:",
    "connector_install:",
    "browser:",
    "fetch:",
    "search:",
    "skill_read:",
    "skill_follow:",
    "send:",
    "question:",
    "dispatch:",
    "check:",
    "stop:",
    "coding:",
    "routine:",
    "routine_create:",
    "routine_expire:",
    "routine_disable:",
    "bridge_shell:",
    "bridge_read:",
    "bridge_copy:",
    "bridge_approve:",
    "bridge_deny:",
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


def _tool_text(name, obj):
    name = (name or "").strip().lower()
    if name == "connector_call":
        if obj.get("text") and not obj.get("connector") and not obj.get("call"):
            return str(obj.get("text") or "")
        payload = {
            "connector": str(obj.get("connector") or ""),
            "tool": str(obj.get("call") or obj.get("method") or ""),
            "arguments": obj.get("arguments")
            if isinstance(obj.get("arguments"), dict)
            else {},
        }
        if not payload["tool"]:
            payload["tool"] = str(obj.get("name") or "") if obj.get("connector") else ""
        if not payload["connector"]:
            payload["connector"] = str(obj.get("name") or "")
        return json.dumps(payload)
    if name in ("browser", "fetch", "search"):
        if obj.get("text") and not obj.get("url") and not obj.get("service"):
            return str(obj.get("text") or "")
        return json.dumps(
            {
                "service": str(obj.get("service") or obj.get("name") or ""),
                "url": str(obj.get("url") or obj.get("text") or ""),
            }
        )
    if name == "connector_install":
        body = obj.get("body")
        if body is None:
            body = obj.get("spec")
        if body is None:
            body = obj.get("text")
        if isinstance(body, (dict, list)):
            return json.dumps(body)
        if body is not None:
            return str(body)
        if isinstance(obj.get("name"), str) and len(obj) > 2:
            return json.dumps(
                {k: v for k, v in obj.items() if k not in ("tool", "text")}
            )
        return str(obj.get("name") or "")
    text = obj.get("text")
    if text is None:
        text = obj.get("name")
    if text is None:
        text = obj.get("body")
    if text is None:
        text = obj.get("connector")
    return str(text or "")

def _payload_text(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    return str(value or "")


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
        return [(name, _tool_text(name, obj))]
    compact = dict(obj)
    if "question" in compact:
        compact.pop("send", None)
    out = []
    for key, value in compact.items():
        if key in COMPACT_TEXT or key in ("connector_discover", "connector_connect"):
            out.append((key, str(value or "")))
        elif key in COMPACT_OBJ:
            out.append((key, _payload_text(value)))
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
        for prefix in LINE_PREFIXES:
            if not lower.startswith(prefix):
                continue
            rest = stripped_line[len(prefix) :].strip()
            actions.append((prefix[:-1], rest))
            break
    return actions


def _load_spec(text):
    raw = text if isinstance(text, str) else str(text or "")
    stripped = raw.strip()
    if not stripped:
        return {}
    if stripped[0] in "{[":
        try:
            obj = json.loads(stripped)
        except ValueError:
            obj = None
        if isinstance(obj, dict):
            return obj
        if isinstance(obj, list):
            return {"items": obj}
    return {"id": stripped, "text": stripped}


def _canon_tool(tool, spec):
    aliases = {
        "worker_dispatch": "dispatch",
        "worker_check": "check",
        "worker_stop": "stop",
        "worker_branch": "coding",
        "coding_on_a_branch": "coding",
        "routine_create": "routine",
        "routine_expire": "routine_disable",
        "copy_to_workspace": "bridge_copy",
        "copy_from_workspace": "bridge_copy",
        "bridge_copy_to": "bridge_copy",
        "bridge_copy_from": "bridge_copy",
        "approve": "bridge_approve",
        "deny": "bridge_deny",
    }
    if tool in ("copy_to_workspace", "bridge_copy_to"):
        spec["direction"] = spec.get("direction") or "to_workspace"
        spec["op"] = spec.get("op") or "copy_to_workspace"
    elif tool in ("copy_from_workspace", "bridge_copy_from"):
        spec["direction"] = spec.get("direction") or "from_workspace"
        spec["op"] = spec.get("op") or "copy_from_workspace"
    elif tool == "bridge_copy":
        spec["op"] = spec.get("op") or "copy"
    elif tool == "bridge_shell":
        spec["op"] = spec.get("op") or "shell"
    elif tool == "bridge_read":
        spec["op"] = spec.get("op") or "read"
    return aliases.get(tool, tool), spec


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
    workers=None,
    routines=None,
    bridge=None,
    view=None,
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
        "workers": list(workers or []),
        "routines": list(routines or []),
        "bridge": bridge,
        "view": view,
        "error": error,
    }


def run_turn(asked):
    from connectors import ConnectorError, ConnectorSession, chat_secret_error
    from bridge import (
        BridgeError,
        approve as bridge_approve,
        deny as bridge_deny,
        request as bridge_request,
        view_for as bridge_view_for,
    )
    from provider import ProviderError, load
    from routines import RoutineError, create as routine_create
    from routines import disable as routine_disable
    from skills import load_body
    from wake import INJECTS, WakeError, inject
    from workers import WorkerError, check as worker_check
    from workers import coding as worker_coding
    from workers import dispatch as worker_dispatch
    from workers import stop as worker_stop

    asked = asked if isinstance(asked, str) else str(asked or "")
    injects = list(INJECTS)
    prompt = ""
    if not asked.strip():
        return _result(asked, injects, prompt, ended="idle", outcome="idle")

    secret = chat_secret_error(asked)
    if secret:
        return _result(
            asked,
            injects,
            prompt,
            ended="failed",
            outcome="failed",
            error=secret,
        )

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
    workers_out = []
    routines_out = []
    bridge_out = None
    view = None
    read_set = set()
    bodies_in_context = set()
    last_reply = ""
    context = prompt
    session = ConnectorSession(root)
    connect_card = None
    queued_ctx = []

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
                workers=workers_out,
                routines=routines_out,
                bridge=bridge_out,
                view=view,
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
                workers=workers_out,
                routines=routines_out,
                bridge=bridge_out,
                view=view,
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
            spec = _load_spec(text)
            tool, spec = _canon_tool(tool, spec)
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
            if tool == "dispatch":
                try:
                    worker = worker_dispatch(root, spec)
                except WorkerError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                workers_out.append(worker)
                if worker.get("status") == "done":
                    if not worker.get("result"):
                        error = "results are sent, not only acknowledged"
                        ended = "failed"
                        outcome = "failed"
                        stop = True
                        break
                    delivered.append(str(worker["result"]))
                    ended = "sent"
                    outcome = "sent"
                else:
                    ended = "running"
                    outcome = "ok"
                continue
            if tool == "check":
                try:
                    worker = worker_check(root, spec)
                except WorkerError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                workers_out.append(worker)
                ended = ended if ended != "idle" else "ok"
                outcome = outcome if outcome != "idle" else "ok"
                continue
            if tool == "stop":
                try:
                    worker = worker_stop(root, spec)
                except WorkerError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                workers_out.append(worker)
                ended = "stopped"
                outcome = "ok"
                continue
            if tool == "coding":
                try:
                    worker = worker_coding(root, spec)
                except WorkerError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                workers_out.append(worker)
                delivered.append(str(worker.get("result") or ""))
                ended = "sent"
                outcome = "sent"
                continue
            if tool == "routine":
                try:
                    routine = routine_create(root, spec)
                except RoutineError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                routines_out.append(routine)
                ended = "ok"
                outcome = "ok"
                continue
            if tool == "routine_disable":
                try:
                    routine = routine_disable(root, spec)
                except RoutineError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                routines_out.append(routine)
                ended = "ok"
                outcome = "ok"
                continue
            if tool in ("bridge_copy", "bridge_shell", "bridge_read"):
                try:
                    record = bridge_request(root, spec)
                except BridgeError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                view = "bridge"
                bridge_out = bridge_view_for(record)
                ended = "pending"
                outcome = "wait"
                continue
            if tool == "bridge_approve":
                try:
                    record = bridge_approve(root, spec)
                except BridgeError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                view = "bridge"
                bridge_out = bridge_view_for(record, reveal=True)
                if record.get("op") == "read" and record.get("body"):
                    delivered.append(record["body"])
                    ended = "sent"
                    outcome = "sent"
                elif record.get("op") == "shell":
                    delivered.append(str(record.get("stdout") or ""))
                    ended = "sent"
                    outcome = "sent"
                else:
                    ended = "approved"
                    outcome = "approved"
                continue
            if tool == "bridge_deny":
                try:
                    record = bridge_deny(root, spec)
                except BridgeError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                view = "bridge"
                bridge_out = bridge_view_for(record)
                ended = "denied"
                outcome = "denied"
                continue

            if tool == "connector_discover":
                try:
                    schema = session.discover(text)
                except ConnectorError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                queued_ctx.append("connector schema %s:\n%s" % (text.strip(), schema))
                continue
            if tool == "connector_call":
                try:
                    obj = json.loads(text) if text.strip().startswith("{") else {}
                except ValueError:
                    obj = {}
                conn_name = str(obj.get("connector") or "")
                call_name = str(obj.get("tool") or "")
                args = obj.get("arguments") if isinstance(obj.get("arguments"), dict) else {}
                try:
                    result = session.call(conn_name, call_name, args)
                except ConnectorError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                queued_ctx.append(
                    "connector result %s.%s:\n%s" % (conn_name, call_name, result)
                )
                continue
            if tool == "connector_connect":
                try:
                    connect_card = session.connect(text)
                except ConnectorError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                if ended == "idle":
                    ended = "connect"
                    outcome = "wait"
                continue
            if tool == "connector_install":
                try:
                    session.install(text)
                except ConnectorError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                continue
            if tool in ("browser", "fetch", "search"):
                try:
                    result = session.browser("", text)
                except ConnectorError as exc:
                    error = str(exc)
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                queued_ctx.append("browser result:\n%s" % result)
                continue
            error = "unknown tool %s" % tool
            ended = "failed"
            outcome = "failed"
            stop = True
            break

        if stop and error:
            break
        if queued or queued_ctx:
            messages.append({"role": "assistant", "content": last_reply})
            parts = []
            for skill in queued:
                parts.append("skill body %s:\n%s" % (skill.name, skill.body))
                bodies_in_context.add(skill.name)
            parts.extend(queued_ctx)
            queued_ctx = []
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
        workers=workers_out,
        routines=routines_out,
        bridge=bridge_out,
        view=view,
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
