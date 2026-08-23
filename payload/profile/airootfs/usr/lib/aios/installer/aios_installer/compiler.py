"""Envelope draft from answers. First compiler is P5.2."""

import os

from questions import format_answers, work_runtime_on


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


def hi_headings(text):
    out = []
    for line in (text or "").splitlines():
        if line.startswith("## HI-"):
            out.append(line[3:].strip())
    if not out:
        out.append("HI-01 … HI-17 (canonical file)")
    return out


def draft(answers):
    # L-18 envelope: HI file + derived clauses in plain language.
    text, path = load_hi()
    headings = hi_headings(text)
    if work_runtime_on(answers):
        work = (
            "work-runtime: yes (explicit). "
            "Do not synthesise /srv/aios/src/work-runtime here (HI-15)."
        )
    else:
        work = "work-runtime: no (HI-15; skip is not a yes). Administer-only."
    hi_path = path or "(HI file not on this host; clauses still apply)"
    lines = [
        "envelope-draft: answers + HI file",
        "compiler: p5.2",
        "hi-file: %s" % hi_path,
        "hi-clauses:",
    ]
    for heading in headings:
        lines.append("  %s" % heading)
    lines.append(work)
    lines.append("derived:")
    for line in format_answers(answers).splitlines():
        lines.append("  %s" % line)
    lines.append(
        "Human accept is merge authority for layer one (HI-05). "
        "Accept/reject are first-class actions."
    )
    return "\n".join(lines)
