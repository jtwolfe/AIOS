"""Work fixture (default) and live Grok adapter."""

import json
import os

OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"
WORK_TOKEN_PATH = "/srv/aios/src/work-runtime/.provider/work.token"


class ProviderError(Exception):
    """Adapter cannot complete this call."""


def _user_text(messages):
    if isinstance(messages, str):
        return messages
    parts = []
    for item in messages or []:
        if isinstance(item, dict):
            parts.append(str(item.get("content", "")))
        else:
            parts.append(str(item))
    return "\n".join(parts)


def refuse_os_token(path=None):
    path = path if path is not None else OS_TOKEN_PATH
    raise ProviderError("work uid cannot read the OS token (L-16): %s" % path)


def under_os_state(path):
    if not path:
        return False
    abs_path = os.path.abspath(path).replace("\\", "/")
    if abs_path == OS_TOKEN_PATH:
        return True
    marker = "/srv/aios/state"
    if abs_path == marker or abs_path.startswith(marker + "/"):
        return True
    idx = abs_path.find(marker)
    if idx >= 0:
        rest = abs_path[idx + len(marker) :]
        if rest == "" or rest.startswith("/"):
            return True
    return False


def _guard_path(path):
    if not path:
        return
    base = os.path.basename(path)
    if base == "os.token" or base.startswith("os.token."):
        refuse_os_token(path)
    abs_path = os.path.abspath(path)
    if under_os_state(path):
        refuse_os_token(path)
    if abs_path.startswith("/home/") or abs_path.startswith("/etc/aios/"):
        raise ProviderError("work token path is not the P8.10 lock (L-16)")


def aios_root():
    env = os.environ.get("AIOS_ROOT")
    if env is None:
        return ""
    env = env.strip()
    if not env:
        raise ProviderError("AIOS_ROOT empty")
    return os.path.abspath(env)


def work_root():
    env = os.environ.get("AIOS_WORK_SRC")
    if env is None:
        return os.path.dirname(os.path.abspath(__file__))
    env = env.strip()
    if not env:
        raise ProviderError("AIOS_WORK_SRC empty")
    return os.path.abspath(env)


def work_token_path():
    env = os.environ.get("AIOS_WORK_TOKEN")
    if env is not None:
        env = env.strip()
        if not env:
            raise ProviderError("AIOS_WORK_TOKEN empty")
        path = env
    else:
        src = os.environ.get("AIOS_WORK_SRC")
        if src is not None:
            src = src.strip()
            if not src:
                raise ProviderError("AIOS_WORK_SRC empty")
            path = os.path.join(os.path.abspath(src), ".provider", "work.token")
        else:
            root = aios_root()
            if root:
                path = root + WORK_TOKEN_PATH
            else:
                path = WORK_TOKEN_PATH
    _guard_path(path)
    if os.path.abspath(path) == OS_TOKEN_PATH:
        refuse_os_token(path)
    return path


class FixtureProvider:
    name = "fixture"

    def __init__(self, path):
        if not path:
            raise ProviderError("fixture requires a script path (L-08)")
        _guard_path(path)
        if not os.path.isfile(path):
            raise ProviderError("fixture missing: %s" % path)
        with open(path, "r", encoding="utf-8") as fh:
            self.doc = json.load(fh)
        if not isinstance(self.doc, dict):
            raise ProviderError("fixture must be a JSON object")
        self._i = 0

    def login(self):
        raise ProviderError("fixture has no live login (L-17)")

    def complete(self, messages):
        responses = self.doc.get("responses")
        if isinstance(responses, list):
            if self._i >= len(responses):
                raise ProviderError("fixture exhausted")
            text = responses[self._i]
            self._i += 1
            if isinstance(text, (dict, list)):
                return json.dumps(text)
            return str(text)
        needle = _user_text(messages)
        for turn in self.doc.get("turns") or []:
            contains = turn.get("contains")
            if contains is None or contains in needle:
                return str(turn["response"])
        if "default" in self.doc:
            return str(self.doc["default"])
        raise ProviderError("no fixture turn matched")


def load(kind=None, fixture_path=None):
    kind = (kind or os.environ.get("AIOS_PROVIDER") or "fixture").strip()
    if not kind:
        kind = "fixture"
    if kind == "fixture":
        path = fixture_path or os.environ.get("AIOS_FIXTURE")
        return FixtureProvider(path)
    if kind == "live":
        from live import LiveProvider

        return LiveProvider()
    raise ProviderError("unknown provider %s (L-08)" % kind)
