"""Operator asks; this uid writes the OS token (L-16, L-17)."""

import io
import json
import os
import time

REQUEST_PATH = "/run/aios/login-request"
STATUS_PATH = "/run/aios/login-status"
WAKE_S = 0.25
_STATUS_KEYS = ("state", "verification", "user_code", "error")

_inflight = None


def reset_for_tests():
    global _inflight
    _inflight = None


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
    return _resolve("AIOS_LOGIN_REQUEST", REQUEST_PATH)


def status_path():
    return _resolve("AIOS_LOGIN_STATUS", STATUS_PATH)


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


def _write_inplace(path, payload, mode):
    # Truncate the accept-created inode. A umask tmpfile swap would
    # drop 0660/0640 and the operator group (L-16, L-17).
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
        text = str(val)
        if key == "verification":
            if not text.startswith("https://") or any(c.isspace() for c in text):
                continue
        if key in ("access_token", "refresh_token", "device_code"):
            continue
        keep[key] = text
    body = json.dumps(keep, separators=(",", ":")) + "\n"
    _write_inplace(status_path(), body, 0o640)


def _clear_inflight():
    global _inflight
    _inflight = None


def _poll_inflight():
    global _inflight
    sess = _inflight
    if sess is None:
        return
    from provider.base import ProviderError

    try:
        result = sess["provider"].poll_token(sess["device_code"])
    except ProviderError as exc:
        _clear_inflight()
        _write_status({"state": "refused", "error": str(exc)})
        return
    except OSError:
        _clear_inflight()
        _write_status(
            {"state": "refused", "error": "device-code request failed (L-17)"}
        )
        return
    if result == "ok":
        uri = sess.get("uri") or ""
        code = sess.get("user_code") or ""
        _clear_inflight()
        _write_status(
            {"state": "ok", "verification": uri, "user_code": code}
        )
        return
    if result == "pending":
        return
    if result == "slow_down":
        sess["interval"] = int(sess.get("interval") or 5) + 5
        return
    _clear_inflight()
    _write_status({"state": "refused", "error": "device-code %s (L-17)" % result})


def tick_login():
    global _inflight
    action = _read_request()
    if action == "cancel":
        _clear_inflight()
        try:
            _write_status({"state": "cancelled"})
            _write_request("")
        except OSError:
            pass
        return
    if _inflight is not None:
        if time.time() >= float(_inflight.get("deadline") or 0):
            _clear_inflight()
            _write_status(
                {"state": "refused", "error": "device-code timed out (L-17)"}
            )
            return
        _poll_inflight()
        return
    if action != "start":
        return
    kind = (os.environ.get("AIOS_PROVIDER") or "").strip()
    if kind == "fixture":
        _write_status(
            {"state": "refused", "error": "fixture has no live login (L-17)"}
        )
        _write_request("")
        return
    from provider.base import ProviderError
    from provider.live import LiveProvider

    err = io.StringIO()
    try:
        provider = LiveProvider()
        sess = provider.request_device(err=err)
    except ProviderError as exc:
        _write_status({"state": "refused", "error": str(exc)})
        _write_request("")
        return
    except OSError:
        _write_status(
            {"state": "refused", "error": "device-code request failed (L-17)"}
        )
        _write_request("")
        return
    _inflight = {
        "provider": provider,
        "device_code": sess.get("device_code") or "",
        "interval": sess.get("interval") or 5,
        "deadline": sess.get("deadline") or (time.time() + 600),
        "uri": sess.get("uri") or "",
        "user_code": sess.get("user_code") or "",
    }
    try:
        _write_request("")
        _write_status(
            {
                "state": "waiting",
                "verification": sess.get("uri") or "",
                "user_code": sess.get("user_code") or "",
            }
        )
    except OSError:
        _clear_inflight()
        raise


def drain_slice(budget):
    stop = time.time() + float(budget)
    while time.time() < stop:
        tick_login()
        try:
            from rollback_gate import tick_rollback

            tick_rollback()
        except Exception:
            pass
        remain = stop - time.time()
        if remain <= 0:
            break
        time.sleep(WAKE_S if remain > WAKE_S else remain)
