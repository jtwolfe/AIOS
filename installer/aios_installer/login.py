"""One non-root operator login on accept (L-13). No enact sudo."""

import os
import shutil
import subprocess
import time

import questions

UID_MIN = 1000
UID_MAX = 60000
NOLOGIN = frozenset(("nologin", "false", "true"))


def dest_root():
    # Host oracles mutate live passwd if this defaults to /.
    env = os.environ.get("AIOS_ROOT")
    if env is not None:
        env = env.strip()
        if not env:
            raise OSError("AIOS_ROOT empty")
        return os.path.abspath(env)
    if _is_live_iso():
        raise OSError("refuse host mutation on live ISO")
    if _is_disk_installer():
        return "/"
    raise OSError("AIOS_ROOT required off the installed disk")


def _writes_frozen():
    env = os.environ.get("AIOS_BRAKE")
    if env:
        return os.path.isfile(env)
    # Oracles set AIOS_ROOT; do not read the workstation brake file.
    if os.environ.get("AIOS_ROOT"):
        return False
    return os.path.isfile("/srv/aios/state/brake")


def enact(name):
    if not questions.valid_login(name):
        raise ValueError("invalid operator login")
    if _writes_frozen():
        raise OSError("writes frozen (L-12)")
    root = dest_root()
    if root != "/":
        os.makedirs(root, exist_ok=True)
    _create_user(root, name)
    _write_autologin(root, name)
    _write_operator_stamp(root, name)
    _release_console(root)
    if not _operator_complete(root, name):
        raise OSError("operator login missing after create (L-13)")


def cmdline_is_archiso(text):
    for tok in (text or "").split():
        if tok == "archisobasedir" or tok.startswith("archisobasedir="):
            return True
    return False


def _is_live_iso():
    if os.path.isdir("/run/archiso"):
        return True
    try:
        with open("/proc/cmdline", encoding="utf-8", errors="replace") as fh:
            return cmdline_is_archiso(fh.read())
    except OSError:
        return False


def _is_disk_installer():
    # Accept deletes the wants link. firstboot's /etc/aios and the
    # installer binary survive mask; live ISO is refused separately.
    if not os.path.isfile("/usr/lib/aios/bin/installer"):
        return False
    return os.path.isdir("/etc/aios")


def _under(root, *parts):
    if any(p.startswith("/") or p in (os.pardir, os.curdir) or os.sep in p for p in parts):
        raise OSError("path escapes AIOS_ROOT")
    root_abs = os.path.abspath(root)
    path = os.path.abspath(os.path.join(root_abs, *parts))
    if root_abs == os.sep:
        return path
    if path == root_abs or path.startswith(root_abs + os.sep):
        return path
    raise OSError("path escapes AIOS_ROOT")


def _atomic_write(path, text, mode=None):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    if not isinstance(text, str):
        text = str(text)
    if not text.endswith("\n"):
        text = text + "\n"
    tmp = "%s.tmp" % path
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(tmp, flags, 0o600 if mode is None else mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fd = None
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except Exception:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def _colon_records(path):
    text = _read(path)
    if text is None:
        return []
    rows = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(":")
        if fields and fields[0]:
            rows.append(fields)
    return rows


def _passwd_record(root, name):
    path = _under(root, "etc", "passwd")
    for fields in _colon_records(path):
        if fields[0] == name:
            return fields
    return None


def _named_in(root, *rel, name=""):
    for fields in _colon_records(_under(root, *rel)):
        if fields[0] == name:
            return True
    return False


def _uid_of(fields):
    if len(fields) < 3:
        return None
    try:
        uid = int(fields[2])
    except ValueError:
        return None
    if isinstance(uid, bool):
        return None
    return uid


def _gid_of(fields):
    if len(fields) < 4:
        return None
    try:
        gid = int(fields[3])
    except ValueError:
        return None
    if isinstance(gid, bool):
        return None
    return gid


def _is_human_shell(shell):
    base = os.path.basename((shell or "").rstrip("/"))
    return base not in NOLOGIN


def _is_human_login(fields):
    uid = _uid_of(fields)
    if uid is None or uid < UID_MIN or uid >= 65534:
        return False
    shell = fields[6] if len(fields) > 6 else ""
    return _is_human_shell(shell)


def _operator_complete(root, name):
    fields = _passwd_record(root, name)
    if fields is None or not _is_human_login(fields):
        return False
    if not _named_in(root, "etc", "shadow", name=name):
        return False
    if not _named_in(root, "etc", "group", name=name):
        return False
    return os.path.isdir(_under(root, "home", name))


def _other_humans(root, name):
    found = []
    for fields in _colon_records(_under(root, "etc", "passwd")):
        login = fields[0]
        if login == name:
            continue
        if _is_human_login(fields):
            found.append(login)
    return found


def _used_ids(root, index):
    used = set()
    for rel in (("etc", "passwd"), ("etc", "group")):
        for fields in _colon_records(_under(root, *rel)):
            if len(fields) <= index:
                continue
            try:
                value = int(fields[index])
            except ValueError:
                continue
            used.add(value)
    return used


def _next_id(used):
    n = UID_MIN
    while n in used and n <= UID_MAX:
        n += 1
    if n > UID_MAX:
        raise OSError("no free uid/gid in human range (L-13)")
    return n


def _useradd(root, name):
    exe = shutil.which("useradd")
    if not exe:
        return False
    cmd = [exe]
    if root != "/":
        cmd.extend(["--root", root])
    cmd.extend(["-m", "-U", "-s", "/bin/bash", name])
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return proc.returncode == 0


def _ensure_line(path, name, line, mode):
    existing = _read(path)
    rows = []
    if existing is not None:
        for old in existing.splitlines():
            if not old:
                continue
            if old.split(":")[0] == name:
                continue
            rows.append(old)
    rows.append(line)
    text = "\n".join(rows) + "\n"
    _atomic_write(path, text, mode=mode)


def _write_user_records(root, name):
    fields = _passwd_record(root, name)
    if fields is None:
        used = _used_ids(root, 2)
        uid = _next_id(used)
        gid = uid
    else:
        uid = _uid_of(fields)
        gid = _gid_of(fields)
        if uid is None:
            uid = _next_id(_used_ids(root, 2))
        if gid is None:
            gid = uid
    days = int(time.time() // 86400)
    passwd = _under(root, "etc", "passwd")
    shadow = _under(root, "etc", "shadow")
    group = _under(root, "etc", "group")
    gshadow = _under(root, "etc", "gshadow")
    passwd_mode = 0o644
    shadow_mode = 0o400
    group_mode = 0o644
    gshadow_mode = 0o400
    if os.path.isfile(passwd):
        passwd_mode = stat_mode(passwd, passwd_mode)
    if os.path.isfile(shadow):
        shadow_mode = stat_mode(shadow, shadow_mode)
    if os.path.isfile(group):
        group_mode = stat_mode(group, group_mode)
    if os.path.isfile(gshadow):
        gshadow_mode = stat_mode(gshadow, gshadow_mode)
    if fields is None:
        _ensure_line(
            passwd,
            name,
            "%s:x:%s:%s::/home/%s:/bin/bash" % (name, uid, gid, name),
            passwd_mode,
        )
    _ensure_line(
        group,
        name,
        "%s:x:%s:" % (name, gid),
        group_mode,
    )
    _ensure_line(
        gshadow,
        name,
        "%s:!::" % name,
        gshadow_mode,
    )
    _ensure_line(
        shadow,
        name,
        "%s:!:%s:0:99999:7:::" % (name, days),
        shadow_mode,
    )
    home = _under(root, "home", name)
    os.makedirs(home, exist_ok=True)
    try:
        os.chmod(home, 0o700)
    except OSError:
        pass
    # Oracles are unprivileged under AIOS_ROOT; production owns the home.
    if root == "/" and not os.environ.get("AIOS_ROOT"):
        try:
            os.chown(home, uid, gid)
        except OSError:
            pass


def stat_mode(path, default):
    try:
        return stat_perm(os.stat(path).st_mode)
    except OSError:
        return default


def stat_perm(mode):
    return mode & 0o7777


def _create_user(root, name):
    existing = _passwd_record(root, name)
    if existing is not None and not _is_human_login(existing):
        raise ValueError("operator login is a service uid (L-13)")
    if _operator_complete(root, name):
        return
    others = _other_humans(root, name)
    if others:
        raise ValueError("one operator login (L-13)")
    # Production on the installed disk uses useradd. Oracles write the
    # same files so a missing useradd cannot mutate the workstation.
    if existing is None and root == "/" and not os.environ.get("AIOS_ROOT"):
        _useradd("/", name)
    _write_user_records(root, name)


def _write_autologin(root, name):
    if not questions.valid_login(name):
        raise ValueError("invalid operator login")
    tty1 = _under(
        root, "etc", "systemd", "system", "getty@tty1.service.d", "autologin.conf"
    )
    serial = _under(
        root,
        "etc",
        "systemd",
        "system",
        "serial-getty@ttyS0.service.d",
        "autologin.conf",
    )
    _atomic_write(
        tty1,
        "[Service]\n"
        "ExecStart=\n"
        "ExecStart=-/usr/bin/agetty --noreset --noclear --autologin %s - ${TERM}\n"
        % name,
        mode=0o644,
    )
    _atomic_write(
        serial,
        "[Service]\n"
        "ExecStart=\n"
        "ExecStart=-/usr/bin/agetty --noreset --noclear --autologin %s "
        "--keep-baud 115200,57600,38400,9600 - ${TERM}\n" % name,
        mode=0o644,
    )


def _unlink_if_exists(path):
    if os.path.lexists(path):
        os.unlink(path)


def _is_devnull_mask(path):
    if not os.path.islink(path):
        return False
    try:
        return os.readlink(path) == "/dev/null"
    except OSError:
        return False


def _mask_installer(root):
    # Mask only under /etc. Do not move the unit into /usr (HI-04).
    etc_unit = _under(root, "etc", "systemd", "system", "aios-installer.service")
    wants = _under(
        root,
        "etc",
        "systemd",
        "system",
        "multi-user.target.wants",
        "aios-installer.service",
    )
    _unlink_if_exists(wants)
    if os.path.lexists(etc_unit) and not _is_devnull_mask(etc_unit):
        _unlink_if_exists(etc_unit)
    if not os.path.lexists(etc_unit):
        os.makedirs(os.path.dirname(etc_unit), exist_ok=True)
        os.symlink("/dev/null", etc_unit)


def _unmask_getty(root, unit):
    path = _under(root, "etc", "systemd", "system", unit)
    if _is_devnull_mask(path):
        os.unlink(path)


def _enable_getty(root, instance, template):
    wants_dir = _under(root, "etc", "systemd", "system", "getty.target.wants")
    os.makedirs(wants_dir, exist_ok=True)
    link = os.path.join(wants_dir, instance)
    target = "/usr/lib/systemd/system/%s" % template
    if os.path.lexists(link):
        return
    os.symlink(target, link)


def _write_operator_stamp(root, name):
    # Survives installer mask. Not the L-20 human-accept stamp.
    _atomic_write(_under(root, "etc", "aios", "operator"), name, mode=0o644)


def _release_console(root):
    # After accept the installer must not own the console (L-09, L-13).
    _mask_installer(root)
    _unmask_getty(root, "getty@tty1.service")
    _unmask_getty(root, "serial-getty@ttyS0.service")
    _enable_getty(root, "getty@tty1.service", "getty@.service")
    _enable_getty(root, "serial-getty@ttyS0.service", "serial-getty@.service")
    if root == "/" and not os.environ.get("AIOS_ROOT"):
        _systemctl(["disable", "aios-installer.service"])
        _systemctl(["mask", "aios-installer.service"])
        _systemctl(["unmask", "getty@tty1.service", "serial-getty@ttyS0.service"])
        _systemctl(["enable", "getty@tty1.service", "serial-getty@ttyS0.service"])


def handoff_console():
    # Start operator gettys this boot. --no-block: Conflicts would wait
    # for this process to exit.
    if os.environ.get("AIOS_ROOT"):
        return
    if _writes_frozen():
        return
    if _is_live_iso():
        return
    if not _is_disk_installer():
        return
    _systemctl(["daemon-reload"])
    exe = shutil.which("systemctl")
    if not exe:
        return
    try:
        subprocess.Popen(
            [
                exe,
                "start",
                "--no-block",
                "getty@tty1.service",
                "serial-getty@ttyS0.service",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError):
        return


def _systemctl(args):
    exe = shutil.which("systemctl")
    if not exe:
        return
    try:
        subprocess.run(
            [exe] + list(args),
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return
