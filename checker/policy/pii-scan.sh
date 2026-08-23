#!/bin/sh
# Extra: the operator is a role; personal identifiers are not in the tree.
set -eu
LC_ALL=C
export LC_ALL

# Hooks set GIT_DIR; named --git-dir/-C must win.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

fail() {
  printf 'pii-scan: %s\n' "$*" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# No-dot hosts (aios@localhost) are identities; skip only known roles, not the line.
LOCAL_RE='[A-Za-z0-9._%+-]+@(localhost|aios\.local)'
UNIT_RE='^[A-Za-z0-9._%+-]+@[A-Za-z0-9_.-]+\.(service|socket|device|mount|automount|swap|target|path|timer|slice|scope)$'
PHONE_RE='(^|[^0-9])[0-9]{3}[-.][0-9]{3}[-.][0-9]{4}([^0-9]|$)|(^|[^0-9])\+[0-9][-0-9(). ]{8,18}[0-9]'
STREET_RE='[0-9]+[[:space:]]+[A-Z][A-Za-z-]+[[:space:]]+(Street|St\.|Avenue|Ave\.|Road|Rd\.|Boulevard|Blvd\.|Lane|Ln\.|Drive|Dr\.|Court|Ct\.|Place|Pl\.)'
HOME_RE='/home/[A-Za-z0-9._-]+'
USERS_RE='/Users/[A-Za-z0-9._-]+'
WIN_RE='[Cc]:[\\/]Users[\\/][A-Za-z0-9._-]+'
MAC_RE='(^|[^0-9A-Fa-f])[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}([^0-9A-Fa-f]|$)'

# Assembled so this file does not contain role@host as a grep-able token.
_at='@'
_d_local='localhost'
_d_aios='aios''.local'

# Token, not surrounding path text: getty@tty1.service.d must not hide a real address.
is_role_email() {
  _em=$1
  printf '%s\n' "${_em}" | grep -Eq -- "${UNIT_RE}" && return 0
  case "${_em}" in
    aios"${_at}${_d_local}"|operator"${_at}${_d_local}"|agent"${_at}${_d_local}"|root"${_at}${_d_local}") return 0 ;;
    aios-agent"${_at}${_d_local}"|aios-checker"${_at}${_d_local}"|aios-work"${_at}${_d_local}") return 0 ;;
    aios"${_at}${_d_aios}"|operator"${_at}${_d_aios}"|agent"${_at}${_d_aios}"|root"${_at}${_d_aios}") return 0 ;;
    aios-agent"${_at}${_d_aios}"|aios-checker"${_at}${_d_aios}"|aios-work"${_at}${_d_aios}") return 0 ;;
  esac
  return 1
}

is_role_home() {
  case "$1" in
    operator|aios|aios-agent|aios-checker|aios-work) return 0 ;;
    # Arch pacman.conf example path, not a person.
    custompkgs|.snapshots|user|username|git|http|nobody|ftp|mail) return 0 ;;
    systemd-*) return 0 ;;
    Shared|Guest|Public|Default) return 0 ;;
  esac
  return 1
}

is_role_name() {
  case "$1" in
    operator|AIOS|'AIOS agent'|aios-agent|aios-checker|aios-work) return 0 ;;
    'Workstation implementer') return 0 ;;
  esac
  return 1
}

WORK=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "${WORK}"' EXIT
TREES="${WORK}/trees"
GITS="${WORK}/gits"
LIST="${WORK}/list"
TOKS="${WORK}/toks"
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

scan_emails() {
  _sf=$1
  : >"${TOKS}"
  grep -I -E -h -o -- "${EMAIL_RE}" "${_sf}" 2>/dev/null >>"${TOKS}" || true
  grep -I -E -h -o -- "${LOCAL_RE}" "${_sf}" 2>/dev/null >>"${TOKS}" || true
  [ -s "${TOKS}" ] || return 0
  while IFS= read -r _tok; do
    [ -n "${_tok}" ] || continue
    is_role_email "${_tok}" && continue
    fail "email in ${_sf}: ${_tok}"
  done <"${TOKS}"
}

scan_homes() {
  _sf=$1
  : >"${TOKS}"
  grep -I -E -h -o -- "${HOME_RE}" "${_sf}" 2>/dev/null >>"${TOKS}" || true
  grep -I -E -h -o -- "${USERS_RE}" "${_sf}" 2>/dev/null >>"${TOKS}" || true
  grep -I -E -h -o -- "${WIN_RE}" "${_sf}" 2>/dev/null >>"${TOKS}" || true
  [ -s "${TOKS}" ] || return 0
  while IFS= read -r _tok; do
    [ -n "${_tok}" ] || continue
    _u=${_tok##*/}
    _u=${_u##*\\}
    is_role_home "${_u}" && continue
    fail "home-machine path in ${_sf}: ${_tok}"
  done <"${TOKS}"
}

scan_file() {
  _sf=$1
  [ -f "${_sf}" ] || return 0
  [ -r "${_sf}" ] || return 0
  scan_emails "${_sf}"
  scan_homes "${_sf}"
  grep -I -E -q -- "${PHONE_RE}" "${_sf}" 2>/dev/null \
    && fail "phone in ${_sf}"
  grep -I -E -q -- "${STREET_RE}" "${_sf}" 2>/dev/null \
    && fail "street address in ${_sf}"
  grep -I -E -q -- "${MAC_RE}" "${_sf}" 2>/dev/null \
    && fail "MAC address in ${_sf}"
  if [ "${_sf##*/}" = hostname ]; then
    _hn=$(grep -v '^[[:space:]]*#' "${_sf}" | grep -v '^[[:space:]]*$' | head -n 1 | tr -d '\r' || true)
    case "${_hn}" in
      ''|aios|localhost) ;;
      *) fail "home-machine hostname in ${_sf}: ${_hn}" ;;
    esac
  fi
  # Identity fields only. Title Case English ("Arch Linux") is not a name census.
  if grep -I -E -q -- '^[[:space:]]*user\.name[[:space:]]*=' "${_sf}" 2>/dev/null; then
    _n=$(grep -I -E -- '^[[:space:]]*user\.name[[:space:]]*=' "${_sf}" | head -n 1 | sed 's/.*=[[:space:]]*//')
    is_role_name "${_n}" || fail "personal name in ${_sf}: ${_n}"
  fi
  if grep -I -E -q -- '^(Signed-off-by|Co-authored-by):' "${_sf}" 2>/dev/null; then
    _n=$(grep -I -E -- '^(Signed-off-by|Co-authored-by):' "${_sf}" | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*<.*//')
    is_role_name "${_n}" || fail "personal name in ${_sf}: ${_n}"
  fi
  return 0
}

sort -u "${TREES}" >"${WORK}/trees.u"
while IFS= read -r _tree; do
  [ -n "${_tree}" ] || continue
  find "${_tree}" -type f ! -path '*/.git/*' -print >"${LIST}" 2>/dev/null || true
  while IFS= read -r _f; do
    [ -n "${_f}" ] || continue
    scan_file "${_f}"
  done <"${LIST}"
done <"${WORK}/trees.u"

# Blobs, not author/committer: those metadata fields are not the tree.
sort -u "${GITS}" >"${WORK}/gits.u"
while IFS= read -r _g; do
  [ -n "${_g}" ] || continue
  [ -d "${_g}" ] || continue
  git --git-dir="${_g}" rev-list --all 2>/dev/null >"${WORK}/revs" || true
  [ -s "${WORK}/revs" ] || continue
  : >"${TOKS}"
  # git grep -o prints rev:path:token; take the token, not the path.
  xargs -r git --git-dir="${_g}" grep -I -E -o -e "${EMAIL_RE}" -- \
    <"${WORK}/revs" 2>/dev/null | sed 's/.*://' >>"${TOKS}" || true
  xargs -r git --git-dir="${_g}" grep -I -E -o -e "${LOCAL_RE}" -- \
    <"${WORK}/revs" 2>/dev/null | sed 's/.*://' >>"${TOKS}" || true
  [ -s "${TOKS}" ] || continue
  sort -u "${TOKS}" >"${WORK}/toks.u"
  while IFS= read -r _tok; do
    [ -n "${_tok}" ] || continue
    is_role_email "${_tok}" && continue
    fail "email in git ${_g}: ${_tok}"
  done <"${WORK}/toks.u"
done <"${WORK}/gits.u"

exit 0
