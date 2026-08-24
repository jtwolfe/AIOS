"""Operator asks; this uid patches envelope/work-runtime-bots.md (P8.13)."""

import os
import subprocess

REQUEST_PATH = "/run/aios/bots-request"
ENACT_BIN = "/usr/lib/aios/bin/enact"


def _aios_root():
    env = os.environ.get("AIOS_ROOT")
    if env is None:
        return ""
    env = env.strip()
    if not env:
        return ""
    return os.path.abspath(env)


def _resolve(env_name, default):
    env = os.environ.get(env_name)
    if env:
        return env
    root = _aios_root()
    if root:
        return root + default
    return default


def request_path():
    return _resolve("AIOS_BOTS_REQUEST", REQUEST_PATH)


def enact_bin():
    env = os.environ.get("AIOS_ENACT")
    if env:
        return env
    root = _aios_root()
    if root:
        cand = root + "/usr/lib/aios/bin/enact"
        if os.path.isfile(cand):
            return cand
    return ENACT_BIN


def _read_request():
    path = request_path()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return ""
    line = (text or "").strip().split(None, 1)
    if not line:
        return ""
    return line[0].lower()


def _write_request(text):
    path = request_path()
    payload = "" if not text else "%s\n" % text
    prior = None
    try:
        prior = os.stat(path)
    except OSError:
        return
    flags = os.O_WRONLY | os.O_TRUNC
    fd = os.open(path, flags)
    try:
        if prior is not None:
            try:
                os.fchown(fd, prior.st_uid, prior.st_gid)
            except OSError:
                pass
        data = payload.encode("utf-8")
        while data:
            n = os.write(fd, data)
            data = data[n:]
        os.fsync(fd)
    finally:
        os.close(fd)


def _bind_destroot_env():
    root = _aios_root()
    if not root:
        return
    os.environ.setdefault(
        "AIOS_ANSWERS",
        root + "/srv/aios/state/bootstrap-in-progress/answers.json",
    )
    os.environ.setdefault(
        "AIOS_ENVELOPE_WORK", root + "/srv/aios/envelope/work-runtime.md"
    )
    os.environ.setdefault(
        "AIOS_ENVELOPE_BOTS", root + "/srv/aios/envelope/work-runtime-bots.md"
    )


def _run_enact():
    binary = enact_bin()
    env = os.environ.copy()
    if _aios_root():
        cmd = [binary, "enable", "work-runtime-bots"]
    else:
        cmd = ["sudo", "-n", binary, "enable", "work-runtime-bots"]
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=120,
        )
    except OSError as exc:
        return 1, "", "enact enable failed: %s" % exc
    except subprocess.TimeoutExpired:
        return 1, "", "enact enable timed out"
    out = proc.stdout.decode("utf-8", "replace")
    err = proc.stderr.decode("utf-8", "replace")
    if proc.returncode != 0:
        reason = (err or out).strip().splitlines()
        msg = reason[-1] if reason else "enact enable failed"
        return proc.returncode, out, msg
    return 0, out, ""


def tick_bots():
    action = _read_request()
    if action != "yes":
        return
    _bind_destroot_env()
    from goals import bots_yes, work_runtime_yes

    if not work_runtime_yes():
        try:
            _write_request("")
        except OSError:
            pass
        return
    if bots_yes():
        try:
            _write_request("")
        except OSError:
            pass
        return
    rc, _out, _err = _run_enact()
    if rc != 0:
        return
    try:
        _write_request("")
    except OSError:
        pass
