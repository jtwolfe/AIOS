"""Work-tree skills catalog and this-turn body load."""

import os


class Skill:
    def __init__(self, name, path, description, body):
        self.name = name
        self.path = path
        self.description = description
        self.body = body


def _fm(text):
    meta = {}
    key = None
    for line in text.splitlines():
        stripped = line.strip()
        if key and stripped.startswith("- "):
            cur = meta.get(key)
            if not isinstance(cur, list):
                meta[key] = [] if cur in (None, "") else [cur]
            meta[key].append(stripped[2:].strip())
            continue
        if ":" in stripped:
            key, value = stripped.split(":", 1)
            key = key.strip()
            value = value.strip()
            meta[key] = value if value else []
    return meta


def _split_skill(raw):
    lines = raw.splitlines(True)
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "---":
            start = i
            break
    if start is None:
        return {}, raw
    end = None
    for j in range(start + 1, len(lines)):
        if lines[j].strip() == "---":
            end = j
            break
    if end is None:
        return {}, raw
    meta = _fm("".join(lines[start + 1 : end]))
    body = "".join(lines[end + 1 :]).lstrip("\n")
    return meta, body


def _skills_dir(root):
    return os.path.join(root, "skills")


def catalog(root):
    skills_dir = _skills_dir(root)
    out = []
    if not os.path.isdir(skills_dir):
        return out
    for name in sorted(os.listdir(skills_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(skills_dir, name)
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
        meta, body = _split_skill(raw)
        skill_name = meta.get("name") or os.path.splitext(name)[0]
        description = meta.get("description") or ""
        if isinstance(description, list):
            description = " ".join(str(part) for part in description)
        out.append(Skill(str(skill_name), path, str(description), body))
    return out


def catalog_text(root):
    lines = []
    for skill in catalog(root):
        desc = skill.description.strip() or "(no description)"
        lines.append("- %s: %s" % (skill.name, desc))
    if not lines:
        return "none"
    return "\n".join(lines)


def load_body(root, name):
    want = (name or "").strip()
    if not want:
        return None
    for skill in catalog(root):
        if skill.name == want:
            return skill
    return None
