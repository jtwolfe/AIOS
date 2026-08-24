#!/usr/bin/python3
"""Unprivileged bots jobs. Path+slice+skill, not selves. VM work is an intent."""

import json
import os
import socket
import sys
import uuid

SOCK = os.environ.get("AIOS_INTENT_SOCK") or "/run/aios/intent.sock"
HERE = os.path.dirname(os.path.abspath(__file__))
JOBS_DIR = os.path.join(HERE, "jobs")
VM_VERBS = ("define", "start", "stop", "snapshot", "destroy")
FORBIDDEN = ("virsh", "pacman")
IDENTITY = ("avatar", "psyche", "personhood", "identity-store")


def _die(message):
    sys.stderr.write("error: %s\n" % message)
    return 1


def _jobs_dir():
    env = os.environ.get("AIOS_BOTS_JOBS")
    if env:
        return env
    return JOBS_DIR


def _parse_job(path):
    job = {
        "path": path,
        "slice": "aios-work.slice",
        "skill": "",
        "state": "idle",
    }
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    lowered = text.lower()
    for token in IDENTITY:
        if token in lowered:
            return None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("path:"):
            job["path"] = stripped.split(":", 1)[1].strip() or path
        elif stripped.startswith("slice:"):
            job["slice"] = stripped.split(":", 1)[1].strip() or job["slice"]
        elif stripped.startswith("skill:"):
            job["skill"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("state:"):
            job["state"] = stripped.split(":", 1)[1].strip() or "idle"
    if not job["skill"]:
        return None
    return job


def list_jobs():
    folder = _jobs_dir()
    out = []
    if not os.path.isdir(folder):
        return out
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return out
    for name in names:
        if name.startswith(".") or name == "README.md":
            continue
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        job = _parse_job(path)
        if job:
            out.append(job)
    return out


def roster_text():
    lines = [
        "roster: jobs are path + slice + skill + state, not selves",
        "no avatars, no identity store, no personhood",
    ]
    jobs = list_jobs()
    if not jobs:
        lines.append("(empty)")
        return "\n".join(lines)
    for job in jobs:
        lines.append(
            "job path=%s slice=%s skill=%s state=%s"
            % (job["path"], job["slice"], job["skill"], job["state"])
        )
    return "\n".join(lines)


def find_job(ident):
    ident = (ident or "").strip()
    for job in list_jobs():
        base = os.path.basename(job["path"])
        stem = base[:-3] if base.endswith(".md") else base
        if ident in (job["path"], base, stem):
            return job
    return None


def handoff_payload(job):
    # Operational only (paths, oracles, last evidence). Not a psyche.
    return {
        "path": job["path"],
        "slice": job["slice"],
        "skill": job["skill"],
        "state": job["state"],
        "oracles": ["policy/hi-13-work-slice.sh", "policy/hi-16-os-privilege.sh"],
        "last_evidence": "",
    }


def intent_body(asked, paths):
    return {
        "id": str(uuid.uuid4()),
        "source": "work-runtime-bots",
        "asked": asked,
        "clause": "HI-13",
        "suggested_oracles": ["policy/hi-13-work-slice.sh"],
        "paths": list(paths),
    }


def file_intent(asked, paths):
    body = intent_body(asked, paths)
    blob = json.dumps(body, sort_keys=True, ensure_ascii=True) + "\n"
    sock = SOCK
    if os.path.exists(sock):
        try:
            conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                conn.settimeout(2)
                conn.connect(sock)
                conn.sendall(blob.encode("utf-8"))
                conn.shutdown(socket.SHUT_WR)
            finally:
                conn.close()
        except OSError as exc:
            sys.stderr.write("error: intent.sock: %s\n" % exc)
            return 1, body
    sys.stdout.write(blob)
    sys.stdout.flush()
    return 0, body


def job_card(job):
    handoff = handoff_payload(job)
    lines = [
        "job: path + slice + skill + state, not a self",
        "path: %s" % job["path"],
        "slice: %s" % job["slice"],
        "skill: %s" % job["skill"],
        "state: %s" % job["state"],
        "handoff: %s" % json.dumps(handoff, sort_keys=True, ensure_ascii=True),
        "send: work surface; stop: standing order off",
        "no avatar",
    ]
    return "\n".join(lines)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    joined = " ".join(argv).lower()
    for token in FORBIDDEN:
        if token in joined.split() or (argv and argv[0] == token):
            return _die(
                "%s from the slice fails; file an intent at %s (HI-13)"
                % (token, SOCK)
            )
    if argv and argv[0] == "ip" and len(argv) > 1:
        return _die("ip from the slice fails; file an intent at %s (HI-13)" % SOCK)
    if not argv or argv[0] in ("roster", "list"):
        sys.stdout.write(roster_text() + "\n")
        sys.stdout.flush()
        return 0
    if argv[0] == "job":
        ident = argv[1] if len(argv) > 1 else ""
        job = find_job(ident) if ident else (list_jobs()[0] if list_jobs() else None)
        if job is None:
            return _die("unknown job")
        sys.stdout.write(job_card(job) + "\n")
        sys.stdout.flush()
        return 0
    if argv[0] == "handoff":
        ident = argv[1] if len(argv) > 1 else ""
        job = find_job(ident) if ident else (list_jobs()[0] if list_jobs() else None)
        if job is None:
            return _die("unknown job")
        sys.stdout.write(
            json.dumps(handoff_payload(job), sort_keys=True, ensure_ascii=True) + "\n"
        )
        sys.stdout.flush()
        return 0
    if argv[0] == "vm" and len(argv) >= 2:
        verb = argv[1].lower()
        if verb not in VM_VERBS:
            return _die("vm verb not allowlisted: %s" % verb)
        guest = argv[2] if len(argv) > 2 else "guest"
        asked = "vm %s %s" % (verb, guest)
        rc, _body = file_intent(asked, ["/srv/aios/src/work-runtime-bots"])
        return rc
    if argv[0] in VM_VERBS:
        guest = argv[1] if len(argv) > 1 else "guest"
        asked = "vm %s %s" % (argv[0], guest)
        rc, _body = file_intent(asked, ["/srv/aios/src/work-runtime-bots"])
        return rc
    return _die("usage: main.py [roster|job NAME|handoff NAME|vm VERB GUEST]")


if __name__ == "__main__":
    sys.exit(main())
