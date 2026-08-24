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
_COMPACT_KEYS = (
    "skill_read",
    "skill_follow",
    "send",
    "question",
    "connector_discover",
    "connector_call",
    "connector_connect",
    "connector_install",
    "browser",
    "fetch",
    "search",
)
_LINE_PREFIXES = tuple("%s:" % key for key in _COMPACT_KEYS)


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
        if key not in _COMPACT_KEYS:
            continue
        if key == "connector_call" and isinstance(value, dict):
            out.append((key, _tool_text(key, value)))
            continue
        if key == "connector_install" and isinstance(value, dict):
            out.append((key, json.dumps(value)))
            continue
        if key in ("browser", "fetch", "search") and isinstance(value, dict):
            out.append((key, _tool_text(key, value)))
            continue
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
        for prefix in _LINE_PREFIXES:
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
    connect_card=None,
    connectors_discovered=None,
    connector_results=None,
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
        "connect_card": connect_card,
        "connectors_discovered": list(connectors_discovered or []),
        "connector_results": list(connector_results or []),
        "error": error,
    }


def _json_obj(text):
    raw = (text or "").strip()
    if not raw:
        return {}
    try:
        obj = json.loads(raw)
    except ValueError:
        return None
    if isinstance(obj, dict):
        return obj
    return {}


def _call_parts(text):
    obj = _json_obj(text)
    if obj:
        return (
            str(obj.get("connector") or obj.get("name") or ""),
            str(obj.get("tool") or obj.get("call") or ""),
            obj.get("arguments") if isinstance(obj.get("arguments"), dict) else {},
        )
    parts = (text or "").strip().split(None, 2)
    name = parts[0] if parts else ""
    tool = parts[1] if len(parts) > 1 else ""
    args = {}
    if len(parts) > 2:
        parsed = _json_obj(parts[2])
        if parsed:
            args = parsed
    return name, tool, args


def _browser_parts(text):
    obj = _json_obj(text)
    if obj:
        return (
            str(obj.get("service") or obj.get("name") or ""),
            str(obj.get("url") or ""),
        )
    raw = (text or "").strip()
    if not raw:
        return "", ""
    if raw.startswith("http://") or raw.startswith("https://"):
        return "", raw
    parts = raw.split(None, 1)
    return parts[0], parts[1] if len(parts) > 1 else ""


def run_turn(asked):
    from connectors import ConnectorError, ConnectorSession, chat_secret_error
    from provider import ProviderError, load
    from skills import load_body
    from wake import INJECTS, WakeError, inject

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
    read_set = set()
    bodies_in_context = set()
    last_reply = ""
    context = prompt
    session = ConnectorSession(root)
    connect_card = None

    def _fail_fields():
        return dict(
            context=context,
            model_text=last_reply,
            delivered="\n".join(delivered),
            ended="failed",
            outcome="failed",
            skills_read=skills_read,
            skills_followed=skills_followed,
            connect_card=connect_card,
            connectors_discovered=sorted(session.discovered),
            connector_results=session.results,
        )

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
                error=str(exc),
                **_fail_fields()
            )
        except Exception as exc:
            return _result(
                asked,
                injects,
                prompt,
                error=str(exc),
                **_fail_fields()
            )
        last_reply = reply if isinstance(reply, str) else str(reply or "")
        actions = parse_actions(last_reply)
        if not actions:
            if not delivered and question is None and connect_card is None:
                ended = "idle"
                outcome = "idle"
            break

        queued = []
        queued_ctx = []
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
                secret = chat_secret_error(text)
                if secret:
                    error = secret
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                delivered.append(text)
                ended = "sent"
                outcome = "sent"
                continue
            if tool == "question":
                secret = chat_secret_error(text)
                if secret:
                    error = secret
                    ended = "failed"
                    outcome = "failed"
                    stop = True
                    break
                question = text
                ended = "question"
                outcome = "wait"
                stop = True
                break
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
                conn_name, call_name, args = _call_parts(text)
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
                service, url = _browser_parts(text)
                try:
                    result = session.browser(service, url)
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
            messages.append({"role": "user", "content": "\n\n".join(parts)})
            context = _messages_text(messages)
            if question or error or delivered:
                break
            continue
        break
    else:
        error = "tool rounds exceeded this turn"
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
        connect_card=connect_card,
        connectors_discovered=sorted(session.discovered),
        connector_results=session.results,
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


def _provider_fail(exc):
    sys.stderr.write("denied: %s\n" % exc)
    sys.stderr.flush()
    return 1


def cmd_provider(argv):
    from provider import OS_TOKEN_PATH, WORK_TOKEN_PATH, ProviderError, load

    if not argv:
        sys.stderr.write(
            "usage: main.py provider path | provider os-path | provider fixture complete FILE [TEXT] | provider live login\n"
        )
        return 2
    if argv[0] == "path":
        sys.stdout.write("%s\n" % WORK_TOKEN_PATH)
        sys.stdout.flush()
        return 0
    if argv[0] == "os-path":
        sys.stdout.write("%s\n" % OS_TOKEN_PATH)
        sys.stdout.flush()
        return 0
    if argv[0] == "live" and (len(argv) < 2 or argv[1] != "login"):
        return _provider_fail("never a pasted API key (L-17)")
    if argv[0] == "live" and argv[1] == "login":
        if len(argv) != 2:
            return _provider_fail("never a pasted API key (L-17)")
        try:
            load("live").login()
        except ProviderError as exc:
            return _provider_fail(exc)
        sys.stdout.write("ok: login\n")
        sys.stdout.flush()
        return 0
    if argv[0] == "fixture" and len(argv) >= 2 and argv[1] == "complete":
        if len(argv) < 3:
            sys.stderr.write(
                "usage: main.py provider fixture complete FILE [TEXT]\n"
            )
            return 2
        text = " ".join(argv[3:]) if len(argv) > 3 else ""
        try:
            out = load("fixture", fixture_path=argv[2]).complete(text)
        except ProviderError as exc:
            return _provider_fail(exc)
        sys.stdout.write("%s\n" % out)
        sys.stdout.flush()
        return 0
    return _provider_fail("unknown provider action")


def _usage():
    sys.stderr.write(
        "usage: main.py [turn [TEXT] | provider path | provider live login]\n"
    )
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
    if argv[0] == "provider":
        return cmd_provider(argv[1:])
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
