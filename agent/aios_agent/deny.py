"""Proposer deny-list (HI-03, HI-04, HI-06, L-04, L-12)."""


class Denied(Exception):
    """This uid may not perform that action."""


# HI-06: disabling these to make a change easier is not a shortcut.
SEATBELT_UNITS = (
    "aios-checker.service",
    "snapper-timeline.timer",
    "snapper-cleanup.timer",
)

# L-12: only the human brake stops the proposer.
SELF_UNIT = "aios-agent.service"

# L-23: work-runtime is a user unit; never a system unit via enact.
USER_UNITS = (
    "aios-work-runtime.service",
    "aios-work-runtime-bots.service",
)

_DESTRUCTIVE = ("disable", "mask", "stop")


def check_unit(action, unit):
    if unit in USER_UNITS:
        raise Denied("%s is a user unit (L-23)" % unit)
    if action in _DESTRUCTIVE and unit in SEATBELT_UNITS:
        raise Denied("cannot %s %s (HI-06)" % (action, unit))
    if action in _DESTRUCTIVE and unit == SELF_UNIT:
        raise Denied("cannot %s %s (L-12 human brake only)" % (action, unit))


def check(kind, *args):
    if kind in ("merge-main", "merge_to_main"):
        raise Denied("cannot merge to main (HI-03)")
    if kind in ("force-push", "force_push"):
        raise Denied("cannot force-push published refs (HI-03)")
    if kind in ("curl-sh", "curl_sh"):
        raise Denied("cannot fetch-pipe-to-shell (HI-04)")
    if kind in ("pacman-partial",):
        raise Denied("partial pacman -S is not allowlisted (L-04, HI-06)")
    if kind in ("usr-mutate",):
        raise Denied("cannot mutate /usr outside pacman (HI-04)")
    if kind == "unit":
        if len(args) != 2:
            raise Denied("unit takes ACTION UNIT")
        check_unit(args[0], args[1])
        return
    raise Denied("unknown action not allowlisted: %s" % kind)
