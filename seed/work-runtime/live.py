"""Work-runtime Grok device-code OAuth (L-17). Own token file, never the OS key."""

import json
import os
import pwd
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from provider import (
    OS_TOKEN_PATH,
    ProviderError,
    _guard_path,
    work_root,
    work_token_path,
)
from wake import WakeError, envelope_state

# Public Grok CLI client. Same device-code grant as `grok login --device-auth`.
CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828"
DEVICE_CODE_URL = "https://auth.x.ai/oauth2/device/code"
TOKEN_URL = "https://auth.x.ai/oauth2/token"
CHAT_URL = "https://api.x.ai/v1/chat/completions"
SCOPE = "openid profile email offline_access grok-cli:access api:access"
DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
DEFAULT_MODEL = "grok-4"
# id_token is a JWT that can carry email; do not persist it (PII).
_TOKEN_KEYS = ("access_token", "refresh_token", "token_type", "expires_in")


def http_json(method, url, data=None, headers=None, timeout=30):
    hdrs = dict(headers or {})
    body = None
    if data is not None:
        if hdrs.get("Content-Type") == "application/json":
            body = json.dumps(data).encode("utf-8")
        else:
            body = urllib.parse.urlencode(data).encode("utf-8")
            hdrs.setdefault(
                "Content-Type", "application/x-www-form-urlencoded"
            )
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            status = getattr(resp, "status", 200)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        status = exc.code
    try:
        payload = json.loads(raw) if raw else {}
    except ValueError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    return status, payload


def _https_uri(value, what="verification_uri"):
    # Print only a single https URL. An injected http:// or newline is a
    # transcript/open-redirect footgun (RFC 8628 device-code hardening).
    if not isinstance(value, str) or not value:
        raise ProviderError("%s is not https (L-17)" % what)
    if value != value.strip() or any(c.isspace() for c in value):
        raise ProviderError("%s has whitespace (L-17)" % what)
    if not value.startswith("https://"):
        raise ProviderError("%s is not https (L-17)" % what)
    return value


def http_from_fixture(path):
    # Host oracles inject this so tests never call auth.x.ai (L-17).
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if not isinstance(doc, dict):
        raise ProviderError("login http fixture is not a JSON object (L-17)")
    polls = list(doc.get("polls") or [])
    state = {"i": 0}

    def http(method, url, data=None, headers=None, timeout=30):
        url = url or ""
        if url.endswith("/device/code") or url == DEVICE_CODE_URL:
            device = doc.get("device")
            if not isinstance(device, dict):
                device = {}
                for key in (
                    "user_code",
                    "verification_uri",
                    "verification_url",
                    "verification_uri_complete",
                    "device_code",
                    "interval",
                    "expires_in",
                ):
                    if key in doc:
                        device[key] = doc[key]
            return 200, device
        if url.endswith("/token") or url == TOKEN_URL:
            if polls:
                idx = state["i"]
                if idx >= len(polls):
                    idx = len(polls) - 1
                state["i"] += 1
                item = polls[idx]
                if isinstance(item, dict) and "status" in item:
                    return int(item.get("status") or 200), item.get("body") or {}
                if not isinstance(item, dict):
                    item = {}
                return 200, item
            tok = doc.get("token")
            if not isinstance(tok, dict):
                tok = {}
                for key in _TOKEN_KEYS:
                    if key in doc:
                        tok[key] = doc[key]
            if tok.get("access_token"):
                return 200, tok
            return 400, {"error": "authorization_pending"}
        if url.endswith("/chat/completions") or url == CHAT_URL:
            chat = doc.get("chat")
            if isinstance(chat, dict):
                return 200, chat
            return 200, {
                "choices": [{"message": {"content": str(doc.get("complete") or "")}}]
            }
        raise ProviderError("login http fixture: unexpected url")

    return http


def _as_messages(messages):
    if isinstance(messages, str):
        return [{"role": "user", "content": messages}]
    out = []
    for item in messages or []:
        if isinstance(item, dict):
            out.append(item)
        else:
            out.append({"role": "user", "content": str(item)})
    return out


def _gate_login(root):
    try:
        enabled, vetoes = envelope_state(root)
    except WakeError as exc:
        raise ProviderError(str(exc))
    if not enabled:
        raise ProviderError("live login is after envelope accept (L-17)")
    remotes = str(vetoes.get("remotes") or "").strip().lower()
    if remotes in ("yes", "true", "1"):
        raise ProviderError("remotes vetoed live login (L-17)")


class LiveProvider:
    name = "live"

    def __init__(self, token_path=None, http=None, sleep=None, root=None):
        self.root = root if root is not None else work_root()
        if token_path is None:
            self.token_path = work_token_path()
        else:
            if not str(token_path).strip():
                raise ProviderError("AIOS_WORK_TOKEN empty")
            _guard_path(token_path)
            self.token_path = token_path
        if os.path.abspath(self.token_path) == OS_TOKEN_PATH:
            raise ProviderError(
                "work uid cannot read the OS token (L-16): %s" % self.token_path
            )
        if http is not None:
            self._http = http
        else:
            hook = (os.environ.get("AIOS_PROVIDER_HTTP") or "").strip()
            self._http = http_from_fixture(hook) if hook else http_json
        self._sleep = sleep or time.sleep

    def request_device(self, err=None):
        err = err or sys.stderr
        _gate_login(self.root)
        status, payload = self._http(
            "POST",
            DEVICE_CODE_URL,
            data={"client_id": CLIENT_ID, "scope": SCOPE},
        )
        if status != 200:
            raise ProviderError("device-code request failed (L-17)")
        user_code = payload.get("user_code")
        uri = payload.get("verification_uri") or payload.get("verification_url")
        device_code = payload.get("device_code")
        if not user_code or not uri or not device_code:
            raise ProviderError("device-code response incomplete (L-17)")
        uri = _https_uri(uri)
        complete = payload.get("verification_uri_complete")
        if complete:
            complete = _https_uri(complete, "verification_uri_complete")
        # Human opens this on another device. Never print device_code or tokens.
        err.write("%s\n" % uri)
        err.write("user_code: %s\n" % user_code)
        err.flush()
        if complete and complete != uri:
            err.write("%s\n" % complete)
            err.flush()
        interval = int(payload.get("interval") or 5)
        if interval < 0:
            interval = 5
        return {
            "user_code": user_code,
            "uri": uri,
            "complete": complete,
            "device_code": device_code,
            "interval": interval,
            "deadline": time.time() + int(payload.get("expires_in") or 600),
        }

    def poll_token(self, device_code):
        status, tok = self._http(
            "POST",
            TOKEN_URL,
            data={
                "grant_type": DEVICE_GRANT,
                "device_code": device_code,
                "client_id": CLIENT_ID,
            },
        )
        err_code = (tok.get("error") or "") if isinstance(tok, dict) else ""
        if status == 200 and isinstance(tok, dict) and tok.get("access_token"):
            self._write_token(tok)
            return "ok"
        if err_code == "authorization_pending":
            return "pending"
        if err_code == "slow_down":
            return "slow_down"
        if err_code in ("expired_token", "access_denied"):
            return err_code
        if status != 200:
            return "pending"
        return "pending"

    def login(self, err=None):
        sess = self.request_device(err)
        interval = sess["interval"]
        while time.time() < sess["deadline"]:
            self._sleep(interval)
            result = self.poll_token(sess["device_code"])
            if result == "ok":
                return
            if result == "pending":
                continue
            if result == "slow_down":
                interval += 5
                continue
            if result in ("expired_token", "access_denied"):
                raise ProviderError("device-code %s (L-17)" % result)
        raise ProviderError("device-code timed out (L-17)")

    def complete(self, messages):
        token = self._access_token()
        model = os.environ.get("AIOS_MODEL") or DEFAULT_MODEL
        status, payload = self._http(
            "POST",
            CHAT_URL,
            data={"model": model, "messages": _as_messages(messages)},
            headers={
                "Authorization": "Bearer %s" % token,
                "Content-Type": "application/json",
            },
        )
        if status == 401:
            token = self._refresh()
            status, payload = self._http(
                "POST",
                CHAT_URL,
                data={"model": model, "messages": _as_messages(messages)},
                headers={
                    "Authorization": "Bearer %s" % token,
                    "Content-Type": "application/json",
                },
            )
        if status != 200:
            raise ProviderError("live complete failed")
        choices = payload.get("choices") or []
        if not choices:
            raise ProviderError("live complete empty")
        msg = (choices[0] or {}).get("message") or {}
        return str(msg.get("content") or "")

    def _access_token(self):
        data = self._read_token()
        token = data.get("access_token")
        if not token:
            raise ProviderError("live login required (L-17)")
        return token

    def _refresh(self):
        data = self._read_token()
        refresh = data.get("refresh_token")
        if not refresh:
            raise ProviderError("live login required (L-17)")
        status, payload = self._http(
            "POST",
            TOKEN_URL,
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": CLIENT_ID,
            },
        )
        if status != 200 or not payload.get("access_token"):
            raise ProviderError("live login required (L-17)")
        if "refresh_token" not in payload:
            payload = dict(payload)
            payload["refresh_token"] = refresh
        self._write_token(payload)
        return payload["access_token"]

    def _read_token(self):
        path = self.token_path
        _guard_path(path)
        if not os.path.isfile(path):
            raise ProviderError("live login required (L-17)")
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode != 0o600:
            raise ProviderError("work token mode is %o, not 0600 (L-16)" % mode)
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ProviderError("work token is not a JSON object (L-17)")
        return data

    def _write_token(self, payload):
        path = self.token_path
        _guard_path(path)
        parent = os.path.dirname(path)
        # Root `sudo` would otherwise leave root:root 0600; the unit user
        # could not read its own token (L-16). Non-root is the unit itself.
        work_ids = None
        if os.geteuid() == 0:
            try:
                spec = pwd.getpwnam("aios-work")
            except KeyError:
                raise ProviderError(
                    "aios-work missing; cannot chown work token (L-16)"
                )
            work_ids = (spec.pw_uid, spec.pw_gid)
        keep = {}
        for key in _TOKEN_KEYS:
            if key in payload:
                keep[key] = payload[key]
        if "access_token" not in keep:
            raise ProviderError("device-code produced no access_token (L-17)")
        tmp = None
        try:
            os.makedirs(parent, mode=0o700, exist_ok=True)
            os.chmod(parent, 0o700)
            if work_ids:
                os.chown(parent, work_ids[0], work_ids[1])
            fd, tmp = tempfile.mkstemp(prefix=".work.token.", dir=parent)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(keep, fh, separators=(",", ":"))
                fh.write("\n")
            os.replace(tmp, path)
            tmp = None
            os.chmod(path, 0o600)
            if work_ids:
                os.chown(path, work_ids[0], work_ids[1])
        except OSError as exc:
            if tmp:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            raise ProviderError("cannot write work token: %s (L-16)" % exc)
        except Exception:
            if tmp:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            raise
