# AIOS payload

Archiso profile for the trusted installer image (P1). No desktop.
Unsigned images must not leave the workstation (L-10). Do not pipe a
fetched script into a shell (HI-04).

## Out-of-band verify (P1.2)

From the repository root, after a signed build:

```sh
sha256sum -c payload/hashes.txt
minisign -Vm dist/aios-*.iso -p payload/minisign.pub
```

`payload/hashes.txt` is GNU `sha256sum` text-mode output (64 lowercase
hex, two spaces, path relative to the repository root). It pins shipped
blobs that exist now, including both `pacstrap.x86_64` copies, firstboot,
installer, enact, sysusers, tmpfiles, the installer unit, getty drop-ins,
seeds, the hard-invariants file, and `minisign.pub`. Stubs are allowed;
the hashes still pin whatever is shipped.

The live ISO carries `minisign.pub` and a firstboot `hashes.txt` at
`/usr/lib/aios/` so firstboot can verify before touching disks. That live
list uses ISO paths (relative to `/usr/lib/aios/` or absolute). `build.sh`
signs it when the secret key is present (`hashes.txt.minisig` is
gitignored).

Public key (`payload/minisign.pub`):

```
untrusted comment: minisign public key 2C2CB12A0B9BDF35
RWQ135sLKrEsLCY+gZMn9y/msJqtHA7mW1gsa5R3ckudsjAlRXpHjrbj
```

Compare that file to this page before trusting a signature. The secret
key is operator-local and never in git:

`${XDG_CONFIG_HOME:-$HOME/.config}/aios/minisign.key` (mode 0600).

`build.sh` honours `AIOS_MINISIGN_SECKEY` if set. Otherwise it looks in
`${XDG_CONFIG_HOME:-$HOME/.config}/aios/minisign.key`, then
`~/.minisign/minisign.key`. Under `sudo` it uses the invoking user's
home; `XDG_CONFIG_HOME` is honoured only when it is under that home
(root's XDG is ignored). Do not put the secret under `payload/` or
anywhere a `git add` can see it.

To sign with the in-tree public key, copy the matching secret key out
of band. Do not generate a new pair onto `payload/minisign.pub` — that
overwrites the committed trust anchor and breaks `hashes.txt`. Only
replace `payload/minisign.pub` when rotating the pair, in the same
change as `payload/hashes.txt`. Keep the secret file outside the work
tree. A new pair (rotation or a fresh workstation) is:

```sh
mkdir -p ~/.config/aios
chmod 700 ~/.config/aios
minisign -G -W -p /tmp/aios-minisign.pub -s ~/.config/aios/minisign.key
chmod 600 ~/.config/aios/minisign.key
```

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
`archlinux-bootstrap-2026.08.01-x86_64.tar.zst.sig`. A missing key skips
PGP (the sha256 pin still binds). A bad signature fails the build.

## Build

```sh
sudo ./payload/build.sh
sudo ./payload/build.sh --publish
```

Needs root for the bootstrap chroot and `mkarchiso`. When the secret key
is present, the script installs `minisign` in that same pinned chroot
(no sysupgrade) and signs `dist/aios-*.iso`. Output: `dist/aios-*.iso`
and, when signed, `dist/aios-*.iso.minisig` (gitignored). Work files
under `work/` (gitignored). The script does not sysupgrade.

`--publish` fails closed unless every `dist/aios-*.iso` has a matching
`.minisig` that verifies with `payload/minisign.pub`. A local build
without the secret key still writes the ISO under `dist/` and that file
must not be copied off the workstation (L-10).

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
