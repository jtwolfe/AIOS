"""Workers: no user voice. Result is sent. Cannot enact."""

import json
import os
import re
import subprocess
import time

PRIVILEGED = re.compile(
    r"\b(enact|pacman|systemctl|bootctl|pacstrap)\b", re.IGNORECASE
)
VOICE_KEYS = ("voice", "speak", "utterance", "chat")
MAIN_BRANCHES = ("main", "master")


class WorkerError(Exception):
    """Worker surface cannot complete."""


def _dir(root):
    return os.path.join(root, "workers")


def _safe_id(raw):
    text = re.sub(r"[^A-Za-z0-9._-]+", "-", str(raw or "").strip()).strip(".-")
    if not text or text in (".", ".."):
        raise WorkerError("worker id missing")
    return text


def _path(root, worker_id):
    return os.path.join(_dir(root), "%s.json" % worker_id)


def _load(root, worker_id):
    path = _path(root, worker_id)
    if not os.path.isfile(path):
        raise WorkerError("unknown worker %s" % worker_id)
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise WorkerError("worker record invalid")
    return data


def _save(root, record):
    os.makedirs(_dir(root), exist_ok=True)
    path = _path(root, record["id"])
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return record


def _blob(spec):
    return json.dumps(spec, sort_keys=True)


def looks_privileged(spec):
    return PRIVILEGED.search(_blob(spec)) is not None


def _refuse_voice(spec):
    for key in VOICE_KEYS:
        if spec.get(key):
            raise WorkerError("workers have no user-visible voice")


def _refuse_enact(spec):
    if looks_privileged(spec):
        raise WorkerError("workers cannot enact (HI-13)")


def _git_env():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("GIT_"):
            env.pop(key, None)
    return env


def _git(repo, args):
    cmd = ["git", "-c", "safe.directory=%s" % repo, "-C", repo]
    cmd.extend(args)
    proc = subprocess.run(
        cmd, capture_output=True, text=True, env=_git_env()
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "git failed").strip()
        raise WorkerError(err)
    return (proc.stdout or "").strip()


def _branch_name(spec):
    wanted = str(spec.get("branch") or "").strip()
    if wanted:
        if wanted in MAIN_BRANCHES or wanted.endswith("/main"):
            raise WorkerError(
                "coding on a branch is a branch plus merge request"
            )
        return wanted
    slug = str(spec.get("slug") or spec.get("id") or "worker").strip()
    slug = re.sub(r"[^a-z0-9-]+", "-", slug.lower()).strip("-") or "worker"
    if slug in MAIN_BRANCHES:
        raise WorkerError("coding on a branch is a branch plus merge request")
    day = time.strftime("%Y-%m-%d", time.gmtime())
    return "agent/%s-%s" % (day, slug)


def _record(worker_id, **fields):
    out = {
        "id": worker_id,
        "status": "done",
        "kind": "dispatch",
        "task": "",
        "result": "",
        "voice": None,
        "branch": None,
        "merge_request": None,
    }
    out.update(fields)
    out["voice"] = None
    return out


def coding(root, spec):
    _refuse_voice(spec)
    _refuse_enact(spec)
    if spec.get("merge") or spec.get("commit_to_main"):
        raise WorkerError("coding on a branch is a branch plus merge request")
    repo = spec.get("repo") or root
    repo = os.path.abspath(str(repo))
    if not os.path.isdir(os.path.join(repo, ".git")):
        raise WorkerError("coding on a branch requires git")
    worker_id = _safe_id(spec.get("id") or spec.get("slug") or "coding")
    branch = _branch_name(spec)
    _git(repo, ["checkout", "-b", branch])
    current = _git(repo, ["rev-parse", "--abbrev-ref", "HEAD"])
    if current in MAIN_BRANCHES:
        raise WorkerError("coding on a branch is a branch plus merge request")
    mr = {
        "source": branch,
        "target": "main",
        "status": "open",
    }
    result = spec.get("result")
    if result is None or str(result) == "":
        result = "merge request %s -> main" % branch
    else:
        result = str(result)
    if not str(result).strip():
        raise WorkerError("results are sent, not only acknowledged")
    return _save(
        root,
        _record(
            worker_id,
            status="done",
            kind="coding",
            task=str(spec.get("task") or spec.get("slug") or ""),
            result=result,
            branch=branch,
            merge_request=mr,
        ),
    )


def dispatch(root, spec):
    spec = dict(spec or {})
    _refuse_voice(spec)
    _refuse_enact(spec)
    kind = str(spec.get("kind") or "dispatch").strip().lower()
    if kind in ("coding", "branch"):
        return coding(root, spec)
    worker_id = _safe_id(spec.get("id") or spec.get("name") or "worker")
    complete = spec.get("complete")
    result = spec.get("result")
    if complete is None:
        complete = result is not None and str(result) != ""
    if complete:
        result = str(result or "")
        if not result.strip():
            raise WorkerError("results are sent, not only acknowledged")
        status = "done"
    else:
        result = str(result or "")
        status = "running"
    return _save(
        root,
        _record(
            worker_id,
            status=status,
            kind="dispatch",
            task=str(spec.get("task") or ""),
            result=result,
        ),
    )


def check(root, spec):
    worker_id = _safe_id(spec.get("id") or spec.get("text") or spec.get("name"))
    record = _load(root, worker_id)
    record["voice"] = None
    return record


def stop(root, spec):
    worker_id = _safe_id(spec.get("id") or spec.get("text") or spec.get("name"))
    record = _load(root, worker_id)
    record["status"] = "stopped"
    record["voice"] = None
    return _save(root, record)
