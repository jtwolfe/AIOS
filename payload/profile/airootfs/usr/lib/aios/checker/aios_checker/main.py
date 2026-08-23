#!/usr/bin/python3
"""aios-checker driver: validate proposals; merge only as aios-checker."""

import os
import sys
import time

from merge import MergeDenied, merge_to_main
from schema import ProposalSchemaError, load_proposal

PROPOSALS_DIR = "/srv/aios/state/proposals"
POLL_S = 5


def _reject(message):
    sys.stderr.write("reject: %s\n" % message)
    sys.stderr.flush()
    return 1


def cmd_validate(path):
    try:
        load_proposal(path)
    except ProposalSchemaError as exc:
        return _reject("%s: %s" % (path, exc))
    sys.stdout.write("ok: %s\n" % path)
    sys.stdout.flush()
    return 0


def cmd_merge(repo, branch, mode):
    try:
        merge_to_main(repo, branch, mode=mode)
    except MergeDenied as exc:
        return _reject(str(exc))
    sys.stdout.write("ok: merged %s into main (%s)\n" % (branch, mode))
    sys.stdout.flush()
    return 0


def serve():
    seen = {}
    while True:
        if os.path.isdir(PROPOSALS_DIR):
            try:
                names = os.listdir(PROPOSALS_DIR)
            except OSError as exc:
                sys.stderr.write("reject: proposals dir: %s\n" % exc)
                sys.stderr.flush()
                names = []
            for name in sorted(names):
                if not name.endswith(".json"):
                    continue
                path = os.path.join(PROPOSALS_DIR, name)
                try:
                    mtime = os.path.getmtime(path)
                except OSError:
                    continue
                if seen.get(path) == mtime:
                    continue
                seen[path] = mtime
                try:
                    load_proposal(path)
                except Exception as exc:
                    _reject("%s: %s" % (path, exc))
                    continue
                sys.stdout.write("ok: schema %s\n" % path)
                sys.stdout.flush()
        time.sleep(POLL_S)


def _usage():
    sys.stderr.write(
        "usage: main.py [validate FILE | merge REPO BRANCH [--mode ff-only|squash]]\n"
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
    cmd = argv[0]
    if cmd == "validate":
        if len(argv) != 2:
            return _usage()
        return cmd_validate(argv[1])
    if cmd == "merge":
        mode = "ff-only"
        args = argv[1:]
        if "--mode" in args:
            i = args.index("--mode")
            if i + 1 >= len(args):
                return _usage()
            mode = args[i + 1]
            args = args[:i] + args[i + 2 :]
        if len(args) != 2:
            return _usage()
        return cmd_merge(args[0], args[1], mode)
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
