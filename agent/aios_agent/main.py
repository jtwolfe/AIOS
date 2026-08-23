#!/usr/bin/python3
"""aios-agent driver: idle proposer (L-21). No provider (P4.2)."""

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
    # one malformed document must not exit the unit.
    while True:
        time.sleep(POLL_S)


def _usage():
    sys.stderr.write("usage: main.py [deny KIND [ARGS]]\n")
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
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
