"""Work-intent socket consumer (L-05, HI-13). ACK only; never a shell."""

import json
import os
import socket
import uuid

PROD_SOCK = "/run/aios/intent.sock"
SD_LISTEN_FDS_START = 3
MAX_BYTES = 65536
READ_S = 5
WORK_INTENT_SOURCES = ("work-runtime", "work-runtime-bots")
REQUIRED = ("id", "source", "asked")
ALLOWED = REQUIRED + ("clause", "suggested_oracles", "paths")
SURFACE = "definition"


class IntentError(Exception):
    """Record is not one L-05 JSON object. Process stays up."""

    def __init__(self, reason, ident=None):
        Exception.__init__(self, reason)
        self.reason = reason
        self.ident = ident


def _ident_of(obj):
    if isinstance(obj, dict) and isinstance(obj.get("id"), str):
        return obj.get("id")
    return None


def refused(ident, reason):
    return {
        "id": ident,
        "accepted": False,
        "reason": reason,
        "surface": SURFACE,
    }


def accepted(ident):
    return {"id": ident, "accepted": True, "surface": SURFACE}


def _need_dict(value):
    if not isinstance(value, dict) or isinstance(value, list):
        raise IntentError("must be an object (HI-13)", _ident_of(value))
    return value


def _need_str(value, what, ident, *, allow_empty=False):
    if not isinstance(value, str) or isinstance(value, bool):
        raise IntentError("%s must be a string" % what, ident)
    if not allow_empty and not value.strip():
        raise IntentError("%s must be non-empty" % what, ident)
    return value


def _need_str_list(value, what, ident):
    if isinstance(value, (str, bytes, dict)) or not isinstance(value, list):
        raise IntentError("%s must be a list" % what, ident)
    out = []
    for i, item in enumerate(value):
        out.append(_need_str(item, "%s[%s]" % (what, i), ident))
    return out


def _uuid4(value, ident):
    raw = _need_str(value, "id", ident)
    try:
        parsed = uuid.UUID(raw)
    except (ValueError, AttributeError, TypeError) as exc:
        raise IntentError("id must be a UUID", ident) from exc
    if parsed.version != 4:
        raise IntentError("id must be a UUID version 4", ident)
    return str(parsed)


def validate_work_intent(obj):
    # Same fields as intent/schema.json. HI-02: do not import the checker.
    data = _need_dict(obj)
    ident = _ident_of(data)
    extra = set(data) - set(ALLOWED)
    if extra:
        raise IntentError(
            "unknown field %s (HI-13)" % ", ".join(sorted(extra)), ident
        )
    missing = [k for k in REQUIRED if k not in data]
    if missing:
        raise IntentError("missing %s" % ", ".join(missing), ident)
    ident = _uuid4(data["id"], ident)
    source = _need_str(data["source"], "source", ident)
    if source not in WORK_INTENT_SOURCES:
        raise IntentError(
            "source must be work-runtime or work-runtime-bots (HI-13)", ident
        )
    asked = _need_str(data["asked"], "asked", ident)
    clause = data.get("clause", None)
    if clause is not None:
        clause = _need_str(clause, "clause", ident)
    oracles = data.get("suggested_oracles", [])
    if "suggested_oracles" in data:
        oracles = _need_str_list(oracles, "suggested_oracles", ident)
    paths = data.get("paths", [])
    if "paths" in data:
        paths = _need_str_list(paths, "paths", ident)
    return {
        "id": ident,
        "source": source,
        "asked": asked,
        "clause": clause,
        "suggested_oracles": oracles,
        "paths": paths,
    }


def consume_bytes(raw):
    """Return an ACK dict, or None on empty hangup. Never raises."""
    if raw is None:
        return None
    if not isinstance(raw, (bytes, bytearray)):
        return refused(None, "not UTF-8")
    if not raw.strip():
        return None
    try:
        text = bytes(raw).decode("utf-8")
    except UnicodeDecodeError:
        return refused(None, "not UTF-8")
    text = text.lstrip("\ufeff").strip()
    if not text:
        return None
    try:
        obj, _idx = json.JSONDecoder().raw_decode(text)
    except json.JSONDecodeError:
        return refused(None, "not JSON")
    except RecursionError:
        return refused(None, "JSON too deeply nested")
    except ValueError:
        return refused(None, "not JSON")
    try:
        record = validate_work_intent(obj)
    except IntentError as exc:
        return refused(exc.ident, exc.reason)
    except Exception:
        return refused(_ident_of(obj) if isinstance(obj, dict) else None, "invalid intent")
    return accepted(record["id"])


def _read_one(conn):
    buf = bytearray()
    decoder = json.JSONDecoder()
    conn.settimeout(READ_S)
    while len(buf) < MAX_BYTES:
        try:
            chunk = conn.recv(min(4096, MAX_BYTES - len(buf)))
        except socket.timeout:
            break
        except OSError:
            break
        if not chunk:
            break
        buf.extend(chunk)
        try:
            text = buf.decode("utf-8")
        except UnicodeDecodeError as exc:
            if exc.reason == "unexpected end of data":
                continue
            return refused(None, "not UTF-8")
        stripped = text.lstrip("\ufeff").lstrip()
        if not stripped:
            continue
        try:
            obj, _idx = decoder.raw_decode(stripped)
        except json.JSONDecodeError:
            continue
        except RecursionError:
            return refused(None, "JSON too deeply nested")
        try:
            record = validate_work_intent(obj)
        except IntentError as exc:
            return refused(exc.ident, exc.reason)
        except Exception:
            return refused(_ident_of(obj) if isinstance(obj, dict) else None, "invalid intent")
        return accepted(record["id"])
    if not buf.strip():
        return None
    return consume_bytes(bytes(buf))


def handle_connection(conn):
    ack = None
    try:
        ack = _read_one(conn)
    except Exception:
        ack = refused(None, "invalid intent")
    if ack is None:
        return
    try:
        conn.sendall((json.dumps(ack) + "\n").encode("utf-8"))
    except OSError:
        return


def listen_socket():
    """Inherit LISTEN_FDS, or bind AIOS_INTENT_SOCK. Never bind the prod path."""
    raw_fds = os.environ.get("LISTEN_FDS", "")
    try:
        n = int(raw_fds) if raw_fds else 0
    except ValueError:
        n = 0
    pid_raw = os.environ.get("LISTEN_PID", "")
    pid_ok = True
    if pid_raw:
        try:
            pid_ok = int(pid_raw) == os.getpid()
        except ValueError:
            pid_ok = False
    if n >= 1 and pid_ok:
        try:
            return socket.socket(fileno=SD_LISTEN_FDS_START)
        except OSError:
            return None
    path = os.environ.get("AIOS_INTENT_SOCK", "")
    if not path or path == PROD_SOCK:
        return None
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        try:
            os.unlink(path)
        except OSError:
            pass
        sock.bind(path)
        sock.listen(32)
    except OSError:
        try:
            sock.close()
        except OSError:
            pass
        return None
    return sock
