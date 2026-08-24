"""Proposer deny-list (HI-03, HI-04, HI-06, L-04, L-12)."""


class Denied(Exception):
    """This uid may not perform that action."""


# HI-06: disabling these to make a change easier is not a shortcut.
SEATBELT_UNITS = (
    "aios-checker.service",
    "snapper-timeline.timer",
    "snapper-cleanup.timer",
    "etckeeper.timer",
    "etckeeper.service",
)

# L-12: only the human brake stops the proposer.
SELF_UNIT = "aios-agent.service"

# L-23: work-runtime is a user unit; never a system unit via enact.
USER_UNITS = (
    "aios-work-runtime.service",
    "aios-work-runtime-bots.service",
)

# Verbs enact will exec. restart/kill are named only so seatbelt checks fire.
ALLOWED_UNIT_ACTIONS = (
    "enable",
    "disable",
    "start",
    "stop",
    "mask",
    "unmask",
    "is-enabled",
    "is-active",
)

_DESTRUCTIVE = (
    "disable",
    "mask",
    "stop",
    "restart",
    "try-restart",
    "reload",
    "reload-or-restart",
    "kill",
)

_AIOS_SUFFIXES = (
    ".service",
    ".socket",
    ".timer",
    ".slice",
    ".target",
    ".path",
)


def unit_basename(unit):
    name = unit.strip()
    if "/" in name:
        name = name.rsplit("/", 1)[-1]
    return name


def is_aios_unit(unit):
    if not unit or "/" in unit or " " in unit or ".." in unit:
        return False
    if not unit.startswith("aios-"):
        return False
    return unit.endswith(_AIOS_SUFFIXES)


def check_unit(action, unit):
    unit = unit_basename(unit)
    if unit in USER_UNITS:
        raise Denied("%s is a user unit (L-23)" % unit)
    if action in _DESTRUCTIVE and unit in SEATBELT_UNITS:
        raise Denied("cannot %s %s (HI-06)" % (action, unit))
    if action in _DESTRUCTIVE and unit == SELF_UNIT:
        raise Denied("cannot %s %s (L-12 human brake only)" % (action, unit))
    if action not in ALLOWED_UNIT_ACTIONS:
        raise Denied("unit action not allowlisted: %s" % action)
    if not is_aios_unit(unit):
        raise Denied("unit is not an aios-* unit: %s" % unit)


def check(kind, *args):
    if kind in ("merge-main", "merge_to_main"):
        raise Denied("cannot merge to main (HI-03)")
    if kind in ("force-push", "force_push"):
        raise Denied("cannot force-push published refs (HI-03)")
    if kind in ("curl-sh", "curl_sh"):
        raise Denied("cannot fetch-pipe-to-shell (HI-04)")
    if kind in ("pacman-partial",):
        raise Denied("partial pacman is not allowlisted (L-04)")
    if kind in ("usr-mutate",):
        raise Denied("cannot mutate /usr outside pacman (HI-04)")
    if kind == "unit":
        if len(args) != 2:
            raise Denied("unit takes ACTION UNIT")
        check_unit(args[0], args[1])
        return
    if kind in ("synthesise", "synthesize"):
        from goals import bots_yes, work_runtime_yes

        target = args[0] if args else "work-runtime"
        if target == "work-runtime-bots":
            if not bots_yes():
                raise Denied("bots stay off until an explicit yes (HI-15)")
            return
        if target != "work-runtime":
            raise Denied("not allowlisted: synthesise %s (HI-15)" % target)
        if not work_runtime_yes():
            raise Denied(
                "work runtime stays off until an explicit yes (HI-15)"
            )
        return
    if kind == "disable":
        target = args[0] if args else "work-runtime"
        if target != "work-runtime":
            raise Denied("not allowlisted: disable %s (HI-15)" % target)
        return
    if kind == "enable":
        from goals import work_runtime_yes

        target = args[0] if args else ""
        if target != "work-runtime-bots":
            raise Denied("not allowlisted: enable %s (HI-15)" % target)
        if not work_runtime_yes():
            raise Denied("bots stay off until work-runtime is yes (HI-15)")
        return
    raise Denied("unknown action not allowlisted: %s" % kind)
