#!/usr/bin/python3
"""aios-agent driver: idle proposer (L-21). Turns and goals via CLI."""

import select
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
    # L-21: available, not always proposing. Turns are CLI (`turn`).
    # Socket consume+ACK (L-05). Login and L-19 rollback gates tick inside POLL_S.
    from intent_consume import handle_connection, listen_socket

    sock = listen_socket()
    while True:
        try:
            from login_gate import tick_login

            tick_login()
        except Exception:
            pass
        try:
            from rollback_gate import tick_rollback

            tick_rollback()
        except Exception:
            pass
        try:
            from bots_gate import tick_bots

            tick_bots()
        except Exception:
            pass
        if sock is None:
            try:
                from login_gate import drain_slice

                drain_slice(POLL_S)
            except Exception:
                time.sleep(POLL_S)
            continue
        try:
            ready, _, _ = select.select([sock], [], [], POLL_S)
        except (OSError, ValueError):
            time.sleep(POLL_S)
            continue
        if not ready:
            continue
        conn = None
        try:
            conn, _peer = sock.accept()
        except OSError:
            continue
        try:
            handle_connection(conn)
        except Exception:
            pass
        finally:
            if conn is not None:
                try:
                    conn.close()
                except OSError:
                    pass

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


def cmd_turn(argv):
    # Lazy import: the idle unit must not load a fixture or walk skills.
    from loop import cmd_turn as _turn

    return _turn(argv)


def cmd_goals(argv):
    # Lazy import: the idle unit must not load goals.json on a malformed wake.
    from goals import cmd_goals as _goals

    return _goals(argv)


def _usage():
    sys.stderr.write(
        "usage: main.py [deny KIND [ARGS] | provider path | provider fixture complete FILE [TEXT] | provider live login | turn [--accept ID] [TEXT] | goals [tick [JSON|FILE] | gap FINGERPRINT | infra KIND]]\n"
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
    if argv[0] == "turn":
        return cmd_turn(argv[1:])
    if argv[0] == "goals":
        return cmd_goals(argv[1:])
    return _usage()


if __name__ == "__main__":
    sys.exit(main())
