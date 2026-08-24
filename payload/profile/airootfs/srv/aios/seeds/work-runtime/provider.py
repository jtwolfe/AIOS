"""Fixture provider. Live Grok is refused."""

import json
import os

OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"


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


def _guard_path(path):
    if not path:
        return
    base = os.path.basename(path)
    if base == "os.token" or base.startswith("os.token."):
        refuse_os_token(path)
    abs_path = os.path.abspath(path)
    if abs_path == OS_TOKEN_PATH or abs_path.startswith("/srv/aios/state/"):
        refuse_os_token(path)


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
    if kind != "fixture":
        raise ProviderError(
            "work provider is fixture (L-08); do not call live Grok (L-16)"
        )
    path = fixture_path or os.environ.get("AIOS_FIXTURE")
    return FixtureProvider(path)
