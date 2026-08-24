"""Operator bridge: approval view. Verbatim copy, not a mount."""

import hashlib
import json
import os
import re
import shutil
import subprocess

PRIVILEGED = re.compile(
    r"\b(enact|pacman|systemctl|bootctl|pacstrap)\b", re.IGNORECASE
)
NOT_OPERATOR = re.compile(
    r"\b(login|2fa|2-fa|two-factor|captcha|payment|password)\b", re.IGNORECASE
)
PRIVILEGED_PREFIXES = (
    "/usr",
    "/etc",
    "/boot",
    "/srv/aios/envelope",
    "/srv/aios/state",
    "/srv/aios/agent",
    "/srv/aios/checker",
    "/srv/aios/git",
    "/usr/lib/aios/bin/enact",
)
VIEW_ID = "bridge"
APPROVAL_IS_OPERATOR_VIEW = "approval is an operator view, not a model tool"


class BridgeError(Exception):
    """Bridge surface cannot complete."""


def _dir(root):
    env = os.environ.get("AIOS_BRIDGE_STATE")
    if env is not None:
        env = env.strip()
        if not env:
            raise BridgeError("AIOS_BRIDGE_STATE empty")
        return os.path.abspath(env)
    aios_root = os.environ.get("AIOS_ROOT")
    if aios_root:
        aios_root = aios_root.strip()
        if not aios_root:
            raise BridgeError("AIOS_ROOT empty")
        return os.path.join(os.path.abspath(aios_root), "bridge-state")
    key = hashlib.sha256(os.path.abspath(root).encode("utf-8")).hexdigest()[:12]
    return os.path.join("/tmp", "aios-bridge-%s" % key)


def _safe_id(raw):
    text = re.sub(r"[^A-Za-z0-9._-]+", "-", str(raw or "").strip()).strip(".-")
    if not text or text in (".", ".."):
        raise BridgeError("bridge request id missing")
    return text


def _path(root, req_id):
    return os.path.join(_dir(root), "%s.json" % req_id)


def _secure_dir(path):
    os.makedirs(path, exist_ok=True)
    os.chmod(path, 0o700)


def _save(root, record):
    _secure_dir(_dir(root))
    path = _path(root, record["id"])
    payload = json.dumps(record, indent=2, sort_keys=True) + "\n"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)
    os.chmod(path, 0o600)
    return record


def _load(root, req_id):
    path = _path(root, req_id)
    if not os.path.isfile(path):
        raise BridgeError("unknown bridge request %s" % req_id)
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise BridgeError("bridge record invalid")
    return data


def _operator_home():
    env = os.environ.get("AIOS_OPERATOR_HOME")
    if env is None:
        return None
    env = env.strip()
    if not env:
        raise BridgeError("AIOS_OPERATOR_HOME empty")
    return os.path.abspath(env)


def _is_under(path, root):
    path = os.path.abspath(path)
    root = os.path.abspath(root)
    return path == root or path.startswith(root + os.sep)


def _privileged_path(path):
    abs_path = os.path.abspath(path)
    for prefix in PRIVILEGED_PREFIXES:
        if abs_path == prefix or abs_path.startswith(prefix + os.sep):
            return True
    return False


def _is_home(path):
    abs_path = os.path.abspath(path)
    return abs_path == "/home" or abs_path.startswith("/home/")


def _in_tmp_dropbox(path):
    abs_path = os.path.abspath(path)
    for prefix in ("/tmp", "/var/tmp"):
        if abs_path == prefix or abs_path.startswith(prefix + os.sep):
            return True
    return False


def _expand(path, root, side):
    raw = str(path or "").strip()
    if not raw:
        raise BridgeError("bridge path missing")
    if raw.startswith("~/"):
        home = _operator_home()
        if home is None:
            raise BridgeError("operator home missing")
        raw = os.path.join(home, raw[2:])
    elif raw == "~":
        home = _operator_home()
        if home is None:
            raise BridgeError("operator home missing")
        raw = home
    if not os.path.isabs(raw):
        if side == "workspace":
            raw = os.path.join(root, raw)
        elif side == "dropbox":
            raw = os.path.join("/tmp", raw)
        else:
            home = _operator_home()
            if home is None:
                raise BridgeError("operator home missing")
            raw = os.path.join(home, raw)
    abs_path = os.path.abspath(raw)
    if _privileged_path(abs_path):
        raise BridgeError("work agents never enact privileged change (HI-13)")
    if side != "dropbox" and _is_home(abs_path) and _operator_home() is None:
        raise BridgeError("refusing live /home without AIOS_OPERATOR_HOME")
    home = _operator_home()
    if side != "dropbox" and _is_home(abs_path) and home is not None:
        if not _is_under(abs_path, home):
            raise BridgeError("refusing live /home without AIOS_OPERATOR_HOME")
    return abs_path


def _refuse_interactive(spec):
    op = str(spec.get("op") or spec.get("kind") or "").strip().lower()
    command = str(spec.get("command") or spec.get("text") or "")
    blob = "%s %s" % (op, command)
    if op in ("login", "2fa", "captcha", "payment", "password"):
        raise BridgeError("login/2FA/captcha/payment are not operator-computer work")
    if NOT_OPERATOR.search(blob):
        raise BridgeError("login/2FA/captcha/payment are not operator-computer work")
    if PRIVILEGED.search(blob):
        raise BridgeError("work agents never enact privileged change (HI-13)")


def _next_id(root, prefix):
    n = 1
    while os.path.isfile(_path(root, "%s%s" % (prefix, n))):
        n += 1
    return "%s%s" % (prefix, n)


def _grant_fields(record):
    return {
        "command": record.get("command") or "",
        "cwd": record.get("cwd") or "",
        "dst": record.get("dst") or "",
        "id": record.get("id") or "",
        "op": record.get("op") or "",
        "path": record.get("path") or "",
        "src": record.get("src") or "",
    }


def grant_hash(record):
    blob = json.dumps(_grant_fields(record), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def view_for(record, audience="work"):
    status = record.get("status") or "pending"
    actions = ["approve", "deny"] if status == "pending" else []
    out = {
        "id": record.get("id"),
        "status": status,
        "op": record.get("op"),
        "actions": actions,
        "path_visible": False,
        "view": VIEW_ID,
    }
    if audience == "operator":
        out["path_visible"] = True
        out["grant"] = record.get("grant")
        op = record.get("op")
        if op == "copy_to_workspace":
            out["path"] = record.get("src")
        elif op == "copy_from_workspace":
            out["path"] = record.get("dst")
        elif op == "read":
            out["path"] = record.get("path")
        elif op == "shell":
            out["command"] = record.get("command")
        return out
    if status == "approved":
        if record.get("body"):
            out["body"] = record.get("body")
        if record.get("copied"):
            out["copied"] = record.get("copied")
        if record.get("stdout") is not None:
            out["stdout"] = record.get("stdout")
    return out


def request(root, spec):
    spec = dict(spec or {})
    _refuse_interactive(spec)
    op = str(spec.get("op") or spec.get("kind") or "copy").strip().lower()
    if op in ("copy_to", "copy_to_workspace", "copy"):
        if str(spec.get("direction") or "").strip() == "from_workspace":
            op = "copy_from_workspace"
        else:
            op = "copy_to_workspace"
    elif op in ("copy_from", "copy_from_workspace"):
        op = "copy_from_workspace"
    elif op in ("shell", "bridge_shell"):
        op = "shell"
    elif op in ("read", "bridge_read"):
        op = "read"
    else:
        raise BridgeError("unknown bridge op %s" % op)

    req_id = spec.get("id")
    if req_id:
        req_id = _safe_id(req_id)
    else:
        req_id = _next_id(root, "b")

    record = {
        "id": req_id,
        "op": op,
        "status": "pending",
        "command": str(spec.get("command") or ""),
        "src": "",
        "dst": "",
        "path": "",
        "body": "",
        "stdout": "",
        "copied": False,
        "ran": False,
        "grant": "",
    }

    if op in ("copy_to_workspace", "copy_from_workspace"):
        src = spec.get("src") or spec.get("from")
        dst = spec.get("dst") or spec.get("to")
        if op == "copy_to_workspace":
            src_abs = _expand(src, root, "operator")
            dst_abs = _expand(dst, root, "workspace")
            if _is_under(src_abs, root):
                raise BridgeError("operator path required")
            if not _is_under(dst_abs, root):
                raise BridgeError("workspace dest required")
        else:
            src_abs = _expand(src, root, "workspace")
            if not _is_under(src_abs, root):
                raise BridgeError("workspace src required")
            dst_abs = _expand(dst, root, "dropbox")
            if _is_home(dst_abs):
                raise BridgeError("copy from workspace is client-mediated")
            home = _operator_home()
            if home is not None and _is_under(dst_abs, home) and not _in_tmp_dropbox(home):
                raise BridgeError("copy from workspace is client-mediated")
            if not _in_tmp_dropbox(dst_abs):
                raise BridgeError("copy from workspace is client-mediated")
        if _privileged_path(src_abs) or _privileged_path(dst_abs):
            raise BridgeError("work agents never enact privileged change (HI-13)")
        record["src"] = src_abs
        record["dst"] = dst_abs
        record["path"] = src_abs
    elif op == "read":
        path = spec.get("path") or spec.get("src") or spec.get("text")
        record["path"] = _expand(path, root, "operator")
        if _is_under(record["path"], root):
            raise BridgeError("operator path required")
    elif op == "shell":
        command = str(spec.get("command") or spec.get("text") or "").strip()
        if not command:
            raise BridgeError("bridge shell command missing")
        record["command"] = command
        cwd = spec.get("cwd") or _operator_home() or root
        record["cwd"] = os.path.abspath(str(cwd))

    record["grant"] = grant_hash(record)
    return _save(root, record)


def _copy_verbatim(src, dst):
    if os.path.islink(src) or os.path.ismount(src):
        raise BridgeError("copy is verbatim, not a mount")
    parent = os.path.dirname(dst)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent, exist_ok=True)
    if os.path.lexists(dst) and os.path.islink(dst):
        raise BridgeError("copy is verbatim, not a mount")
    with open(src, "rb") as inf:
        with open(dst, "wb") as outf:
            shutil.copyfileobj(inf, outf)
    if os.path.islink(dst) or os.path.ismount(dst):
        os.remove(dst)
        raise BridgeError("copy is verbatim, not a mount")
    if os.path.samefile(src, dst):
        raise BridgeError("copy is verbatim, not a mount")


def _structured_read(path):
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    out = []
    for index, line in enumerate(lines, 1):
        out.append("%d→%s" % (index, line))
    return "\n".join(out)


def _run_shell(record):
    command = record.get("command") or ""
    if NOT_OPERATOR.search(command):
        raise BridgeError("login/2FA/captcha/payment are not operator-computer work")
    if PRIVILEGED.search(command):
        raise BridgeError("work agents never enact privileged change (HI-13)")
    for needle in (
        "/usr/",
        "/etc/",
        "/boot/",
        "/srv/aios/envelope",
        "/srv/aios/state",
        "/usr/lib/aios/bin/enact",
    ):
        if needle in command:
            raise BridgeError("work agents never enact privileged change (HI-13)")
    if "/home/" in command:
        home = _operator_home()
        if home is None or home not in command:
            raise BridgeError("refusing live /home without AIOS_OPERATOR_HOME")
    cwd = record.get("cwd") or os.getcwd()
    cwd = os.path.abspath(str(cwd))
    if _privileged_path(cwd):
        raise BridgeError("work agents never enact privileged change (HI-13)")
    proc = subprocess.run(
        command,
        shell=True,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=8,
    )
    stdout = proc.stdout or ""
    if proc.returncode != 0:
        err = (proc.stderr or stdout or "bridge shell failed").strip()
        raise BridgeError(err)
    return stdout


def approve(root, spec):
    spec = dict(spec or {})
    req_id = spec.get("id") or spec.get("name")
    grant = str(spec.get("grant") or "").strip()
    if not req_id:
        raise BridgeError("bridge request id missing")
    if not grant:
        raise BridgeError("bridge grant missing")
    record = _load(root, _safe_id(req_id))
    frozen = grant_hash(record)
    stored = str(record.get("grant") or "")
    if grant != stored or grant != frozen:
        raise BridgeError("bridge grant mismatch")
    if record.get("status") == "denied":
        raise BridgeError("bridge request denied")
    if record.get("status") != "pending" and record.get("status") != "approved":
        raise BridgeError("bridge request %s" % record.get("status"))
    if record.get("status") == "approved" and record.get("ran"):
        return record

    op = record.get("op")
    if op in ("copy_to_workspace", "copy_from_workspace"):
        src = record.get("src")
        dst = record.get("dst")
        if not src or not dst:
            raise BridgeError("bridge copy paths missing")
        if op == "copy_from_workspace":
            if _is_home(dst) or not _in_tmp_dropbox(dst):
                raise BridgeError("copy from workspace is client-mediated")
        if not os.path.isfile(src):
            raise BridgeError("bridge copy src missing")
        _copy_verbatim(src, dst)
        record["copied"] = True
        record["ran"] = True
    elif op == "read":
        path = record.get("path")
        if not path or not os.path.isfile(path):
            raise BridgeError("bridge read path missing")
        record["body"] = _structured_read(path)
        record["ran"] = True
    elif op == "shell":
        record["stdout"] = _run_shell(record)
        record["ran"] = True
    else:
        raise BridgeError("unknown bridge op %s" % op)
    record["status"] = "approved"
    record["grant"] = grant_hash(record)
    return _save(root, record)


def deny(root, spec):
    spec = dict(spec or {})
    req_id = spec.get("id") or spec.get("name")
    if not req_id:
        raise BridgeError("bridge request id missing")
    record = _load(root, _safe_id(req_id))
    record["status"] = "denied"
    record["ran"] = False
    record["grant"] = grant_hash(record)
    return _save(root, record)
