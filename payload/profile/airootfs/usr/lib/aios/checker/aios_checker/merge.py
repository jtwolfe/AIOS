"""Merge gate: only aios-checker may fast-forward or squash-merge to main (HI-02, HI-03)."""

import os
import pwd
import subprocess

ALLOWED_MODES = ("ff-only", "squash")


class MergeDenied(Exception):
    """This process may not update main."""


def aios_checker_uid():
    try:
        return pwd.getpwnam("aios-checker").pw_uid
    except KeyError as exc:
        raise MergeDenied("aios-checker sysuser missing (L-02)") from exc


def is_checker_uid(uid=None):
    if uid is None:
        uid = os.getuid()
    return int(uid) == aios_checker_uid()


def assert_merge_permitted(mode="ff-only"):
    # HI-02 / HI-03: only this uid may move refs/heads/main, and never by force.
    if mode not in ALLOWED_MODES:
        raise MergeDenied(
            "main accepts only fast-forward or squash merge (HI-03)"
        )
    if not is_checker_uid():
        raise MergeDenied(
            "only aios-checker uid may merge to main (HI-02, HI-03)"
        )


def merge_to_main(repo, branch, mode="ff-only"):
    assert_merge_permitted(mode)
    if not repo or not branch:
        raise MergeDenied("repo and branch are required")
    branch = str(branch)
    if branch in ("main", "refs/heads/main"):
        raise MergeDenied("refusing to merge main into itself")
    repo = os.path.abspath(repo)
    if not os.path.exists(repo):
        raise MergeDenied("repo missing: %s" % repo)
    if mode == "ff-only":
        args = ["git", "-C", repo, "merge", "--ff-only", "--no-edit", branch]
    else:
        args = ["git", "-C", repo, "merge", "--squash", branch]
    try:
        subprocess.run(args, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise MergeDenied("git missing") from exc
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or exc.stdout or str(exc)).strip()
        raise MergeDenied(err) from exc
    if mode == "squash":
        try:
            subprocess.run(
                [
                    "git",
                    "-C",
                    repo,
                    "commit",
                    "--no-edit",
                    "-m",
                    "squash merge to main",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except FileNotFoundError as exc:
            raise MergeDenied("git missing") from exc
        except subprocess.CalledProcessError as exc:
            err = (exc.stderr or exc.stdout or str(exc)).strip()
            raise MergeDenied(err) from exc
