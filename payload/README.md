# AIOS payload

Archiso profile for the trusted installer image (P1). No desktop. Unsigned
images must not leave the workstation (L-10). Minisign out-of-band steps
land in P1.2.

## Pinned bootstrap (hour 1)

Option B: the dated official bootstrap blob on the Arch Linux Archive.

- Version: `2026.08.01`
- URL: `https://archive.archlinux.org/iso/2026.08.01/archlinux-bootstrap-2026.08.01-x86_64.tar.zst`
- SHA-256: `9600cef264af08899eff8f8b9bb2dd141c748a0038b651256d335e489a8dd2f6`
- Official listing: `https://archive.archlinux.org/iso/2026.08.01/sha256sums.txt`
- Pacman freeze used by `build.sh`: `https://archive.archlinux.org/repos/2026/08/01/$repo/os/$arch`

Do not replace the URL with an undated alias. `payload/build.sh` fails closed
if the downloaded file’s sha256 is not exactly the pin above, or if that pin
does not match `sha256sums.txt` in the same directory.

Verify a local copy:

```sh
printf '%s  %s\n' \
  9600cef264af08899eff8f8b9bb2dd141c748a0038b651256d335e489a8dd2f6 \
  archlinux-bootstrap-2026.08.01-x86_64.tar.zst | sha256sum -c
```

If GnuPG already has the Arch ISO signing key, `build.sh` also checks
`archlinux-bootstrap-2026.08.01-x86_64.tar.zst.sig`. Missing key is not a
pass: the sha256 pin still binds.

## Build

```sh
sudo ./payload/build.sh
```

Needs root for the bootstrap chroot and `mkarchiso`. Output:
`dist/aios-*.iso` (gitignored). Work files under `work/` (gitignored).
The script does not sysupgrade.

## Profile

`payload/profile/` started from archiso `configs/releng` (archiso
`f900196af8f293ec7e4ef452b368b9db8012d79f`) and was stripped: no DE, no
enabled `sshd`, no reflector/choose-mirror, no cloud-init, no guest-agent
units.

- `packages.x86_64` — live ISO set (locked installed set plus mkarchiso /
  firstboot extras).
- `pacstrap.x86_64` — installed set. Same bytes at
  `airootfs/usr/lib/aios/pacstrap.x86_64`.
- `pacman.conf` — official `[core]` / `[extra]` only.
