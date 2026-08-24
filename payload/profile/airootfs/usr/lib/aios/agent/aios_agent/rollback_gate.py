"""Operator asks; this uid runs enact rollback N (P7.7, L-19, HI-06)."""

import json
import os
import subprocess

REQUEST_PATH = "/run/aios/rollback-request"
STATUS_PATH = "/run/aios/rollback-status"
ENACT_BIN = "/usr/lib/aios/bin/enact"
_STATUS_KEYS = ("state", "n", "error", "entry")


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
    return _resolve("AIOS_ROLLBACK_REQUEST", REQUEST_PATH)


def status_path():
    return _resolve("AIOS_ROLLBACK_STATUS", STATUS_PATH)


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
    return (text or "").strip()


def _write_inplace(path, payload, mode):
    # Truncate the accept-created inode. A umask tmpfile swap would
    # drop 0660/0640 and the operator group (L-16).
    prior = None
    try:
        prior = os.stat(path)
    except OSError:
        prior = None
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, mode)
    try:
        os.fchmod(fd, mode)
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


def _write_request(text):
    payload = "" if not text else "%s\n" % text
    _write_inplace(request_path(), payload, 0o660)


def _write_status(payload):
    keep = {}
    if not isinstance(payload, dict):
        payload = {}
    for key in _STATUS_KEYS:
        val = payload.get(key)
        if val is None or val == "":
            continue
        keep[key] = str(val)
    body = json.dumps(keep, separators=(",", ":")) + "\n"
    _write_inplace(status_path(), body, 0o640)


def _read_status():
    path = status_path()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return {}
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except ValueError:
        return {}
    if not isinstance(data, dict):
        return {}
    return data


def _btrfs_mnt():
    root = _aios_root()
    if root:
        return root + "/run/aios-btrfs"
    return "/run/aios-btrfs"


def _broken_record():
    root = _aios_root()
    path = (root + "/srv/aios/state/broken-subvol") if root else "/srv/aios/state/broken-subvol"
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def _status_promoted(n):
    data = _read_status()
    state = (data.get("state") or "").strip().lower()
    return state == "promoted" and str(data.get("n") or "") == str(n)


def _fs_promoted(n):
    n = str(n)
    if _broken_record() == "@.broken-%s" % n:
        restore = os.path.join(_btrfs_mnt(), "@.restore-%s" % n)
        if not os.path.exists(restore):
            return True
    mnt = _btrfs_mnt()
    broken = os.path.join(mnt, "@.broken-%s" % n)
    restore = os.path.join(mnt, "@.restore-%s" % n)
    return os.path.exists(broken) and not os.path.exists(restore)


def parse_n(text):
    line = (text or "").strip()
    if not line:
        return None
    parts = line.split()
    if parts[0].lower() == "rollback":
        parts = parts[1:]
    if len(parts) != 1:
        return None
    token = parts[0]
    if token.startswith("-") or not token.isdigit():
        return None
    if int(token) <= 0:
        return None
    return token


def _cmdline_restore_n():
    env = os.environ.get("AIOS_CMDLINE")
    if env is not None:
        text = env
    elif _aios_root():
        return None
    else:
        try:
            with open("/proc/cmdline", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            return None
    for tok in text.split():
        if not tok.startswith("rootflags="):
            continue
        for part in tok.split("=", 1)[-1].split(","):
            if part.startswith("subvol=@.restore-"):
                n = part[len("subvol=@.restore-") :]
                if n.isdigit() and int(n) > 0:
                    return n
    return None


def _run_enact(n, promote=False):
    binary = enact_bin()
    args = [binary, "rollback", str(n)]
    if promote:
        args.append("promote")
    env = os.environ.copy()
    if _aios_root():
        cmd = args
    else:
        cmd = ["sudo", "-n", binary, "rollback", str(n)]
        if promote:
            cmd.append("promote")
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=120,
        )
    except OSError as exc:
        return 1, "", "enact rollback failed: %s (L-19)" % exc
    except subprocess.TimeoutExpired:
        return 1, "", "enact rollback timed out (L-19)"
    out = proc.stdout.decode("utf-8", "replace")
    err = proc.stderr.decode("utf-8", "replace")
    if proc.returncode != 0:
        reason = (err or out).strip().splitlines()
        msg = reason[-1] if reason else "enact rollback failed (L-19)"
        return proc.returncode, out, msg
    return 0, out, ""


def tick_rollback():
    raw = _read_request()
    n = parse_n(raw)
    if n is None:
        boot_n = _cmdline_restore_n()
        if boot_n is None:
            return
        # After promote, cmdline still names @.restore-N until the next reboot.
        if _status_promoted(boot_n):
            return
        if _fs_promoted(boot_n):
            _write_status({"state": "promoted", "n": boot_n})
            return
        rc, out, err = _run_enact(boot_n, promote=True)
        if rc != 0:
            _write_status({"state": "refused", "n": boot_n, "error": err})
            return
        _write_status({"state": "promoted", "n": boot_n})
        return
    try:
        _write_request("")
    except OSError:
        pass
    rc, out, err = _run_enact(n, promote=False)
    if rc != 0:
        _write_status({"state": "refused", "n": n, "error": err})
        return
    state = "prepared"
    if "promoted" in out:
        state = "promoted"
    entry = ""
    for line in out.splitlines():
        if line.startswith("entry "):
            entry = line[6:].strip()
    payload = {"state": state, "n": n}
    if entry:
        payload["entry"] = entry
    _write_status(payload)
