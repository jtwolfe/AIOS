#!/bin/sh
# Clause-first work-runtime bit (HI-15). Sourced by policy and enact.
# Skip is not a yes. JSON string "true" is not a yes. Keep in sync with
# goals.py work_runtime_yes (_ENABLED_LINE / _DISABLED_LINE).

# work_runtime_compute_yes PREFIX
# PREFIX is AIOS_POLICY_ROOT / DESTROOT / empty. Sets WORK_RUNTIME_YES=0|1.
work_runtime_compute_yes() {
  _wr_pfx=${1-}
  WORK_RUNTIME_YES=0
  _wr_clause=$(printf '%s%s' "${_wr_pfx}" /srv/aios/envelope/work-runtime.md)
  _wr_ans=$(printf '%s%s' "${_wr_pfx}" /srv/aios/state/bootstrap-in-progress/answers.json)
  _wr_decided=0
  if [ -f "${_wr_clause}" ]; then
    while IFS= read -r _wr_line || [ -n "${_wr_line}" ]; do
      _wr_lead=${_wr_line%%[![:space:]]*}
      _wr_s=${_wr_line#"${_wr_lead}"}
      case "${_wr_s}" in
        \#*) continue ;;
      esac
      if printf '%s\n' "${_wr_s}" \
        | grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(false|no|0)[[:space:]]*$'; then
        WORK_RUNTIME_YES=0
        _wr_decided=1
        break
      fi
      if printf '%s\n' "${_wr_s}" \
        | grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(true|yes|1)[[:space:]]*$'; then
        WORK_RUNTIME_YES=1
        _wr_decided=1
        break
      fi
    done < "${_wr_clause}"
  fi
  if [ "${_wr_decided}" -eq 0 ] && [ -f "${_wr_ans}" ]; then
    if grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true([,[:space:]}]|$)' "${_wr_ans}" \
      && grep -Eq '"work_runtime"[[:space:]]*:[[:space:]]*true([,[:space:]}]|$)' "${_wr_ans}"; then
      WORK_RUNTIME_YES=1
    fi
  fi
}

# 0 if src is absent or work-runtime is a git worktree (inert after disable).
work_runtime_inert_git() {
  _wr_pfx=${1-}
  _wr_src=$(printf '%s%s' "${_wr_pfx}" /srv/aios/src)
  _wr_tree=$(printf '%s%s' "${_wr_pfx}" /srv/aios/src/work-runtime)
  [ -e "${_wr_src}" ] || return 0
  git -c safe.directory="${_wr_tree}" -C "${_wr_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || return 1
  _wr_inside=$(git -c safe.directory="${_wr_tree}" -C "${_wr_tree}" rev-parse --is-inside-work-tree)
  [ "${_wr_inside}" = true ]
}

# bots_compute_yes PREFIX. Envelope clause only. Sets BOTS_YES=0|1.
bots_compute_yes() {
  _bt_pfx=${1-}
  BOTS_YES=0
  _bt_clause=$(printf '%s%s' "${_bt_pfx}" /srv/aios/envelope/work-runtime-bots.md)
  if [ -f "${_bt_clause}" ]; then
    while IFS= read -r _bt_line || [ -n "${_bt_line}" ]; do
      _bt_lead=${_bt_line%%[![:space:]]*}
      _bt_s=${_bt_line#"${_bt_lead}"}
      case "${_bt_s}" in
        \#*) continue ;;
      esac
      if printf '%s\n' "${_bt_s}" \
        | grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(false|no|0)[[:space:]]*$'; then
        BOTS_YES=0
        break
      fi
      if printf '%s\n' "${_bt_s}" \
        | grep -Eq '^[[:space:]]*enabled[[:space:]]*[:=][[:space:]]*(true|yes|1)[[:space:]]*$'; then
        BOTS_YES=1
        break
      fi
    done < "${_bt_clause}"
  fi
}

# 0 if bots tree is absent or a git worktree (inert after disable).
bots_inert_git() {
  _bt_pfx=${1-}
  _bt_tree=$(printf '%s%s' "${_bt_pfx}" /srv/aios/src/work-runtime-bots)
  [ -e "${_bt_tree}" ] || return 0
  git -c safe.directory="${_bt_tree}" -C "${_bt_tree}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || return 1
  _bt_inside=$(git -c safe.directory="${_bt_tree}" -C "${_bt_tree}" rev-parse --is-inside-work-tree)
  [ "${_bt_inside}" = true ]
}
