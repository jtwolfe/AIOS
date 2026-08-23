#!/usr/bin/env bash
# shellcheck disable=SC2034
# Started from archiso releng; DE, enabled sshd, and reflector/choose-mirror stripped.

iso_name="aios"
iso_label="AIOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="AIOS"
iso_application="AIOS live installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="aios"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86,arm64' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/lib/aios/bin/firstboot"]="0:0:755"
  ["/usr/lib/aios/bin/installer"]="0:0:755"
  ["/usr/lib/aios/bin/enact"]="0:0:755"
  ["/usr/lib/aios/bin/aios"]="0:0:755"
  ["/usr/lib/aios/checker/hooks/update"]="0:0:755"
  ["/usr/lib/aios/checker/hooks/pre-receive"]="0:0:755"
  ["/usr/lib/aios/checker/hooks/reference-transaction"]="0:0:755"
)
