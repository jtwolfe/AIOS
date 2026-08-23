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
_ghp='ghp''_[A-Za-z0-9]{36}'
_gho='gho''_[A-Za-z0-9]{36}'
_ghu='ghu''_[A-Za-z0-9]{36}'
_ghs='ghs''_[A-Za-z0-9]{36}'
_ghr='ghr''_[A-Za-z0-9]{36}'
_pat='github''_pat_[A-Za-z0-9_]{22,}'
_aws='AWS''_SECRET''_ACCESS''_KEY[[:space:]]*=[[:space:]]*[^[:space:]]+'
_gtk='GITHUB''_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]]+'
_ght='GH''_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]]+'
# Line-anchored PEM: sibling oracles quote these headers mid-line as grep patterns.
CONTENT_RE="^[[:space:]]*${_beg} ([A-Z0-9]+ )?${_priv}|^[[:space:]]*${_beg} ${_osc}|^[[:space:]]*${_beg} ${_pgp}|^[[:space:]]*${_beg} ${_msk}|^[[:space:]]*untrusted comment: ${_mcom}|${_akia}|${_ghp}|${_gho}|${_ghu}|${_ghs}|${_ghr}|${_pat}|${_aws}|${_gtk}|${_ght}"

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
  case "${_sn_path}" in
    */.aws/credentials|*/.aws/credentials.*) return 0 ;;
  esac
  printf '%s\n' "${_sn_base}" | grep -Fq 'minisign.key' && return 0
  printf '%s\n' "${_sn_base}" | grep -Eq 'id_(rsa|dsa|ecdsa|ed25519)' && return 0
  return 1
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

sort -u "${TREES}" >"${WORK}/trees.u"
while IFS= read -r _tree; do
  [ -n "${_tree}" ] || continue
  find "${_tree}" -type f ! -path '*/.git/*' -print >"${LIST}" 2>/dev/null || true
  while IFS= read -r _f; do
    [ -n "${_f}" ] || continue
    [ -f "${_f}" ] || continue
    is_secret_name "${_f}" && fail "secret file name: ${_f}"
    grep -I -E -q -- "${CONTENT_RE}" "${_f}" 2>/dev/null \
      && fail "secret material in ${_f}"
  done <"${LIST}"
done <"${WORK}/trees.u"

sort -u "${GITS}" >"${WORK}/gits.u"
while IFS= read -r _g; do
  [ -n "${_g}" ] || continue
  [ -d "${_g}" ] || continue
  git --git-dir="${_g}" log --all --name-only --pretty=format: 2>/dev/null \
    >"${LIST}" || true
  while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    is_secret_name "${_p}" && fail "secret file name in git ${_g}: ${_p}"
  done <"${LIST}"
  git --git-dir="${_g}" rev-list --all 2>/dev/null >"${WORK}/revs" || true
  [ -s "${WORK}/revs" ] || continue
  _hit=$(xargs -r git --git-dir="${_g}" grep -I -E -l -e "${CONTENT_RE}" -- \
    <"${WORK}/revs" 2>/dev/null | head -n 1 || true)
  [ -z "${_hit}" ] || fail "secret material in git ${_g} ${_hit}"
done <"${WORK}/gits.u"

exit 0
