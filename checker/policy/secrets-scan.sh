#!/bin/sh
# Extra: a token in git is not reconstructible (L-16). Fail closed.
set -eu
LC_ALL=C
export LC_ALL

# Hooks set GIT_DIR; named --git-dir/-C must win.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

fail() {
  printf 'secrets-scan: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Pieces stay split so this file does not match the assembled pattern.
_beg='-----BEGIN'
_priv='PRIVATE KEY-----'
_osc='OPENSSH PRIVATE KEY-----'
_pgp='PGP PRIVATE KEY BLOCK-----'
_msk='MINISIGN SECRET KEY-----'
_mcom='minisign encrypted secret key'
_akia='AKI''A[0-9A-Z]{16}'
_asia='ASI''A[0-9A-Z]{16}'
_ghp='ghp''_[A-Za-z0-9]{36}'
_gho='gho''_[A-Za-z0-9]{36}'
_ghu='ghu''_[A-Za-z0-9]{36}'
_ghs='ghs''_[A-Za-z0-9]{36}'
_ghr='ghr''_[A-Za-z0-9]{36}'
_pat='github''_pat_[A-Za-z0-9_]{22,}'
# Line-anchored PEM: sibling oracles quote these headers mid-line as grep patterns.
CONTENT_RE="^[[:space:]]*${_beg} ([A-Z0-9]+ )?${_priv}|^[[:space:]]*${_beg} ${_osc}|^[[:space:]]*${_beg} ${_pgp}|^[[:space:]]*${_beg} ${_msk}|^[[:space:]]*untrusted comment: ${_mcom}|${_akia}|${_asia}|${_ghp}|${_gho}|${_ghu}|${_ghs}|${_ghr}|${_pat}"
# Case-insensitive via grep -i. Live xAI prefix is a P4 must-close (L-16).
_env_aws='aws''_secret''_access''_key[[:space:]]*=[[:space:]]*[^[:space:]]+'
_env_gtk='github''_token[[:space:]]*=[[:space:]]*[^[:space:]]+'
_env_ght='gh''_token[[:space:]]*=[[:space:]]*[^[:space:]]+'
ENV_RE="${_env_aws}|${_env_gtk}|${_env_ght}"

# Basename token, not surrounding path: nested keys still match; prefix/suffix
# on the filename still match; a path fragment like docs/id_rsa.pub does not.
is_secret_name() {
  _sn_path=$1
  _sn_base=${_sn_path##*/}
  case "${_sn_base}" in
    *.pub) return 1 ;;
    .env.example|.env.sample|.env.template) return 1 ;;
  esac
  case "${_sn_base}" in
    .env|.env.*) return 0 ;;
    .netrc|.netrc.*) return 0 ;;
  esac
  # Git-relative `.aws/credentials` has no leading slash; worktree paths do.
  case "${_sn_path}" in
    .aws/credentials|.aws/credentials.*|*/.aws/credentials|*/.aws/credentials.*)
      return 0
      ;;
  esac
  printf '%s\n' "${_sn_base}" | grep -Fq 'minisign.key' && return 0
  printf '%s\n' "${_sn_base}" | grep -Eq 'id_(rsa|dsa|ecdsa|ed25519)' && return 0
  return 1
}

# grep 0=match 1=no match; anything else cannot-scan (fail closed).
# $3 is -i or empty; never pass -- (it would eat -E).
grep_q() {
  _gq_re=$1
  _gq_f=$2
  _gq_i=${3:-}
  _rc=0
  if [ "${_gq_i}" = -i ]; then
    grep -I -i -E -q -- "${_gq_re}" "${_gq_f}" || _rc=$?
  else
    grep -I -E -q -- "${_gq_re}" "${_gq_f}" || _rc=$?
  fi
  case "${_rc}" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "cannot read ${_gq_f}" ;;
  esac
}

scan_secret_content() {
  _cf=$1
  _cl=$2
  grep_q "${CONTENT_RE}" "${_cf}" && fail "secret material in ${_cl}"
  grep_q "${ENV_RE}" "${_cf}" -i && fail "secret material in ${_cl}"
  return 0
}

# Trees before pathspecs: `git grep -e <pattern> <tree>` not `git grep -- <sha>`.
git_grep_q() {
  _gd=$1
  _pat=$2
  _rev=$3
  _gq_i=${4:-}
  _rc=0
  if [ "${_gq_i}" = -i ]; then
    git --git-dir="${_gd}" grep -I -i -E -q -e "${_pat}" "${_rev}" || _rc=$?
  else
    git --git-dir="${_gd}" grep -I -E -q -e "${_pat}" "${_rev}" || _rc=$?
  fi
  case "${_rc}" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "git grep failed in ${_gd} ${_rev} (exit ${_rc})" ;;
  esac
}

WORK=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "${WORK}"' EXIT
TREES="${WORK}/trees"
GITS="${WORK}/gits"
LIST="${WORK}/list"
: >"${TREES}"
: >"${GITS}"
SCANNED=0

add_tree() {
  [ -n "${1:-}" ] || return 0
  [ -d "$1" ] || return 0
  _t=$(CDPATH= cd -- "$1" && pwd) || return 0
  case "${_t}" in
    /|/usr|/usr/lib|/usr/local|/home|/etc|/var|/tmp|/proc|/sys|/dev) return 0 ;;
  esac
  printf '%s\n' "${_t}" >>"${TREES}"
  SCANNED=$((SCANNED + 1))
}

add_git() {
  [ -n "${1:-}" ] || return 0
  if [ -d "$1/objects" ]; then
    _g=$(CDPATH= cd -- "$1" && pwd) || return 0
    printf '%s\n' "${_g}" >>"${GITS}"
    SCANNED=$((SCANNED + 1))
    return 0
  fi
  [ -d "$1" ] || return 0
  _g=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  [ -n "${_g}" ] || return 0
  printf '%s\n' "${_g}" >>"${GITS}"
  SCANNED=$((SCANNED + 1))
}

_top=$(CDPATH= cd -- "${here}/../.." && pwd)
add_tree "${_top}"
add_tree /srv/aios
add_tree /usr/lib/aios
add_git "${_top}"
add_git /srv/aios/checker
add_git /srv/aios/state
add_git /srv/aios/envelope
add_git /srv/aios/memory
add_git /srv/aios/skills
add_git /srv/aios/agent
add_git /srv/aios/seeds
if [ -d /srv/aios/git ]; then
  for _d in /srv/aios/git/*.git; do
    [ -d "${_d}" ] || continue
    add_git "${_d}"
  done
fi

[ "${SCANNED}" -gt 0 ] || fail "no payload or git tree to scan"

scan_worktree_path() {
  _f=$1
  is_secret_name "${_f}" && fail "secret file name: ${_f}"
  # Dangling non-secret names (ISO systemd .wants) are not a leak.
  if [ -L "${_f}" ] && [ ! -e "${_f}" ]; then
    return 0
  fi
  [ -r "${_f}" ] || fail "unreadable: ${_f}"
  [ -f "${_f}" ] || return 0
  scan_secret_content "${_f}" "${_f}"
}

sort -u "${TREES}" >"${WORK}/trees.u"
while IFS= read -r _tree; do
  [ -n "${_tree}" ] || continue
  _rc=0
  find "${_tree}" \( -type f -o -type l \) ! -path '*/.git/*' -print \
    >"${LIST}" 2>"${WORK}/find.err" || _rc=$?
  if [ "${_rc}" -ne 0 ] || [ -s "${WORK}/find.err" ]; then
    fail "find failed under ${_tree}: $(tr '\n' ' ' <"${WORK}/find.err")"
  fi
  while IFS= read -r _f; do
    [ -n "${_f}" ] || continue
    scan_worktree_path "${_f}"
  done <"${LIST}"
done <"${WORK}/trees.u"

sort -u "${GITS}" >"${WORK}/gits.u"
while IFS= read -r _g; do
  [ -n "${_g}" ] || continue
  [ -d "${_g}" ] || fail "git dir missing: ${_g}"
  git --git-dir="${_g}" log --all --name-only --pretty=format: \
    >"${LIST}" 2>"${WORK}/git.err" || fail "git log failed in ${_g}: $(tr '\n' ' ' <"${WORK}/git.err")"
  while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    is_secret_name "${_p}" && fail "secret file name in git ${_g}: ${_p}"
  done <"${LIST}"
  git --git-dir="${_g}" rev-list --all >"${WORK}/revs" 2>"${WORK}/git.err" \
    || fail "git rev-list failed in ${_g}: $(tr '\n' ' ' <"${WORK}/git.err")"
  while IFS= read -r _rev; do
    [ -n "${_rev}" ] || continue
    git_grep_q "${_g}" "${CONTENT_RE}" "${_rev}" \
      && fail "secret material in git ${_g} ${_rev}"
    git_grep_q "${_g}" "${ENV_RE}" "${_rev}" -i \
      && fail "secret material in git ${_g} ${_rev}"
  done <"${WORK}/revs"
done <"${WORK}/gits.u"

exit 0
