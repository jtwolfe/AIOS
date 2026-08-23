"""Grok device-code OAuth (L-17). Token never on stdout. Never a pasted key."""

import json
import os
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from provider.base import (
    ACCEPT_STAMP,
    ANSWERS_PATH,
    OS_TOKEN_PATH,
    Provider,
    ProviderError,
    envelope_accepted,
    remotes_vetoed,
)

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


class LiveProvider(Provider):
    name = "live"

    def __init__(
        self,
        token_path=None,
        accept_stamp=None,
        answers_path=None,
        http=None,
        sleep=None,
    ):
        self.token_path = token_path or OS_TOKEN_PATH
        self.accept_stamp = accept_stamp or ACCEPT_STAMP
        self.answers_path = answers_path or ANSWERS_PATH
        self._http = http or http_json
        self._sleep = sleep or time.sleep
        # L-16: not /home (operator snowflake) and not /etc/aios (etckeeper).
        if self.token_path.startswith("/home/") or self.token_path.startswith(
            "/etc/aios/"
        ):
            raise ProviderError("OS token path is not the P4.2 lock (L-16)")

    def login(self, err=None):
        err = err or sys.stderr
        if not envelope_accepted(self.accept_stamp):
            raise ProviderError("live login is after envelope accept (L-17)")
        if remotes_vetoed(self.answers_path):
            raise ProviderError("remotes vetoed live login (L-17)")
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
        # Human opens this on another device. Never print device_code or tokens.
        err.write("%s\n" % uri)
        err.write("user_code: %s\n" % user_code)
        err.flush()
        complete = payload.get("verification_uri_complete")
        if complete and complete != uri:
            err.write("%s\n" % complete)
            err.flush()
        interval = int(payload.get("interval") or 5)
        if interval < 0:
            interval = 5
        deadline = time.time() + int(payload.get("expires_in") or 600)
        while time.time() < deadline:
            self._sleep(interval)
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
            if status == 200 and tok.get("access_token"):
                self._write_token(tok)
                return
            if err_code == "authorization_pending":
                continue
            if err_code == "slow_down":
                interval += 5
                continue
            if err_code in ("expired_token", "access_denied"):
                raise ProviderError("device-code %s (L-17)" % err_code)
            if status != 200:
                continue
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
        if not os.path.isfile(path):
            raise ProviderError("live login required (L-17)")
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode != 0o600:
            raise ProviderError("OS token mode is %o, not 0600 (L-16)" % mode)
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ProviderError("OS token is not a JSON object (L-17)")
        return data

    def _write_token(self, payload):
        path = self.token_path
        parent = os.path.dirname(path)
        os.makedirs(parent, mode=0o700, exist_ok=True)
        os.chmod(parent, 0o700)
        keep = {}
        for key in _TOKEN_KEYS:
            if key in payload:
                keep[key] = payload[key]
        if "access_token" not in keep:
            raise ProviderError("device-code produced no access_token (L-17)")
        fd, tmp = tempfile.mkstemp(prefix=".os.token.", dir=parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(keep, fh, separators=(",", ":"))
                fh.write("\n")
            os.replace(tmp, path)
            os.chmod(path, 0o600)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
