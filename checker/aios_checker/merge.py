"""Merge gate: only aios-checker may fast-forward or squash-merge to main (HI-02, HI-03)."""

import os
import pwd
import shutil
import subprocess
import tempfile

ALLOWED_MODES = ("ff-only", "squash")
MAIN_REF = "refs/heads/main"
BARE_ROOT = "/srv/aios/git"
KNOWN_REPOS = (
    "envelope",
    "memory",
    "skills",
    "agent",
    "checker",
    "state",
    "seeds",
)
CHECKER_NAME = "aios-checker"
CHECKER_EMAIL = "aios-checker@localhost"


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
    if mode not in ALLOWED_MODES:
        raise MergeDenied(
            "main accepts only fast-forward or squash merge (HI-03)"
        )
    if not is_checker_uid():
        raise MergeDenied(
            "only aios-checker uid may merge to main (HI-02, HI-03)"
        )


def _run_git(args, *, git_dir=None, cwd=None, env=None):
    cmd = ["git"]
    if git_dir is not None:
        cmd.extend(["--git-dir", git_dir])
    cmd.extend(args)
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    try:
        proc = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
            cwd=cwd,
            env=run_env,
        )
    except FileNotFoundError as exc:
        raise MergeDenied("git missing") from exc
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or exc.stdout or str(exc)).strip()
        raise MergeDenied(err or "git failed") from exc
    return proc.stdout.strip()


def _bare_git_dir(repo):
    # L-03: only the checker-owned bare repo is writable by this uid.
    raw = str(repo).rstrip("/")
    name = None
    if raw in KNOWN_REPOS:
        name = raw
    else:
        path = os.path.abspath(raw)
        base = os.path.basename(path)
        if base.endswith(".git"):
            cand = base[:-4]
            if cand in KNOWN_REPOS:
                name = cand
        elif base in KNOWN_REPOS:
            name = base
    if name is None:
        raise MergeDenied("unknown repo %s (HI-12)" % repo)
    bare = os.path.join(BARE_ROOT, "%s.git" % name)
    if not os.path.isdir(os.path.join(bare, "objects")):
        raise MergeDenied("bare repo missing: %s" % bare)
    return os.path.abspath(bare)


def _agent_ref(branch):
    name = str(branch)
    if name.startswith("refs/heads/"):
        short = name[len("refs/heads/") :]
    else:
        short = name
    if not short.startswith("agent/") or short == "agent/":
        raise MergeDenied("branch must be agent/<slug> (L-03)")
    if short == "main" or short.endswith("/main"):
        raise MergeDenied("refusing to merge main into itself")
    return "refs/heads/" + short


def _ff_to_main(bare, src_ref, old):
    new = _run_git(["rev-parse", "--verify", "--end-of-options", src_ref], git_dir=bare)
    if old != new:
        try:
            _run_git(["merge-base", "--is-ancestor", old, new], git_dir=bare)
        except MergeDenied as exc:
            raise MergeDenied(
                "refusing non-fast-forward update of main (HI-03)"
            ) from exc
    _run_git(["update-ref", MAIN_REF, new, old], git_dir=bare)


def _squash_to_main(bare, src_ref, old):
    tmpdir = tempfile.mkdtemp(prefix="aios-checker-squash-")
    added = False
    try:
        # Detached so this does not collide with the agent worktree on main.
        _run_git(
            ["worktree", "add", "--detach", "--", tmpdir, MAIN_REF],
            git_dir=bare,
        )
        added = True
        _run_git(["merge", "--squash", "--", src_ref], cwd=tmpdir)
        _run_git(
            [
                "-c",
                "user.name=%s" % CHECKER_NAME,
                "-c",
                "user.email=%s" % CHECKER_EMAIL,
                "commit",
                "--no-edit",
                "-m",
                "squash merge to main",
            ],
            cwd=tmpdir,
        )
        new = _run_git(["rev-parse", "--verify", "--end-of-options", "HEAD"], cwd=tmpdir)
        _run_git(["update-ref", MAIN_REF, new, old], git_dir=bare)
    finally:
        if added:
            try:
                _run_git(
                    ["worktree", "remove", "--force", "--", tmpdir],
                    git_dir=bare,
                )
            except MergeDenied:
                shutil.rmtree(tmpdir, ignore_errors=True)
        elif os.path.isdir(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)


def merge_to_main(repo, branch, mode="ff-only"):
    assert_merge_permitted(mode)
    if not repo or not branch:
        raise MergeDenied("repo and branch are required")
    src_ref = _agent_ref(branch)
    bare = _bare_git_dir(repo)
    old = _run_git(["rev-parse", "--verify", "--end-of-options", MAIN_REF], git_dir=bare)
    if mode == "ff-only":
        _ff_to_main(bare, src_ref, old)
        return
    _squash_to_main(bare, src_ref, old)
