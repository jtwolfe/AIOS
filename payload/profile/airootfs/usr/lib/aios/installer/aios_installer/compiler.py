"""Compile the first envelope from answers plus the canonical HI file."""

import json
import os
import sys

from questions import empty, format_answers, work_runtime_on


def _hi_paths():
    env = os.environ.get("AIOS_HI")
    here = os.path.dirname(os.path.abspath(__file__))
    return (
        env,
        "/srv/aios/envelope/hard-invariants.md",
        os.path.normpath(
            os.path.join(here, "..", "..", "envelope", "hard-invariants.md")
        ),
        os.path.normpath(os.path.join(here, "..", "..", "hard-invariants.md")),
        os.path.normpath(
            os.path.join(here, "..", "..", "docs", "envelope", "hard-invariants.md")
        ),
    )


def load_hi():
    for path in _hi_paths():
        if not path:
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                return fh.read(), path
        except OSError:
            continue
    return "", ""


def _plain(value):
    if value is None:
        return "(unset)"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (list, tuple)):
        parts = []
        for item in value:
            text = str(item).strip()
            if text:
                parts.append(text)
        return ", ".join(parts) if parts else "(unset)"
    text = str(value).strip()
    return text or "(unset)"


def from_mapping(data):
    answers = empty()
    if not isinstance(data, dict):
        return answers
    if "purpose" in data:
        purpose = data.get("purpose")
        answers["purpose"] = purpose if purpose else None
    # HI-15: only JSON true is yes. skip / "true" / "on" / "yes please" are not.
    if "work_runtime" in data:
        answers["work_runtime"] = data.get("work_runtime") is True
    if "operator" in data:
        operator = data.get("operator")
        answers["operator"] = operator if operator else None
    vetoes = data.get("vetoes")
    if isinstance(vetoes, dict):
        dest = answers.setdefault("vetoes", {})
        if "never_do" in vetoes:
            val = vetoes.get("never_do")
            dest["never_do"] = val if val else None
        if "networks" in vetoes:
            val = vetoes.get("networks")
            dest["networks"] = val if val else None
        if "remotes" in vetoes:
            dest["remotes"] = vetoes.get("remotes") is True
    return answers


def load_answers(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return from_mapping(data)


def derived_lines(answers):
    vetoes = answers.get("vetoes") or {}
    purpose = _plain(answers.get("purpose"))
    never = _plain(vetoes.get("never_do"))
    networks = _plain(vetoes.get("networks"))
    remotes_on = vetoes.get("remotes") is True
    if work_runtime_on(answers):
        work_bit = "work-runtime: yes"
        work_plain = (
            "The work runtime bit is yes (explicit). "
            "Do not synthesise /srv/aios/src/work-runtime here (HI-15)."
        )
    else:
        work_bit = "work-runtime: no"
        work_plain = (
            "The work runtime is off (HI-15). Skip is not a yes. "
            "Administer-only. Do not synthesise /srv/aios/src/work-runtime."
        )
    lines = ["derived:"]
    for line in format_answers(answers).splitlines():
        lines.append("  %s" % line)
    lines.extend(
        [
            "  %s" % work_bit,
            "  %s" % work_plain,
            "  This machine is for: %s" % purpose,
            "  The agent must never: %s" % never,
            "  Networks this machine may join: %s" % networks,
            "  Remotes: %s" % ("yes" if remotes_on else "no"),
            "  bots: false",
        ]
    )
    return lines


def compile_envelope(answers):
    hi_text, hi_path = load_hi()
    if not hi_text:
        raise ValueError("canonical hard-invariants.md missing")
    lines = [
        "compiler: p5.2",
        "hi-file: %s" % hi_path,
        "Human accept is merge authority for layer one (HI-05). "
        "Accept/reject are first-class actions.",
        "Derived clauses sit on top of HI-01 … HI-17. They do not rewrite them.",
    ]
    lines.extend(derived_lines(answers))
    lines.append("canonical-hard-invariants:")
    body = hi_text.replace("\r\n", "\n").replace("\r", "\n")
    if body.endswith("\n"):
        body = body[:-1]
    return "\n".join(lines) + "\n" + body + "\n"


def write_draft(text, path):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
        if not text.endswith("\n"):
            fh.write("\n")


def maybe_write(text):
    path = os.environ.get("AIOS_ENVELOPE_DRAFT")
    if not path:
        return
    write_draft(text, path)


def draft(answers):
    try:
        text = compile_envelope(answers)
    except ValueError as exc:
        lines = [
            "compiler: p5.2",
            "hi-file: (missing)",
            "error: %s" % exc,
            "Human accept is merge authority for layer one (HI-05). "
            "Accept/reject are first-class actions.",
        ]
        lines.extend(derived_lines(answers))
        text = "\n".join(lines) + "\n"
    try:
        maybe_write(text)
    except OSError:
        pass
    return text


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] in ("-h", "--help", "help"):
        sys.stdout.write("usage: compiler.py [answers.json]\n")
        sys.stdout.flush()
        return 0
    path = argv[0] if argv else None
    if path:
        try:
            answers = load_answers(path)
        except (OSError, json.JSONDecodeError, ValueError, TypeError) as exc:
            sys.stderr.write("error: %s\n" % exc)
            return 1
    else:
        answers = empty()
    try:
        text = compile_envelope(answers)
    except ValueError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 1
    dest = os.environ.get("AIOS_ENVELOPE_DRAFT")
    if dest:
        try:
            write_draft(text, dest)
        except OSError as exc:
            sys.stderr.write("error: %s\n" % exc)
            return 1
    sys.stdout.write(text)
    if not text.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
