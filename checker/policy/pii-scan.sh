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
NAME_RE='^[[:space:]]*user\.name[[:space:]]*='
TRAILER_RE='^(Signed-off-by|Co-authored-by):'

# Assembled so this file does not contain role@host as a grep-able token.
_at='@'
_d_local='localhost'
_d_aios='aios''.local'

# Token, not surrounding path text: getty@tty1.service.d must not hide a real address.
is_role_email() {
  _em=$1
  printf '%s\n' "${_em}" | grep -Eq -- "${UNIT_RE}" && return 0
  # SSH remote (git at github.com), not a person. Whole token only.
  case "${_em}" in
    git"${_at}"*) return 0 ;;
  esac
  # RFC 2606 / regex-docs hosts, not a person. Domain of the token only.
  _dom=${_em#*@}
  case "${_dom}" in
    example.com|example.org|example.net|host.tld|domain.tld) return 0 ;;
  esac
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
    aios|operator|AIOS|'AIOS agent'|aios-agent|aios-checker|aios-work) return 0 ;;
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
LINES="${WORK}/lines"
BLOB="${WORK}/blob"
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

# grep 0=match 1=no match; anything else cannot-scan (fail closed).
grep_q() {
  _gq_re=$1
  _gq_f=$2
  _rc=0
  grep -I -E -q -- "${_gq_re}" "${_gq_f}" || _rc=$?
  case "${_rc}" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "cannot read ${_gq_f}" ;;
  esac
}

grep_o() {
  _go_re=$1
  _go_f=$2
  _go_out=$3
  _rc=0
  grep -I -E -h -o -- "${_go_re}" "${_go_f}" >>"${_go_out}" || _rc=$?
  case "${_rc}" in
    0|1) return 0 ;;
    *) fail "cannot read ${_go_f}" ;;
  esac
}

grep_lines() {
  _gl_re=$1
  _gl_f=$2
  _gl_out=$3
  _rc=0
  grep -I -E -- "${_gl_re}" "${_gl_f}" >"${_gl_out}" || _rc=$?
  case "${_rc}" in
    0|1) return 0 ;;
    *) fail "cannot read ${_gl_f}" ;;
  esac
}

scan_emails() {
  _sf=$1
  _sl=$2
  : >"${TOKS}"
  grep_o "${EMAIL_RE}" "${_sf}" "${TOKS}"
  grep_o "${LOCAL_RE}" "${_sf}" "${TOKS}"
  [ -s "${TOKS}" ] || return 0
  while IFS= read -r _tok; do
    [ -n "${_tok}" ] || continue
    is_role_email "${_tok}" && continue
    fail "email in ${_sl}: ${_tok}"
  done <"${TOKS}"
}

scan_homes() {
  _sf=$1
  _sl=$2
  : >"${TOKS}"
  grep_o "${HOME_RE}" "${_sf}" "${TOKS}"
  grep_o "${USERS_RE}" "${_sf}" "${TOKS}"
  grep_o "${WIN_RE}" "${_sf}" "${TOKS}"
  [ -s "${TOKS}" ] || return 0
  while IFS= read -r _tok; do
    [ -n "${_tok}" ] || continue
    _u=${_tok##*/}
    _u=${_u##*\\}
    is_role_home "${_u}" && continue
    fail "home-machine path in ${_sl}: ${_tok}"
  done <"${TOKS}"
}

scan_file() {
  _sf=$1
  _sl=${2:-$1}
  scan_emails "${_sf}" "${_sl}"
  scan_homes "${_sf}" "${_sl}"
  grep_q "${PHONE_RE}" "${_sf}" && fail "phone in ${_sl}"
  grep_q "${STREET_RE}" "${_sf}" && fail "street address in ${_sl}"
  grep_q "${MAC_RE}" "${_sf}" && fail "MAC address in ${_sl}"
  _base=${_sl##*/}
  if [ "${_base}" = hostname ]; then
    _hn=$(grep -v '^[[:space:]]*#' "${_sf}" | grep -v '^[[:space:]]*$' | head -n 1 | tr -d '\r' || true)
    case "${_hn}" in
      ''|aios|localhost) ;;
      *) fail "home-machine hostname in ${_sl}: ${_hn}" ;;
    esac
  fi
  # Identity fields only. Title Case English ("Arch Linux") is not a name census.
  grep_lines "${NAME_RE}" "${_sf}" "${LINES}"
  while IFS= read -r _line; do
    [ -n "${_line}" ] || continue
    _n=${_line#*=}
    _n=$(printf '%s\n' "${_n}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    is_role_name "${_n}" || fail "personal name in ${_sl}: ${_n}"
  done <"${LINES}"
  grep_lines "${TRAILER_RE}" "${_sf}" "${LINES}"
  while IFS= read -r _line; do
    [ -n "${_line}" ] || continue
    _n=${_line#*:}
    _n=$(printf '%s\n' "${_n}" | sed 's/^[[:space:]]*//;s/[[:space:]]*<.*//;s/[[:space:]]*$//')
    is_role_name "${_n}" || fail "personal name in ${_sl}: ${_n}"
  done <"${LINES}"
  return 0
}

scan_worktree_path() {
  _f=$1
  # Dangling non-secret names (ISO systemd .wants) are not PII.
  if [ -L "${_f}" ] && [ ! -e "${_f}" ]; then
    return 0
  fi
  [ -r "${_f}" ] || fail "unreadable: ${_f}"
  [ -f "${_f}" ] || return 0
  scan_file "${_f}" "${_f}"
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

# git grep <pattern> <tree> — SHAs are trees, never pathspecs after --.
git_grep_run() {
  _gd=$1
  _pat=$2
  _rev=$3
  _out=$4
  _mode=$5
  _rc=0
  case "${_mode}" in
    o) git --git-dir="${_gd}" grep -I -E -o -e "${_pat}" "${_rev}" >"${_out}" || _rc=$? ;;
    l) git --git-dir="${_gd}" grep -I -E -e "${_pat}" "${_rev}" >"${_out}" || _rc=$? ;;
    q) git --git-dir="${_gd}" grep -I -E -q -e "${_pat}" "${_rev}" || _rc=$? ;;
    *) fail "internal git_grep_run mode ${_mode}" ;;
  esac
  case "${_rc}" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "git grep failed in ${_gd} ${_rev} (exit ${_rc})" ;;
  esac
}

# Drop rev:path: so the token is the last field, not the surrounding path.
git_toks() {
  sed 's/^[^:]*:[^:]*://' "$1"
}

scan_git_rev() {
  _g=$1
  _rev=$2
  _lab="${_g}:${_rev}"
  if git_grep_run "${_g}" "${EMAIL_RE}" "${_rev}" "${WORK}/graw" o; then
    git_toks "${WORK}/graw" >"${TOKS}"
    while IFS= read -r _tok; do
      [ -n "${_tok}" ] || continue
      is_role_email "${_tok}" && continue
      fail "email in git ${_lab}: ${_tok}"
    done <"${TOKS}"
  fi
  if git_grep_run "${_g}" "${LOCAL_RE}" "${_rev}" "${WORK}/graw" o; then
    git_toks "${WORK}/graw" >"${TOKS}"
    while IFS= read -r _tok; do
      [ -n "${_tok}" ] || continue
      is_role_email "${_tok}" && continue
      fail "email in git ${_lab}: ${_tok}"
    done <"${TOKS}"
  fi
  if git_grep_run "${_g}" "${HOME_RE}" "${_rev}" "${WORK}/graw" o; then
    git_toks "${WORK}/graw" >"${TOKS}"
    while IFS= read -r _tok; do
      [ -n "${_tok}" ] || continue
      _u=${_tok##*/}
      _u=${_u##*\\}
      is_role_home "${_u}" && continue
      fail "home-machine path in git ${_lab}: ${_tok}"
    done <"${TOKS}"
  fi
  if git_grep_run "${_g}" "${USERS_RE}" "${_rev}" "${WORK}/graw" o; then
    git_toks "${WORK}/graw" >"${TOKS}"
    while IFS= read -r _tok; do
      [ -n "${_tok}" ] || continue
      _u=${_tok##*/}
      is_role_home "${_u}" && continue
      fail "home-machine path in git ${_lab}: ${_tok}"
    done <"${TOKS}"
  fi
  if git_grep_run "${_g}" "${WIN_RE}" "${_rev}" "${WORK}/graw" o; then
    git_toks "${WORK}/graw" >"${TOKS}"
    while IFS= read -r _tok; do
      [ -n "${_tok}" ] || continue
      _u=${_tok##*/}
      _u=${_u##*\\}
      is_role_home "${_u}" && continue
      fail "home-machine path in git ${_lab}: ${_tok}"
    done <"${TOKS}"
  fi
  git_grep_run "${_g}" "${PHONE_RE}" "${_rev}" "${WORK}/graw" q \
    && fail "phone in git ${_lab}"
  git_grep_run "${_g}" "${STREET_RE}" "${_rev}" "${WORK}/graw" q \
    && fail "street address in git ${_lab}"
  git_grep_run "${_g}" "${MAC_RE}" "${_rev}" "${WORK}/graw" q \
    && fail "MAC address in git ${_lab}"
  if git_grep_run "${_g}" "${NAME_RE}" "${_rev}" "${WORK}/graw" l; then
    git_toks "${WORK}/graw" >"${LINES}"
    while IFS= read -r _line; do
      [ -n "${_line}" ] || continue
      _n=${_line#*=}
      _n=$(printf '%s\n' "${_n}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      is_role_name "${_n}" || fail "personal name in git ${_lab}: ${_n}"
    done <"${LINES}"
  fi
  if git_grep_run "${_g}" "${TRAILER_RE}" "${_rev}" "${WORK}/graw" l; then
    git_toks "${WORK}/graw" >"${LINES}"
    while IFS= read -r _line; do
      [ -n "${_line}" ] || continue
      _n=${_line#*:}
      _n=$(printf '%s\n' "${_n}" | sed 's/^[[:space:]]*//;s/[[:space:]]*<.*//;s/[[:space:]]*$//')
      is_role_name "${_n}" || fail "personal name in git ${_lab}: ${_n}"
    done <"${LINES}"
  fi
  git --git-dir="${_g}" ls-tree -r --name-only "${_rev}" >"${LIST}" 2>"${WORK}/git.err" \
    || fail "git ls-tree failed in ${_g} ${_rev}: $(tr '\n' ' ' <"${WORK}/git.err")"
  while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    [ "${_p##*/}" = hostname ] || continue
    git --git-dir="${_g}" cat-file blob "${_rev}:${_p}" >"${BLOB}" 2>"${WORK}/git.err" \
      || fail "git cat-file failed ${_g} ${_rev}:${_p}: $(tr '\n' ' ' <"${WORK}/git.err")"
    _hn=$(grep -v '^[[:space:]]*#' "${BLOB}" | grep -v '^[[:space:]]*$' | head -n 1 | tr -d '\r' || true)
    case "${_hn}" in
      ''|aios|localhost) ;;
      *) fail "home-machine hostname in git ${_lab}:${_p}: ${_hn}" ;;
    esac
  done <"${LIST}"
}

# Blobs, not author/committer: those metadata fields are not the tree.
sort -u "${GITS}" >"${WORK}/gits.u"
while IFS= read -r _g; do
  [ -n "${_g}" ] || continue
  [ -d "${_g}" ] || fail "git dir missing: ${_g}"
  git --git-dir="${_g}" rev-list --all >"${WORK}/revs" 2>"${WORK}/git.err" \
    || fail "git rev-list failed in ${_g}: $(tr '\n' ' ' <"${WORK}/git.err")"
  while IFS= read -r _rev; do
    [ -n "${_rev}" ] || continue
    scan_git_rev "${_g}" "${_rev}"
  done <"${WORK}/revs"
done <"${WORK}/gits.u"

exit 0
