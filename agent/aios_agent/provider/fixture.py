"""Scripted turns. No network. VM default (L-08)."""

import json
import os

from provider.base import Provider, ProviderError


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


class FixtureProvider(Provider):
    name = "fixture"

    def __init__(self, path):
        if not path:
            raise ProviderError("fixture requires a script path (L-08)")
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
            return str(text)
        needle = _user_text(messages)
        for turn in self.doc.get("turns") or []:
            contains = turn.get("contains")
            if contains is None or contains in needle:
                return str(turn["response"])
        if "default" in self.doc:
            return str(self.doc["default"])
        raise ProviderError("no fixture turn matched")
