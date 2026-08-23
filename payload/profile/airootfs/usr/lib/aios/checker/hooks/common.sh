# Shared HI-03 / L-03 gate. Sourced by the three git hooks.
# Copied onto checker-owned bare repos; do not exec merge.py from the
# aios-agent-writable worktree. Equivalent of merge.py: only aios-checker
# uid may fast-forward main (squash is a fast-forward of that ref).

deny() {
  printf '%s\n' "$*" >&2
  exit 1
}

# Direct execution is not a hook.
case "${0##*/}" in
  common.sh)
    deny "common.sh is not a git hook (HI-03)"
    ;;
esac

is_zero_oid() {
  case "$1" in
    ''|*[!0]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_checker() {
  _gate_cu=$(id -u aios-checker 2>/dev/null) || return 1
  _gate_u=$(id -u) || return 1
  [ "${_gate_u}" -eq "${_gate_cu}" ]
}

is_agent() {
  _gate_au=$(id -u aios-agent 2>/dev/null) || return 1
  _gate_u=$(id -u) || return 1
  [ "${_gate_u}" -eq "${_gate_au}" ]
}

is_main_ref() {
  [ "$1" = refs/heads/main ]
}

is_agent_ref() {
  case "$1" in
    refs/heads/agent/*) ;;
    *) return 1 ;;
  esac
  _gate_slug=${1#refs/heads/agent/}
  case "${_gate_slug}" in
    ''|main|*/main|*..*) return 1 ;;
  esac
  return 0
}

is_published_ref() {
  is_main_ref "$1" && return 0
  case "$1" in
    refs/tags/*) return 0 ;;
  esac
  return 1
}

# Hook GIT_DIR is this bare repo. Drop worktree/index so merge-base does
# not follow a caller worktree. Keep GIT_QUARANTINE_PATH (pre-receive).
git_repo() {
  (
    unset GIT_WORK_TREE GIT_INDEX_FILE
    if [ -n "${GIT_DIR:-}" ]; then
      git --git-dir="${GIT_DIR}" "$@"
    else
      git "$@"
    fi
  )
}

is_fast_forward() {
  _ff_old=$1
  _ff_new=$2
  is_zero_oid "${_ff_old}" && return 0
  is_zero_oid "${_ff_new}" && return 1
  [ "${_ff_old}" = "${_ff_new}" ] && return 0
  git_repo merge-base --is-ancestor "${_ff_old}" "${_ff_new}" || return 1
  return 0
}

require_commit() {
  _rc_oid=$1
  is_zero_oid "${_rc_oid}" && return 0
  _rc_type=$(git_repo cat-file -t "${_rc_oid}") || return 1
  [ "${_rc_type}" = commit ]
}

check_ref_update() {
  _old=$1
  _new=$2
  _ref=$3
  [ -n "${_old}" ] && [ -n "${_new}" ] && [ -n "${_ref}" ] \
    || deny "malformed ref update (HI-03)"

  if is_main_ref "${_ref}"; then
    is_checker || deny "proposer cannot update main (HI-03)"
    is_zero_oid "${_new}" && deny "refusing delete of main (HI-03)"
    is_zero_oid "${_old}" && deny "refusing create of main (HI-03)"
    require_commit "${_new}" || deny "main must point at a commit (HI-03)"
    is_fast_forward "${_old}" "${_new}" \
      || deny "refusing non-fast-forward of published ref (HI-03)"
    return 0
  fi

  if is_agent; then
    is_agent_ref "${_ref}" || deny "agent may push only refs/heads/agent/* (L-03)"
    return 0
  fi

  if is_checker; then
    if is_published_ref "${_ref}"; then
      is_zero_oid "${_new}" && deny "refusing delete of published ref (HI-03)"
      is_fast_forward "${_old}" "${_new}" \
        || deny "refusing non-fast-forward of published ref (HI-03)"
    fi
    return 0
  fi

  deny "only aios-agent or aios-checker may update refs (HI-03, L-03)"
}
