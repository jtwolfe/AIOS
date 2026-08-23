#!/usr/bin/python3
"""aios-agent driver: idle proposer (L-21). Fixture/live via CLI (P4.2)."""

import sys
import time

from deny import Denied, check

POLL_S = 60


def _denied(message):
    sys.stderr.write("denied: %s\n" % message)
    sys.stderr.flush()
    return 1


def cmd_deny(argv):
    if not argv:
        sys.stderr.write("usage: main.py deny KIND [ARGS]\n")
        return 2
    try:
        check(argv[0], *argv[1:])
    except Denied as exc:
        return _denied(str(exc))
    sys.stdout.write("ok: %s\n" % " ".join(argv))
    sys.stdout.flush()
    return 0


def serve():
    # L-21: available, not always proposing. Do not parse inputs here;
    # one malformed document must not exit the unit. Provider is CLI-only.
    while True:
        time.sleep(POLL_S)


def _provider_fail(exc):
    sys.stderr.write("denied: %s\n" % exc)
    sys.stderr.flush()
    return 1


def cmd_provider(argv):
    # Lazy import: the idle unit must not load urllib or a fixture file.
    from provider.base import OS_TOKEN_PATH, ProviderError, load

    if not argv:
        sys.stderr.write(
            "usage: main.py provider path | provider fixture complete FILE [TEXT] | provider live login\n"
        )
        return 2
    if argv[0] == "path":
        sys.stdout.write("%s\n" % OS_TOKEN_PATH)
        sys.stdout.flush()
        return 0
    if argv[0] == "live" and (len(argv) < 2 or argv[1] != "login"):
        return _provider_fail("never a pasted API key (L-17)")
    if argv[0] == "live" and argv[1] == "login":
        if len(argv) != 2:
            return _provider_fail("never a pasted API key (L-17)")
        try:
            load("live").login()
        except ProviderError as exc:
            return _provider_fail(exc)
        sys.stdout.write("ok: login\n")
        sys.stdout.flush()
        return 0
    if argv[0] == "fixture" and len(argv) >= 2 and argv[1] == "complete":
        if len(argv) < 3:
            sys.stderr.write("usage: main.py provider fixture complete FILE [TEXT]\n")
            return 2
        text = " ".join(argv[3:]) if len(argv) > 3 else ""
        try:
            out = load("fixture", fixture_path=argv[2]).complete(text)
        except ProviderError as exc:
            return _provider_fail(exc)
        sys.stdout.write("%s\n" % out)
        sys.stdout.flush()
        return 0
    return _provider_fail("unknown provider action")


def _usage():
    sys.stderr.write(
        "usage: main.py [deny KIND [ARGS] | provider path | provider fixture complete FILE [TEXT] | provider live login]\n"
    )
    return 2


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        try:
            serve()
        except KeyboardInterrupt:
            return 0
        return 0
    if argv[0] == "deny":
        return cmd_deny(argv[1:])
    if argv[0] == "provider":
        return cmd_provider(argv[1:])
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
