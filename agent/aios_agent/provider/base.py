"""Model provider adapter (L-08). Default is fixture so tests never pay."""

import json
import os

# L-16: aios-work cannot read this file. Not /home. Not /etc/aios (etckeeper).
OS_TOKEN_PATH = "/srv/aios/state/provider/os.token"
ACCEPT_STAMP = "/etc/aios/envelope-accepted"
ANSWERS_PATH = "/srv/aios/state/bootstrap-in-progress/answers.json"


class ProviderError(Exception):
    """Adapter cannot complete this call."""


class Provider:
    name = "base"

    def complete(self, messages):
        raise ProviderError("provider %s has no complete" % self.name)

    def login(self):
        raise ProviderError("provider %s has no login" % self.name)


def envelope_accepted(path=None):
    return os.path.exists(path or ACCEPT_STAMP)


def remotes_vetoed(path=None):
    path = path or ANSWERS_PATH
    if not os.path.isfile(path):
        return False
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    vetoes = doc.get("vetoes") or {}
    return bool(vetoes.get("remotes"))


def load(kind=None, fixture_path=None):
    kind = (kind or os.environ.get("AIOS_PROVIDER") or "fixture").strip()
    if kind == "fixture":
        from provider.fixture import FixtureProvider

        path = fixture_path or os.environ.get("AIOS_FIXTURE")
        if not path:
            raise ProviderError("fixture requires a script path (L-08)")
        return FixtureProvider(path)
    if kind == "live":
        from provider.live import LiveProvider

        return LiveProvider()
    raise ProviderError("unknown provider %s (L-08)" % kind)
