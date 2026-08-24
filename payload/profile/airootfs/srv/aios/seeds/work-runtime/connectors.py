"""MCP-preferred connectors. Discover, then call. Secrets stay off chat."""

import json
import os
import re

from provider import OS_TOKEN_PATH, refuse_os_token


class ConnectorError(Exception):
    """Connector surface cannot complete this call."""


class Connector:
    def __init__(self, name, path, doc):
        self.name = name
        self.path = path
        self.doc = doc

    @property
    def service(self):
        return str(self.doc.get("service") or self.name).strip().lower()

    @property
    def status(self):
        return str(self.doc.get("status") or "disconnected").strip().lower()

    @property
    def tools(self):
        tools = self.doc.get("tools")
        if isinstance(tools, list):
            return tools
        schema = self.doc.get("schema")
        if isinstance(schema, dict) and isinstance(schema.get("tools"), list):
            return schema["tools"]
        return []


_AUTH_CHAT = re.compile(
    r"https://auth\.x\.ai/\S+|https://[^\s]+/oauth(?:2)?/authorize\S*",
    re.IGNORECASE,
)
_CHAT_SECRETS = (
    "access_token=",
    "refresh_token=",
    "api_key=",
    "authorization: bearer ",
    "xai_api_key",
)


def chat_secret_error(text):
    raw = text if isinstance(text, str) else str(text or "")
    if not raw:
        return None
    lower = raw.lower()
    for needle in _CHAT_SECRETS:
        if needle in lower:
            return "token in chat fails (P8.6)"
    if _AUTH_CHAT.search(raw):
        return "do not paste authorization links into chat (P8.6)"
    return None


def _connectors_dir(root):
    env = os.environ.get("AIOS_WORK_CONNECTORS")
    if env is not None:
        env = env.strip()
        if not env:
            raise ConnectorError("AIOS_WORK_CONNECTORS empty")
        path = env
    else:
        path = os.path.join(root, "connectors")
    if os.path.abspath(path) == OS_TOKEN_PATH:
        refuse_os_token(path)
    if "/srv/aios/state/" in os.path.abspath(path).replace("\\", "/"):
        refuse_os_token(path)
    return path


def _read_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if not isinstance(doc, dict):
        raise ConnectorError("connector must be a JSON object: %s" % path)
    return doc


def _stem(name):
    base = os.path.basename(name)
    if base.endswith(".json"):
        base = base[: -len(".json")]
    return base


def load_all(root):
    folder = _connectors_dir(root)
    out = []
    if not os.path.isdir(folder):
        return out
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        doc = _read_json(path)
        conn_name = str(doc.get("name") or _stem(name))
        out.append(Connector(conn_name, path, doc))
    return out


def _host(url):
    raw = (url or "").strip().lower()
    if "://" in raw:
        rest = raw.split("://", 1)[1]
        rest = rest.split("/", 1)[0]
        rest = rest.split(":", 1)[0]
        if rest.startswith("www."):
            rest = rest[4:]
        return rest
    return raw


def _service_key(value):
    host = _host(value)
    if host:
        return host
    return str(value or "").strip().lower()


def connector_for_service(connectors, service, url=""):
    want = _service_key(url or service)
    if not want:
        return None
    for conn in connectors:
        keys = (conn.service, conn.name.lower())
        for key in keys:
            if not key:
                continue
            if want == key:
                return conn
            # Host suffix only: "api.example.com" vs "example.com", not
            # connector name "example" vs "none.example".
            if "." in key and "." in want:
                if want.endswith("." + key) or key.endswith("." + want):
                    return conn
    return None


class ConnectorSession:
    def __init__(self, root):
        self.root = root
        self.available = {c.name: c for c in load_all(root)}
        self.discovered = set()
        self.installed_this_turn = set()
        self.results = []
        self.cards = []

    def _require_available(self, name):
        want = (name or "").strip()
        if not want:
            raise ConnectorError("connector name missing")
        if want in self.installed_this_turn:
            raise ConnectorError(
                "newly installed connectors are available on the next message"
            )
        conn = self.available.get(want)
        if conn is None:
            raise ConnectorError("unknown connector %s" % want)
        return conn

    def discover(self, name):
        conn = self._require_available(name)
        self.discovered.add(conn.name)
        schema = {
            "name": conn.name,
            "service": conn.service,
            "status": conn.status,
            "tools": conn.tools,
        }
        return json.dumps(schema)

    def connect(self, name):
        conn = self._require_available(name)
        card = conn.doc.get("connect")
        if not isinstance(card, dict):
            raise ConnectorError("no connect card for %s" % conn.name)
        out = {
            "kind": "connect_card",
            "connector": conn.name,
        }
        for key in ("verification_uri", "verification_url", "user_code"):
            if key in card:
                out[key] = card[key]
        if "verification_uri" not in out and out.get("verification_url"):
            out["verification_uri"] = out["verification_url"]
        dumped = json.dumps(card).lower()
        if "access_token" in dumped or "refresh_token" in dumped:
            raise ConnectorError("connect card must not carry a token (P8.6)")
        self.cards.append(out)
        return out

    def call(self, name, tool, arguments=None):
        conn = self._require_available(name)
        if conn.name not in self.discovered:
            raise ConnectorError("discover schema, then call")
        if conn.status not in ("connected", "ok", "ready"):
            raise ConnectorError("connect card required for %s" % conn.name)
        tool_name = (tool or "").strip()
        if not tool_name:
            raise ConnectorError("connector tool missing")
        known = []
        for item in conn.tools:
            if isinstance(item, dict) and item.get("name"):
                known.append(str(item["name"]))
            elif isinstance(item, str):
                known.append(item)
        if known and tool_name not in known:
            raise ConnectorError("unknown tool %s on %s" % (tool_name, conn.name))
        args = arguments if isinstance(arguments, dict) else {}
        err = chat_secret_error(json.dumps(args))
        if err:
            raise ConnectorError(err)
        calls = conn.doc.get("calls")
        result = None
        if isinstance(calls, dict) and tool_name in calls:
            result = calls[tool_name]
        elif "default" in conn.doc:
            result = conn.doc.get("default")
        else:
            result = {"ok": True, "tool": tool_name, "arguments": args}
        if isinstance(result, (dict, list)):
            text = json.dumps(result)
        else:
            text = str(result)
        record = {
            "connector": conn.name,
            "tool": tool_name,
            "result": result,
        }
        self.results.append(record)
        return text

    def install(self, spec):
        if isinstance(spec, str):
            raw = spec.strip()
            if not raw:
                raise ConnectorError("connector install missing spec")
            try:
                doc = json.loads(raw)
            except ValueError:
                raise ConnectorError("connector install spec is not JSON")
        elif isinstance(spec, dict):
            doc = spec
        else:
            raise ConnectorError("connector install spec is not JSON")
        if not isinstance(doc, dict):
            raise ConnectorError("connector install spec is not a JSON object")
        name = str(doc.get("name") or "").strip()
        if not name:
            raise ConnectorError("connector install missing name")
        folder = _connectors_dir(self.root)
        os.makedirs(folder, mode=0o700, exist_ok=True)
        path = os.path.join(folder, "%s.json" % name)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, path)
        self.installed_this_turn.add(name)
        return name

    def browser(self, service, url=""):
        hit = connector_for_service(list(self.available.values()), service, url)
        if hit is not None:
            raise ConnectorError(
                "If a Connector exists for a service, use it. Browser is fallback."
            )
        target = url or service or ""
        err = chat_secret_error(target)
        if err:
            raise ConnectorError(err)
        return "browser-fallback:%s" % target
