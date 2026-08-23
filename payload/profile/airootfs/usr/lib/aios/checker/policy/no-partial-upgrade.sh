#!/bin/sh
# HI-06: a partial upgrade is not a seatbelt (Arch System maintenance).
set -eu

fail() {
  printf 'no-partial-upgrade: %s\n' "$*" >&2
  exit 1
}

# Envelope accept is P5. Until then this is still Harness A: -Syu is a fail.
harness_a() {
  _ans=/srv/aios/state/bootstrap-in-progress/answers.json
  if [ -f "${_ans}" ] && grep -Eq '"accepted"[[:space:]]*:[[:space:]]*true' "${_ans}"; then
    return 1
  fi
  return 0
}

# Clustered short flags: -Syyu counts as sync+refresh+sysupgrade.
# --root/-r/--sysroot exempts pacstrap into a target, not --root / on the live box.
classify_pacman() {
  HAS_S=0
  HAS_Y=0
  HAS_U=0
  HAS_ROOT=0
  ROOT_PATH=
  _want_root=0
  for _tok in ${CMD}; do
    if [ "${_want_root}" -eq 1 ]; then
      case "${_tok}" in
        -*)
          _want_root=0
          ;;
        *)
          ROOT_PATH=${_tok}
          HAS_ROOT=1
          _want_root=0
          continue
          ;;
      esac
    fi
    case "${_tok}" in
      --root|--sysroot|-r)
        HAS_ROOT=1
        _want_root=1
        ;;
      --root=*)
        HAS_ROOT=1
        ROOT_PATH=${_tok#--root=}
        ;;
      --sysroot=*)
        HAS_ROOT=1
        ROOT_PATH=${_tok#--sysroot=}
        ;;
      --sysupgrade) HAS_U=1 ;;
      --sync) HAS_S=1 ;;
      --refresh) HAS_Y=1 ;;
      --*) ;;
      -*)
        _rest=${_tok#-}
        while [ -n "${_rest}" ]; do
          _c=${_rest%${_rest#?}}
          _rest=${_rest#?}
          case "${_c}" in
            S) HAS_S=1 ;;
            y) HAS_Y=1 ;;
            u) HAS_U=1 ;;
            r)
              HAS_ROOT=1
              _want_root=1
              ;;
          esac
        done
        ;;
    esac
  done
}

# Pacstrap into /mnt (etc.). --root / is the live system.
pacstrap_root() {
  [ "${HAS_ROOT}" -eq 1 ] || return 1
  [ -n "${ROOT_PATH}" ] || return 1
  _rp=${ROOT_PATH}
  while [ "${#_rp}" -gt 1 ]; do
    case "${_rp}" in
      */) _rp=${_rp%/} ;;
      *) break ;;
    esac
  done
  [ "${_rp}" != / ] && [ "${_rp}" != . ]
}

# IgnorePkg of linux while the rest moves is the same brick as pacman -S.
scan_ignorepkg() {
  _files=/etc/pacman.conf
  if [ -d /etc/pacman.conf.d ]; then
    for _f in /etc/pacman.conf.d/*.conf; do
      [ -f "${_f}" ] || continue
      _files="${_files} ${_f}"
    done
  fi
  # shellcheck disable=SC2086
  _hits=$(grep -E '^[[:space:]]*IgnorePkg' ${_files} 2>/dev/null || true)
  [ -n "${_hits}" ] || return 0
  printf '%s\n' "${_hits}" | grep -Eq '(^|[[:space:]=])linux(-lts)?([[:space:]]|$)' \
    && fail "IgnorePkg lists linux or linux-lts (HI-06)"
  return 0
}

scan_ignorepkg

for _bin in /usr/lib/aios/bin/firstboot /usr/lib/aios/bin/installer; do
  [ -f "${_bin}" ] || continue
  grep -q -- '-Syu' "${_bin}" && fail "Harness A ${_bin} contains -Syu (L-20)"
done
if [ -f /var/log/aios-firstboot.log ]; then
  grep -q -- '-Syu' /var/log/aios-firstboot.log \
    && fail "firstboot log contains -Syu (L-20)"
fi

# File-level snapper undochange after -Syu leaves the sync db ahead of files
# (snap-pac(8)). v1 rollback is previous ESP generation + matching @, not this.
for _f in \
  /root/.bash_history \
  /root/.ash_history \
  /root/.history \
  /var/log/aios-firstboot.log
do
  [ -f "${_f}" ] || continue
  grep -Eq 'snapper[[:space:]]+([^[:space:]]+[[:space:]]+)*undochange' "${_f}" \
    && fail "snapper undochange recorded in ${_f} (HI-06)"
done
if [ -d /srv/aios/state ]; then
  _uc=$(grep -R -l -- 'undochange' /srv/aios/state 2>/dev/null | head -n 1 || true)
  [ -z "${_uc}" ] || fail "snapper undochange recorded in ${_uc} (HI-06)"
fi

[ -f /var/log/pacman.log ] || fail "pacman.log missing"

# Each Running line is one invocation. Pacstrap --root /mnt is not a live -Syu.
while IFS= read -r _line || [ -n "${_line}" ]; do
  [ -n "${_line}" ] || continue
  CMD=${_line}
  classify_pacman
  if [ "${HAS_S}" -eq 1 ] && [ "${HAS_U}" -eq 1 ]; then
    if [ "${HAS_Y}" -eq 0 ]; then
      fail "pacman -Su without refresh is not a -Syu window: ${_line}"
    fi
    if harness_a; then
      fail "Harness A -Syu: ${_line} (L-20)"
    fi
    continue
  fi
  if [ "${HAS_S}" -eq 1 ] && [ "${HAS_U}" -eq 0 ]; then
    if pacstrap_root; then
      continue
    fi
    if [ "${HAS_Y}" -eq 1 ]; then
      fail "pacman -Sy without -u: ${_line}"
    fi
    fail "pacman -S without a full -Syu window: ${_line}"
  fi
done <<EOF
$(sed -n "s/.*\\[PACMAN\\] Running '\\(.*\\)'\$/\\1/p" /var/log/pacman.log)
EOF

# undochange class: db claims linux files that are not on disk.
if command -v pacman >/dev/null 2>&1; then
  _qk=$(pacman -Qk linux linux-lts 2>/dev/null || true)
  printf '%s\n' "${_qk}" | grep -Eq 'warning|missing' \
    && fail "pacman -Qk linux/linux-lts missing files (undochange class)"
fi

exit 0
